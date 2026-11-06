/**
 * NoteEmbeddingService.ets — 笔记 chunk 向量的写入与补建
 *
 * 路径: entry/src/main/ets/services/NoteEmbeddingService.ets
 * 职责: 为笔记的每个 rag_chunk 计算「当前生效端口」的向量并写入 rag_embedding；
 *       提供缺失向量的批量补建（历史笔记、模型切换后重建）。
 * 依赖: @kit.ArkData、common（EmbeddingPort）、./EmbeddingRuntime、./NoteVectorIndex。
 *
 * 约束:
 *   - 模型来源由 EmbeddingRuntime 决定（云端稠密 / 词面），写库带 model 标识，
 *     检索只比较同标识向量；切换模型后旧向量由下一次补建覆盖；
 *   - 向量写入失败必须抛出，由 post-commit 记告警、由补建重试，不落半截数据；
 *   - 云端补建按笔记条数限量（每条笔记一次请求），避免一次跑完整个库。
 */
import { relationalStore } from '@kit.ArkData';
import type { EmbeddingPort, EmbeddingVector } from 'common';
import { EmbeddingRuntime } from './EmbeddingRuntime';
import { NoteVectorIndex } from './NoteVectorIndex';

const EMBEDDING_METRIC: string = 'cosine';
const BACKFILL_LEXICAL_LIMIT: number = 200;
const BACKFILL_CLOUD_LIMIT: number = 20;

interface ChunkRow {
  id: string;
  title: string;
  content: string;
}

export class NoteEmbeddingService {
  /** 重建一条笔记全部 chunk 的向量；返回写入行数。 */
  static async embedUnit(store: relationalStore.RdbStore, unitId: string): Promise<number> {
    if (unitId.length === 0) {
      return 0;
    }
    const chunks: ChunkRow[] = await NoteEmbeddingService.queryChunks(store, unitId);
    if (chunks.length === 0) {
      return 0;
    }
    const port: EmbeddingPort = EmbeddingRuntime.active();
    const texts: string[] = [];
    for (let i = 0; i < chunks.length; i += 1) {
      // 标题进向量：块正文可能不含关键词，标题补上主题信号。
      texts.push(chunks[i].title + '\n' + chunks[i].content);
    }
    const vectors: EmbeddingVector[] = await port.embed(texts);
    if (vectors.length !== chunks.length) {
      throw new Error('embedding count mismatch: chunks=' + chunks.length.toString()
        + ' vectors=' + vectors.length.toString());
    }
    // 先删掉这些块的所有模型向量：切换模型后不留下无用的旧向量。
    await store.executeSql(
      'DELETE FROM rag_embedding WHERE chunk_id IN (SELECT id FROM rag_chunk WHERE unit_id = ?)', [unitId]);
    const now: number = Date.now();
    let written: number = 0;
    for (let i = 0; i < chunks.length; i += 1) {
      const chunk: ChunkRow = chunks[i];
      const vector: EmbeddingVector = vectors[i];
      const rowId: string = chunk.id + ':' + vector.model;
      await store.executeSql(
        'INSERT OR REPLACE INTO rag_embedding '
          + '(id, chunk_id, provider, model, dimension, metric, vector_json, created_at, updated_at) '
          + 'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [rowId, chunk.id, vector.provider, vector.model, vector.values.length,
          EMBEDDING_METRIC, JSON.stringify(vector.values), now, now]);
      written += 1;
    }
    NoteVectorIndex.invalidate();
    return written;
  }

  /** 补建缺失向量的笔记；按 unit 逐个重建，返回写入行数。 */
  static async backfillMissing(store: relationalStore.RdbStore, limit: number = 0): Promise<number> {
    const effectiveLimit: number = limit > 0
      ? limit
      : (EmbeddingRuntime.isDense() ? BACKFILL_CLOUD_LIMIT : BACKFILL_LEXICAL_LIMIT);
    const unitIds: string[] = await NoteEmbeddingService.queryMissingUnits(store, effectiveLimit);
    let written: number = 0;
    for (let i = 0; i < unitIds.length; i += 1) {
      try {
        written += await NoteEmbeddingService.embedUnit(store, unitIds[i]);
      } catch (error) {
        console.warn('embed unit failed id=' + unitIds[i] + ' err=' + (error as Error).message);
      }
    }
    return written;
  }

  /** 覆盖率诊断：应有多少 chunk、当前模型已建多少向量、缺多少笔记。 */
  static async coverage(store: relationalStore.RdbStore): Promise<string> {
    const model: string = EmbeddingRuntime.activeModel();
    let chunks: number = 0;
    let embedded: number = 0;
    let missingUnits: number = 0;
    try {
      chunks = await NoteEmbeddingService.count(store, 'SELECT COUNT(*) AS c FROM rag_chunk');
      embedded = await NoteEmbeddingService.count(store,
        'SELECT COUNT(*) AS c FROM rag_embedding WHERE model = ?', [model]);
      missingUnits = await NoteEmbeddingService.count(store,
        'SELECT COUNT(*) AS c FROM (SELECT c.unit_id FROM rag_chunk c '
          + 'LEFT JOIN rag_embedding e ON e.chunk_id = c.id AND e.model = ? '
          + 'WHERE e.id IS NULL GROUP BY c.unit_id)', [model]);
    } catch (error) {
      return 'vectorErr=' + (error as Error).message;
    }
    return 'model=' + model + ' ragChunks=' + chunks.toString() + ' vectors=' + embedded.toString()
      + ' missingUnits=' + missingUnits.toString();
  }

  private static async queryChunks(store: relationalStore.RdbStore, unitId: string): Promise<ChunkRow[]> {
    const rows: ChunkRow[] = [];
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      resultSet = await store.querySql(
        'SELECT id, title, content FROM rag_chunk WHERE unit_id = ? ORDER BY chunk_index ASC', [unitId]);
      while (resultSet.goToNextRow()) {
        rows.push({
          id: resultSet.getString(resultSet.getColumnIndex('id')),
          title: resultSet.getString(resultSet.getColumnIndex('title')),
          content: resultSet.getString(resultSet.getColumnIndex('content')),
        });
      }
    } catch (error) {
      console.warn('embedding chunk query failed: ' + (error as Error).message);
    } finally {
      if (resultSet !== undefined) {
        resultSet.close();
      }
    }
    return rows;
  }

  private static async queryMissingUnits(store: relationalStore.RdbStore, limit: number): Promise<string[]> {
    const model: string = EmbeddingRuntime.activeModel();
    const unitIds: string[] = [];
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      resultSet = await store.querySql(
        'SELECT c.unit_id AS unit_id FROM rag_chunk c '
          + 'LEFT JOIN rag_embedding e ON e.chunk_id = c.id AND e.model = ? '
          + 'WHERE e.id IS NULL GROUP BY c.unit_id LIMIT ?',
        [model, limit]);
      while (resultSet.goToNextRow()) {
        unitIds.push(resultSet.getString(resultSet.getColumnIndex('unit_id')));
      }
    } catch (error) {
      console.warn('embedding missing query failed: ' + (error as Error).message);
    } finally {
      if (resultSet !== undefined) {
        resultSet.close();
      }
    }
    return unitIds;
  }

  private static async count(store: relationalStore.RdbStore, sql: string,
    bindArgs: Array<string | number> = []): Promise<number> {
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      resultSet = await store.querySql(sql, bindArgs);
      if (!resultSet.goToFirstRow()) {
        return 0;
      }
      return resultSet.getLong(resultSet.getColumnIndex('c'));
    } finally {
      if (resultSet !== undefined) {
        resultSet.close();
      }
    }
  }
}
