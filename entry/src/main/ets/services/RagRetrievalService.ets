/**
 * RagRetrievalService.ets — RAG 检索一期：自管 FTS5（trigram）
 *
 * 路径: entry/src/main/ets/services/RagRetrievalService.ets
 * 职责: 在 MindTrace.db 的 `note_fts`（FTS5 trigram，schema v19）上做本地检索：
 *       ≥3 字查询走 MATCH（rank 排序），<3 字走 LIKE 子串 fallback。
 *       供 NoteEvidenceService 作为首选召回（失败/无命中回退既有 note.search）。
 * 依赖: @kit.ArkData (relationalStore) / common DatabaseHelper / ./RagQueryPlan（纯函数）。
 *
 * 约束:
 *   - **不 import 受限 Kit**（DataAugmentationKit 的探针在 RagKitProbe.ets，仅调试 harness 用）。
 *   - 任何失败返回空数组（调用方负责降级），不抛异常打断回答。
 *
 * 数据流:
 *   knowledge_unit 写入/更新/删除 → note_fts（NoteFtsIndex 同步）
 *   NoteEvidenceService.build(query) → search(query, topK) → RagHit[] → join knowledge_unit → NoteEvidenceCitation
 */
import { relationalStore } from '@kit.ArkData';
import { planQueryTerms } from 'common';
import { planRagQuery, planShortTermQuery, planTermQuery, RagQueryPlan, RagTermQueryPlan } from './RagQueryPlan';

const PROBE_FTS_TABLE: string = 'note_fts';
const PROBE_SEED_TEXT: string = '函数在一点的连续性 极限 连续函数';
const PROBE_QUERY: string = '连续性';

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
   * RAG 检索：自管 FTS5（trigram）。
   * - 先用整句跑原有计划（≥3 字 MATCH / <3 字 LIKE），命中即返回，既有行为不变；
   * - 整句未命中时，按 044 R2 拆词做词 OR 兜底（避免带疑问词的提问必然 miss）。
   * 任何失败返回空数组（由调用方回退 note.search）。
   */
  static async search(store: relationalStore.RdbStore, query: string, topK: number): Promise<RagHit[]> {
    const trimmed: string = query.trim();
    if (trimmed.length === 0 || topK <= 0) {
      return [];
    }
    const plan: RagQueryPlan = planRagQuery(trimmed);
    const direct: RagHit[] = await RagRetrievalService.runWholeQuery(store, plan, trimmed, topK);
    if (direct.length > 0) {
      return direct;
    }
    const terms: string[] = planQueryTerms(trimmed).terms;
    if (terms.length === 1 && terms[0] === trimmed) {
      return [];
    }
    const termPlan: RagTermQueryPlan | null = planTermQuery(terms, topK);
    if (termPlan !== null) {
      const termHits: RagHit[] = await RagRetrievalService.runTermQuery(store, termPlan);
      if (termHits.length > 0) {
        return termHits;
      }
      if (termPlan.mode === 'like') {
        return [];
      }
    }
    // 长词 OR 未命中时再试短词（如「数列极限的定义」→「定义」）。
    const shortPlan: RagTermQueryPlan | null = planShortTermQuery(terms, topK);
    if (shortPlan === null) {
      return [];
    }
    return await RagRetrievalService.runTermQuery(store, shortPlan);
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
