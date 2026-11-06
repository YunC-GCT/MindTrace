/**
 * NoteVectorIndex.ets — 笔记向量的内存索引与余弦检索
 *
 * 路径: entry/src/main/ets/services/NoteVectorIndex.ets
 * 职责: 把 rag_embedding 里当前模型的向量读进内存，对查询做全量余弦扫描，
 *       按 unit 取块内最高分，返回 TopK。笔记量级在千条以内，暴力扫描足够快，
 *       不需要 ANN 索引（少一个依赖、少一处一致性风险）。
 * 依赖: @kit.ArkData、common（余弦）、./EmbeddingRuntime。
 *
 * 约束:
 *   - 只读取 `model = 当前模型` 的向量，绝不混用不同来源的向量；
 *   - 查询向量由当前端口生成：云端模型每问一次要多一次 /embeddings 往返，
 *     失败即返回空（检索其余通道照常）；
 *   - 新鲜度靠 `model + COUNT + MAX(updated_at) + 体积` 戳：跨进程写入也能感知。
 */
import { relationalStore } from '@kit.ArkData';
import { cosineSimilarity, meanVector, subtractCentroid } from 'common';
import type { EmbeddingPort, EmbeddingVector } from 'common';
import { EmbeddingRuntime } from './EmbeddingRuntime';
import { RerankClient } from './RerankClient';

// 向量的最低可信余弦。2026-11-06 真机标定（100 条语料）：
//   BAAI/bge-m3：无关查询 0.377–0.438，相关 0.49–0.56 → 取 0.46
//   BAAI/bge-large-zh-v1.5：无关 0.232，相关 0.44–0.55 → 取 0.33
// 两个模型的分数尺度差一个档，换模型必须重标，否则无关查询会全部漏进来。
const VECTOR_MIN_COSINE: number = 0.46;
// 相对切尾：只保留与本次最高分差距不远的候选，压掉随语料增长冒出来的长尾噪声。
const RELATIVE_CUTOFF_RATIO: number = 0.6;
// 交叉编码器重排的候选数：只重排头部，其余保持余弦顺序。
// 同领域语料的余弦分挤得很窄（实测 25 条笔记只占 0.372–0.515），重排是唯一能把第 9 名拉回来的手段。
// 取 12 而不是 8：实测目标笔记可能排在第 9，取 8 会把它挡在候选之外。
const RERANK_CANDIDATES: number = 12;
// 只在余弦头部「分不开」时才重排：实测无条件重排会把 hit@1 从 16 拉到 13，
// 因为通用 reranker 会推翻本来排对的强信号。top1 与 top2 差小于这个值才介入。
const AMBIGUOUS_GAP: number = 0.03;
const MAX_ENTRIES: number = 20000;

interface VectorEntry {
  chunkId: string;
  unitId: string;
  values: number[];
}

export interface VectorHit {
  unitId: string;
  chunkId: string;
  score: number;
}

export class NoteVectorIndex {
  private static entries: VectorEntry[] = [];
  private static stamp: string = '';
  /** 语料均值：查询与文档同时去掉公共词分量，压低公共词对分数的贡献。 */
  private static centroid: number[] = [];
  /** chunkId → 正文，重排时作为 query-doc 对的文档侧。 */
  private static texts: Map<string, string> = new Map<string, string>();

  /** 本地写完向量后主动失效，避免下一次检索多跑一次戳查询。 */
  static invalidate(): void {
    NoteVectorIndex.entries = [];
    NoteVectorIndex.stamp = '';
    NoteVectorIndex.centroid = [];
    NoteVectorIndex.texts = new Map<string, string>();
  }

  /**
   * @param minScore 最低余弦；检索用默认阈值。诊断探针传 0 可看到完整分数分布，用于调阈值。
   * 判定是「绝对下限 + 相对切尾」：既要过绝对阈值，也不能比本次最高分低太多。
   * 绝对阈值防无关查询，相对切尾让语料增长后自动收紧。
   */
  static async search(store: relationalStore.RdbStore, query: string, topK: number,
    minScore: number = VECTOR_MIN_COSINE): Promise<VectorHit[]> {
    if (topK <= 0 || query.trim().length === 0) {
      return [];
    }
    const all: VectorHit[] = await NoteVectorIndex.scanScores(store, query);
    if (all.length === 0) {
      return [];
    }
    let top: number = 0;
    for (let i = 0; i < all.length; i += 1) {
      if (all[i].score > top) {
        top = all[i].score;
      }
    }
    // 探针传 minScore=0 时保留全量，用于观察分布。
    const cutoff: number = minScore > 0
      ? Math.max(minScore, top * RELATIVE_CUTOFF_RATIO)
      : minScore;
    const hits: VectorHit[] = [];
    for (let i = 0; i < all.length; i += 1) {
      if (all[i].score >= cutoff) {
        hits.push(all[i]);
      }
    }
    hits.sort((left: VectorHit, right: VectorHit): number => right.score - left.score);
    const ordered: VectorHit[] = await NoteVectorIndex.rerank(query, hits);
    return ordered.slice(0, topK);
  }

  /** 余弦同领域压缩严重：只在头部无法区分时，对候选做交叉编码器重排。 */
  private static async rerank(query: string, hits: VectorHit[]): Promise<VectorHit[]> {
    if (hits.length <= 1) {
      return hits;
    }
    // 头部差距足够大说明余弦已经分得开，重排只会引入噪声和延迟。
    if (hits[0].score - hits[1].score >= AMBIGUOUS_GAP) {
      return hits;
    }
    const count: number = Math.min(RERANK_CANDIDATES, hits.length);
    const docs: string[] = [];
    for (let i = 0; i < count; i += 1) {
      const text: string | undefined = NoteVectorIndex.texts.get(hits[i].chunkId);
      docs.push(RerankClient.trimDocument(text !== undefined ? text : ''));
    }
    const scores: number[] = await RerankClient.score(query, docs);
    if (scores.length !== count) {
      return hits;
    }
    const order: number[] = [];
    for (let i = 0; i < count; i += 1) {
      order.push(i);
    }
    order.sort((left: number, right: number): number => scores[right] - scores[left]);
    const reordered: VectorHit[] = [];
    for (let i = 0; i < order.length; i += 1) {
      reordered.push(hits[order[i]]);
    }
    for (let i = count; i < hits.length; i += 1) {
      reordered.push(hits[i]);
    }
    return reordered;
  }

  /** 分数分布诊断：top / 中位数 / 均值 / 条目数，用于语料增长后重标阈值。 */
  static async scoreStats(store: relationalStore.RdbStore, query: string): Promise<string> {
    const all: VectorHit[] = await NoteVectorIndex.scanScores(store, query);
    if (all.length === 0) {
      return 'n=0';
    }
    all.sort((left: VectorHit, right: VectorHit): number => right.score - left.score);
    let sum: number = 0;
    for (let i = 0; i < all.length; i += 1) {
      sum += all[i].score;
    }
    const median: number = all[Math.floor(all.length / 2)].score;
    return 'n=' + all.length.toString()
      + ' top=' + all[0].score.toFixed(3)
      + ' p50=' + median.toFixed(3)
      + ' mean=' + (sum / all.length).toFixed(3);
  }

  /** 全量扫描：每个 unit 取块内最高分，不做任何阈值过滤。 */
  private static async scanScores(store: relationalStore.RdbStore, query: string): Promise<VectorHit[]> {
    await NoteVectorIndex.ensureFresh(store, EmbeddingRuntime.activeModel());
    if (NoteVectorIndex.entries.length === 0) {
      return [];
    }
    const queryVector: number[] = await NoteVectorIndex.queryVector(query);
    if (queryVector.length === 0) {
      return [];
    }
    const best: Map<string, VectorHit> = new Map<string, VectorHit>();
    for (let i = 0; i < NoteVectorIndex.entries.length; i += 1) {
      const entry: VectorEntry = NoteVectorIndex.entries[i];
      const score: number = cosineSimilarity(queryVector, entry.values);
      const existing: VectorHit | undefined = best.get(entry.unitId);
      if (existing === undefined || score > existing.score) {
        best.set(entry.unitId, { unitId: entry.unitId, chunkId: entry.chunkId, score: score });
      }
    }
    return Array.from(best.values());
  }

  /** 查询向量必须由写库用的同一个端口生成，否则两个向量不在同一空间。 */
  private static async queryVector(query: string): Promise<number[]> {
    const port: EmbeddingPort = EmbeddingRuntime.active();
    try {
      const vector: EmbeddingVector = await port.embedQuery(query);
      if (vector.values.length === 0) {
        return [];
      }
      return NoteVectorIndex.centerQuery(vector.values);
    } catch (error) {
      console.warn('vector query embed failed: ' + (error as Error).message);
      return [];
    }
  }

  private static async ensureFresh(store: relationalStore.RdbStore, model: string): Promise<void> {
    const stamp: string = await NoteVectorIndex.readStamp(store, model);
    if (stamp.length > 0 && stamp === NoteVectorIndex.stamp && NoteVectorIndex.entries.length > 0) {
      return;
    }
    await NoteVectorIndex.load(store, model, stamp);
  }

  private static async readStamp(store: relationalStore.RdbStore, model: string): Promise<string> {
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      // 体积和也进戳：同一毫秒内等量改写的笔记，仅靠 COUNT+MAX 分辨不出来。
      resultSet = await store.querySql(
        'SELECT COUNT(*) AS n, COALESCE(MAX(updated_at), 0) AS t, '
          + 'COALESCE(CAST(TOTAL(LENGTH(vector_json)) AS INTEGER), 0) AS l '
          + 'FROM rag_embedding WHERE model = ?', [model]);
      if (!resultSet.goToFirstRow()) {
        return '';
      }
      const total: number = resultSet.getLong(resultSet.getColumnIndex('n'));
      const latest: number = resultSet.getLong(resultSet.getColumnIndex('t'));
      const volume: number = resultSet.getLong(resultSet.getColumnIndex('l'));
      return model + '|' + total.toString() + ':' + latest.toString() + ':' + volume.toString();
    } catch (error) {
      console.warn('vector index stamp failed: ' + (error as Error).message);
      return '';
    } finally {
      if (resultSet !== undefined) {
        resultSet.close();
      }
    }
  }

  private static async load(store: relationalStore.RdbStore, model: string, stamp: string): Promise<void> {
    const loaded: VectorEntry[] = [];
    const loadedTexts: Map<string, string> = new Map<string, string>();
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      resultSet = await store.querySql(
        'SELECT e.chunk_id AS chunk_id, c.unit_id AS unit_id, e.vector_json AS vector_json, '
          + 'c.title AS title, c.content AS content, k.summary AS summary '
          + 'FROM rag_embedding e INNER JOIN rag_chunk c ON c.id = e.chunk_id '
          + 'INNER JOIN knowledge_unit k ON k.id = c.unit_id '
          + 'WHERE e.model = ? LIMIT ?', [model, MAX_ENTRIES]);
      while (resultSet.goToNextRow()) {
        const values: number[] = NoteVectorIndex.parseVector(
          resultSet.getString(resultSet.getColumnIndex('vector_json')));
        if (values.length === 0) {
          continue;
        }
        const chunkId: string = resultSet.getString(resultSet.getColumnIndex('chunk_id'));
        loaded.push({
          chunkId: chunkId,
          unitId: resultSet.getString(resultSet.getColumnIndex('unit_id')),
          values: values,
        });
        // 重排用「标题 + 摘要」：正文开头多是「## 定义」这类模板字，既拖慢编码又不提供区分度。
        const title: string = resultSet.getString(resultSet.getColumnIndex('title'));
        const summary: string = resultSet.getString(resultSet.getColumnIndex('summary'));
        const rerankText: string = summary.trim().length > 0
          ? title + '：' + summary
          : title + '：' + resultSet.getString(resultSet.getColumnIndex('content'));
        loadedTexts.set(chunkId, rerankText);
      }
    } catch (error) {
      console.warn('vector index load failed: ' + (error as Error).message);
    } finally {
      if (resultSet !== undefined) {
        resultSet.close();
      }
    }
    const rawVectors: number[][] = [];
    for (let i = 0; i < loaded.length; i += 1) {
      rawVectors.push(loaded[i].values);
    }
    // 去均值只对词面向量有意义：它压的是公共二元组带来的基线。
    // 稠密向量本身已分布良好，减均值会把分数整体压扁（实测 0.45 → 0.10）。
    const centroid: number[] = EmbeddingRuntime.isDense() ? [] : meanVector(rawVectors);
    for (let i = 0; i < loaded.length; i += 1) {
      loaded[i].values = subtractCentroid(loaded[i].values, centroid);
    }
    NoteVectorIndex.centroid = centroid;
    NoteVectorIndex.entries = loaded;
    NoteVectorIndex.texts = loadedTexts;
    NoteVectorIndex.stamp = stamp;
  }

  private static centerQuery(vector: number[]): number[] {
    return subtractCentroid(vector, NoteVectorIndex.centroid);
  }

  private static parseVector(json: string): number[] {
    const values: number[] = [];
    try {
      const parsed: Object = JSON.parse(json) as Object;
      if (!Array.isArray(parsed)) {
        return values;
      }
      const items: Object[] = parsed as Object[];
      for (let i = 0; i < items.length; i += 1) {
        values.push(Number(items[i]));
      }
    } catch (error) {
      return values;
    }
    return values;
  }
}

