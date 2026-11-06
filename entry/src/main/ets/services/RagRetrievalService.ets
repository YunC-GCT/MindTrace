/**
 * RagRetrievalService.ets — RAG 检索：多路召回 + RRF 融合
 *
 * 路径: entry/src/main/ets/services/RagRetrievalService.ets
 * 职责: 在 MindTrace.db 上做本地检索，五路取候选后按名次融合：
 *       整句 FTS5 trigram（≥3 字 MATCH / <3 字 LIKE）、数学签名直查、
 *       词 OR 扩展、短词 LIKE 兜底、chunk 向量余弦（NoteVectorIndex）。
 *       供 NoteEvidenceService 作为首选召回（失败/无命中回退既有 note.search）。
 * 依赖: @kit.ArkData / common（QueryTerms / MathSignature / RrfFusion） /
 *       ./RagQueryPlan（纯函数） / ./QueryKeywordExtractor / ./NoteVectorIndex
 *
 * 约束:
 *   - **不 import 受限 Kit**（DataAugmentationKit 的探针在 RagKitProbe.ets，仅调试 harness 用）。
 *   - 任何失败返回空数组（调用方负责降级），不抛异常打断回答。
 *
 * 数据流:
 *   knowledge_unit 写入/更新/删除 → note_fts + rag_chunk（事务内）/ rag_embedding（post-commit）
 *   NoteEvidenceService.build(query) → search(query, topK) → RagHit[] → join knowledge_unit
 */
import { relationalStore } from '@kit.ArkData';
import { extractMathSignature, fuseRrf, mergeQueryTerms, planQueryTerms } from 'common';
import type { RrfChannel } from 'common';
import { QueryKeywordExtractor } from './QueryKeywordExtractor';
import { NoteVectorIndex } from './NoteVectorIndex';
import type { VectorHit } from './NoteVectorIndex';
import { EmbeddingRuntime } from './EmbeddingRuntime';
import { QueryRewriter } from './QueryRewriter';
import { planRagQuery, planShortTermQuery, planTermQuery, RagQueryPlan, RagTermQueryPlan } from './RagQueryPlan';

const PROBE_FTS_TABLE: string = 'note_fts';
const PROBE_SEED_TEXT: string = '函数在一点的连续性 极限 连续函数';
const PROBE_QUERY: string = '连续性';

// RRF 分路权重：精确整句与数学签名最可信，词 OR 次之，短词 LIKE 只作兜底。
// 权重只影响「多路同时命中时的排序」，不改变单路召回。
const CHANNEL_WEIGHT_WHOLE: number = 3;
const CHANNEL_WEIGHT_SIGNATURE: number = 3;
const CHANNEL_WEIGHT_TERMS: number = 2;
const CHANNEL_WEIGHT_SHORT: number = 1;
const CHANNEL_WEIGHT_VECTOR: number = 2;
// 改写关键词是最贴近语义的检索词，给与「整句/签名」同级的权重。
const CHANNEL_WEIGHT_REWRITE: number = 3;
// 向量头部差距小于这个值说明分不开——此时才值得花一次 LLM 调用去改写查询。
const AMBIGUOUS_HEAD_GAP: number = 0.03;
// 2026-11-05 真机实测：词面向量分不开相关与无关（无关查询 0.163 压过相关 0.123），
// 因此词面通道不进融合；只有配置了云端稠密模型才开启（EmbeddingRuntime.isDense）。
// 每路多取一些候选再融合：融合的是名次，候选池太窄会让名次失真。
const FUSION_OVERFETCH: number = 3;

export interface RagHit {
  unitId: string;
  title: string;
  content: string;
  subject: string;
  chapter: string;
  score?: number;
}

export interface RagFtsDiagnostic {
  ok: boolean;
  hits: number;
  message: string;
}

export class RagRetrievalService {
  /**
   * RAG 检索：多路召回 + RRF 融合。
   * 五路并行取候选（整句、数学签名、词 OR、短词 LIKE、向量），按名次融合后截断 TopK。
   * 相比「命中即返回」的级联，弱召回通道的精确命中不会再被前一路的普通命中挤掉。
   * 任何失败返回空数组（由调用方回退 note.search）。
   */
  static async search(store: relationalStore.RdbStore, query: string, topK: number): Promise<RagHit[]> {
    const trimmed: string = query.trim();
    if (trimmed.length === 0 || topK <= 0) {
      return [];
    }
    const fetchK: number = topK * FUSION_OVERFETCH;
    const byId: Map<string, RagHit> = new Map<string, RagHit>();
    const channels: RrfChannel[] = [];

    const plan: RagQueryPlan = planRagQuery(trimmed);
    RagRetrievalService.pushChannel(channels, CHANNEL_WEIGHT_WHOLE,
      await RagRetrievalService.runWholeQuery(store, plan, trimmed, fetchK), byId);

    // 数学签名直出：不同措辞的同一道题（「两个 21 的和」↔「计算 21 加 21」）靠签名命中。
    const signature: string = extractMathSignature(trimmed);
    if (signature.length > 0) {
      RagRetrievalService.pushChannel(channels, CHANNEL_WEIGHT_SIGNATURE,
        await RagRetrievalService.queryBySignature(store, signature, fetchK), byId);
    }

    // 系统分词的内容词作为查询扩展；失败时沿用纯规则拆分。
    const terms: string[] = planQueryTerms(trimmed).terms;
    const keywords: string[] = await QueryKeywordExtractor.extract(trimmed);
    const expandedTerms: string[] = keywords.length > 0
      ? mergeQueryTerms(terms, keywords, 8)
      : terms;
    // 拆词结果与整句相同时跳过词通道，避免同一条 SQL 算两遍名次。
    // 注意比较的是扩展后的词：分词可能把整句拆出额外的词，此时不能跳过。
    const termsDuplicateWhole: boolean = expandedTerms.length === 1 && expandedTerms[0] === trimmed;

    const termPlan: RagTermQueryPlan | null = termsDuplicateWhole ? null : planTermQuery(expandedTerms, fetchK);
    if (termPlan !== null) {
      RagRetrievalService.pushChannel(channels, CHANNEL_WEIGHT_TERMS,
        await RagRetrievalService.runTermQuery(store, termPlan), byId);
    }
    const shortPlan: RagTermQueryPlan | null = planShortTermQuery(expandedTerms, fetchK);
    if (shortPlan !== null && !RagRetrievalService.sameTermPlan(termPlan, shortPlan)) {
      RagRetrievalService.pushChannel(channels, CHANNEL_WEIGHT_SHORT,
        await RagRetrievalService.runTermQuery(store, shortPlan), byId);
    }

    if (EmbeddingRuntime.isDense()) {
      const vectorHits: VectorHit[] =
        await RagRetrievalService.appendVectorChannel(store, trimmed, fetchK, channels, byId);
      // 向量分不开时，用 LLM 把问题改写成检索关键词再补一路召回。
      // 只在头部差距小的时候调，命中明确的查询不受影响、也不付这次调用。
      if (RagRetrievalService.isAmbiguousHead(vectorHits)) {
        const keywords: string[] = await QueryRewriter.rewrite(trimmed);
        if (keywords.length > 0) {
          const rewritePlan: RagTermQueryPlan | null = planTermQuery(keywords, fetchK);
          if (rewritePlan !== null) {
            RagRetrievalService.pushChannel(channels, CHANNEL_WEIGHT_REWRITE,
              await RagRetrievalService.runTermQuery(store, rewritePlan), byId);
            console.info('[RagRewrite] gap=' + (vectorHits[0].score - vectorHits[1].score).toFixed(3)
              + ' keywords=' + keywords.join(' '));
          }
        }
      }
    }

    const fusedIds: string[] = fuseRrf(channels, topK);
    const hits: RagHit[] = [];
    for (let i = 0; i < fusedIds.length; i += 1) {
      const hit: RagHit | undefined = byId.get(fusedIds[i]);
      if (hit !== undefined) {
        hits.push(hit);
      }
    }
    return hits;
  }

  private static isAmbiguousHead(hits: VectorHit[]): boolean {
    return hits.length >= 2 && hits[0].score - hits[1].score < AMBIGUOUS_HEAD_GAP;
  }

  /** 向量通道：块级余弦取 unit 最高分，再回查正文字段供引用。 */
  private static async appendVectorChannel(store: relationalStore.RdbStore, query: string, fetchK: number,
    channels: RrfChannel[], byId: Map<string, RagHit>): Promise<VectorHit[]> {
    let vectorHits: VectorHit[] = [];
    try {
      vectorHits = await NoteVectorIndex.search(store, query, fetchK);
    } catch (error) {
      console.warn('rag vector search failed: ' + (error as Error).message);
      return [];
    }
    if (vectorHits.length === 0) {
      return [];
    }
    const ids: string[] = [];
    for (let i = 0; i < vectorHits.length; i += 1) {
      ids.push(vectorHits[i].unitId);
    }
    const rows: Map<string, RagHit> = await RagRetrievalService.queryHitsByIds(store, ids);
    const channelIds: string[] = [];
    for (let i = 0; i < vectorHits.length; i += 1) {
      const unitId: string = vectorHits[i].unitId;
      const row: RagHit | undefined = rows.get(unitId);
      if (row === undefined) {
        continue;
      }
      if (!byId.has(unitId)) {
        byId.set(unitId, row);
      }
      channelIds.push(unitId);
    }
    if (channelIds.length > 0) {
      channels.push({ weight: CHANNEL_WEIGHT_VECTOR, ids: channelIds });
    }
    return vectorHits;
  }

  private static pushChannel(channels: RrfChannel[], weight: number, hits: RagHit[],
    byId: Map<string, RagHit>): void {
    if (hits.length === 0) {
      return;
    }
    const ids: string[] = [];
    for (let i = 0; i < hits.length; i += 1) {
      const unitId: string = hits[i].unitId;
      if (unitId.length === 0 || ids.indexOf(unitId) >= 0) {
        continue;
      }
      ids.push(unitId);
      if (!byId.has(unitId)) {
        byId.set(unitId, hits[i]);
      }
    }
    if (ids.length > 0) {
      channels.push({ weight: weight, ids: ids });
    }
  }

  private static sameTermPlan(left: RagTermQueryPlan | null, right: RagTermQueryPlan): boolean {
    if (left === null || left.mode !== right.mode || left.bindValues.length !== right.bindValues.length) {
      return false;
    }
    for (let i = 0; i < left.bindValues.length; i += 1) {
      if (left.bindValues[i] !== right.bindValues[i]) {
        return false;
      }
    }
    return true;
  }

  private static async queryHitsByIds(store: relationalStore.RdbStore, ids: string[]): Promise<Map<string, RagHit>> {
    const rows: Map<string, RagHit> = new Map<string, RagHit>();
    if (ids.length === 0) {
      return rows;
    }
    const placeholders: string[] = [];
    for (let i = 0; i < ids.length; i += 1) {
      placeholders.push('?');
    }
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      resultSet = await store.querySql(
        'SELECT id, title, content, subject, chapter FROM knowledge_unit WHERE id IN ('
          + placeholders.join(',') + ')', ids);
      while (resultSet.goToNextRow()) {
        const hit: RagHit = {
          unitId: resultSet.getString(resultSet.getColumnIndex('id')),
          title: resultSet.getString(resultSet.getColumnIndex('title')),
          content: resultSet.getString(resultSet.getColumnIndex('content')),
          subject: resultSet.getString(resultSet.getColumnIndex('subject')),
          chapter: resultSet.getString(resultSet.getColumnIndex('chapter')),
        };
        rows.set(hit.unitId, hit);
      }
    } catch (error) {
      console.warn('rag id query failed: ' + (error as Error).message);
    } finally {
      if (resultSet !== undefined) {
        resultSet.close();
      }
    }
    return rows;
  }

  private static async queryBySignature(store: relationalStore.RdbStore, signature: string,
    topK: number): Promise<RagHit[]> {
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      resultSet = await store.querySql(
        'SELECT id, title, content, subject, chapter FROM knowledge_unit '
          + 'WHERE signature = ? ORDER BY updated_at DESC LIMIT ?',
        [signature, topK]);
      const hits: RagHit[] = [];
      while (resultSet.goToNextRow()) {
        hits.push({
          unitId: resultSet.getString(resultSet.getColumnIndex('id')),
          title: resultSet.getString(resultSet.getColumnIndex('title')),
          content: resultSet.getString(resultSet.getColumnIndex('content')),
          subject: resultSet.getString(resultSet.getColumnIndex('subject')),
          chapter: resultSet.getString(resultSet.getColumnIndex('chapter')),
        });
      }
      return hits;
    } catch (error) {
      console.warn('rag signature search failed: ' + (error as Error).message);
      return [];
    } finally {
      if (resultSet !== undefined) {
        resultSet.close();
      }
    }
  }

  private static async runWholeQuery(store: relationalStore.RdbStore, plan: RagQueryPlan,
    trimmed: string, topK: number): Promise<RagHit[]> {
    if (plan.mode === 'fts') {
      return await RagRetrievalService.queryHits(store, plan.sql, [trimmed, topK]);
    }
    const pattern: string = '%' + trimmed + '%';
    return await RagRetrievalService.queryHits(store, plan.sql, [pattern, pattern, topK]);
  }

  private static async runTermQuery(store: relationalStore.RdbStore,
    plan: RagTermQueryPlan): Promise<RagHit[]> {
    return await RagRetrievalService.queryHits(store, plan.sql, plan.bindValues);
  }

  private static async queryHits(store: relationalStore.RdbStore, sql: string,
    bindArgs: Array<string | number>): Promise<RagHit[]> {
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      resultSet = await store.querySql(sql, bindArgs);
      const hits: RagHit[] = [];
      while (resultSet.goToNextRow()) {
        const hit: RagHit = {
          unitId: resultSet.getString(resultSet.getColumnIndex('unit_id')),
          title: resultSet.getString(resultSet.getColumnIndex('title')),
          content: resultSet.getString(resultSet.getColumnIndex('content')),
          subject: resultSet.getString(resultSet.getColumnIndex('subject')),
          chapter: resultSet.getString(resultSet.getColumnIndex('chapter')),
        };
        hits.push(hit);
      }
      return hits;
    } catch (error) {
      console.warn('rag search failed sql=' + sql + ' err=' + (error as Error).message);
      return [];
    } finally {
      if (resultSet !== undefined) {
        resultSet.close();
      }
    }
  }

  /** 自管 FTS5 能力诊断（建表/插入/查询全链路），供 e2e 调试入口使用。 */
  static async fts5Diagnostic(store: relationalStore.RdbStore): Promise<string> {
    const result: RagFtsDiagnostic = { ok: false, hits: 0, message: '' };
    try {
      await store.executeSql('DROP TABLE IF EXISTS ' + PROBE_FTS_TABLE);
      await store.executeSql('CREATE VIRTUAL TABLE ' + PROBE_FTS_TABLE
        + " USING fts5(title, content, unit_id UNINDEXED, subject UNINDEXED, chapter UNINDEXED, tokenize='trigram')");
      await store.executeSql('INSERT INTO ' + PROBE_FTS_TABLE
        + ' (title, content, unit_id, subject, chapter) VALUES (?, ?, ?, ?, ?)',
        ['极限与连续', PROBE_SEED_TEXT, 'rag-probe-unit', '数学分析', '连续性']);
      const rs: relationalStore.ResultSet = await store.querySql(
        'SELECT unit_id FROM ' + PROBE_FTS_TABLE + ' WHERE ' + PROBE_FTS_TABLE + ' MATCH ?', [PROBE_QUERY]);
      let hits: number = 0;
      while (rs.goToNextRow()) {
        hits += 1;
      }
      rs.close();
      result.ok = true;
      result.hits = hits;
    } catch (error) {
      result.message = 'err=' + (error as Error).message;
      console.warn('rag fts5 diagnostic failed: ' + result.message);
    }
    return 'fts5Ok=' + (result.ok ? '1' : '0') + ' ftsHits=' + result.hits.toString()
      + (result.message.length > 0 ? ' ' + result.message : '');
  }
}
