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

// 向量的最低可信余弦。2026-11-06 真机标定（BGE-large-zh-v1.5，25 条语料）：
// 相关查询原始余弦 0.44–0.55，无关查询「今天天气怎么样」0.232，取 0.33 卡在中间。
// 换模型或语料规模变化较大时需要重新标定。
const VECTOR_MIN_COSINE: number = 0.33;
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

  /** 本地写完向量后主动失效，避免下一次检索多跑一次戳查询。 */
  static invalidate(): void {
    NoteVectorIndex.entries = [];
    NoteVectorIndex.stamp = '';
    NoteVectorIndex.centroid = [];
  }

  /**
   * @param minScore 最低余弦；检索用默认阈值。诊断探针传 0 可看到完整分数分布，用于调阈值。
   */
  static async search(store: relationalStore.RdbStore, query: string, topK: number,
    minScore: number = VECTOR_MIN_COSINE): Promise<VectorHit[]> {
    if (topK <= 0 || query.trim().length === 0) {
      return [];
    }
    const model: string = EmbeddingRuntime.activeModel();
    await NoteVectorIndex.ensureFresh(store, model);
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
      if (score < minScore) {
        continue;
      }
      const existing: VectorHit | undefined = best.get(entry.unitId);
      if (existing === undefined || score > existing.score) {
        best.set(entry.unitId, { unitId: entry.unitId, chunkId: entry.chunkId, score: score });
      }
    }
    const hits: VectorHit[] = Array.from(best.values());
    hits.sort((left: VectorHit, right: VectorHit): number => right.score - left.score);
    return hits.slice(0, topK);
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
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      resultSet = await store.querySql(
        'SELECT e.chunk_id AS chunk_id, c.unit_id AS unit_id, e.vector_json AS vector_json '
          + 'FROM rag_embedding e INNER JOIN rag_chunk c ON c.id = e.chunk_id '
          + 'WHERE e.model = ? LIMIT ?', [model, MAX_ENTRIES]);
      while (resultSet.goToNextRow()) {
        const values: number[] = NoteVectorIndex.parseVector(
          resultSet.getString(resultSet.getColumnIndex('vector_json')));
        if (values.length === 0) {
          continue;
        }
        loaded.push({
          chunkId: resultSet.getString(resultSet.getColumnIndex('chunk_id')),
          unitId: resultSet.getString(resultSet.getColumnIndex('unit_id')),
          values: values,
        });
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

