// ============================================================================
//  database/RagEmbeddingDao.ets — demo-only RAG chunk/vector storage
// ============================================================================

import { relationalStore } from '@kit.ArkData';
import { RagChunk, RagEmbedding, uuid } from 'common';

export interface RagEmbeddingDemoRecord {
  chunk: RagChunk;
  embedding: RagEmbedding;
}

export class RagEmbeddingDao {
  private store: relationalStore.RdbStore;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  async saveDemoEmbedding(
    unitId: string,
    title: string,
    content: string,
    vector: number[],
    provider: string,
    model: string,
  ): Promise<RagEmbeddingDemoRecord> {
    const now: number = Date.now();
    const chunk: RagChunk = {
      id: uuid(),
      unitId: unitId,
      chunkIndex: 0,
      title: title,
      content: content,
      contentHash: '',
      tokenCount: 0,
      createdAt: now,
      updatedAt: now,
    };
    const embedding: RagEmbedding = {
      id: uuid(),
      chunkId: chunk.id,
      provider: provider,
      model: model,
      dimension: vector.length,
      metric: 'cosine',
      vectorJson: RagEmbeddingDao.stringifyVector(vector),
      createdAt: now,
      updatedAt: now,
    };
    await this.insertChunk(chunk);
    await this.insertEmbedding(embedding);
    return { chunk: chunk, embedding: embedding };
  }

  async queryDemoEmbeddingsByUnitId(unitId: string): Promise<RagEmbeddingDemoRecord[]> {
    const sql: string = "SELECT c.id AS chunk_id, c.unit_id, c.chunk_index, c.title, c.content, c.content_hash, c.token_count, c.created_at AS chunk_created_at, c.updated_at AS chunk_updated_at, e.id AS embedding_id, e.provider, e.model, e.dimension, e.metric, e.vector_json, e.created_at AS embedding_created_at, e.updated_at AS embedding_updated_at FROM rag_chunk c INNER JOIN rag_embedding e ON e.chunk_id = c.id WHERE c.unit_id = ? ORDER BY c.chunk_index ASC";
    return new Promise<RagEmbeddingDemoRecord[]>((resolve, reject) => {
      this.store.querySql(sql, [unitId], (err, resultSet) => {
        if (err) {
          reject(new Error('RagEmbeddingDao.queryDemoEmbeddingsByUnitId failed: ' + err.message));
          return;
        }
        const records: RagEmbeddingDemoRecord[] = [];
        if (resultSet.goToFirstRow()) {
          do {
            records.push(RagEmbeddingDao.rowToDemoRecord(resultSet));
          } while (resultSet.goToNextRow());
        }
        resultSet.close();
        resolve(records);
      });
    });
  }

  private static rowToDemoRecord(rs: relationalStore.ResultSet): RagEmbeddingDemoRecord {
    const chunk: RagChunk = {
      id: RagEmbeddingDao.readString(rs, 'chunk_id', ''),
      unitId: RagEmbeddingDao.readString(rs, 'unit_id', ''),
      chunkIndex: RagEmbeddingDao.readLong(rs, 'chunk_index', 0),
      title: RagEmbeddingDao.readString(rs, 'title', ''),
      content: RagEmbeddingDao.readString(rs, 'content', ''),
      contentHash: RagEmbeddingDao.readString(rs, 'content_hash', ''),
      tokenCount: RagEmbeddingDao.readLong(rs, 'token_count', 0),
      createdAt: RagEmbeddingDao.readLong(rs, 'chunk_created_at', 0),
      updatedAt: RagEmbeddingDao.readLong(rs, 'chunk_updated_at', 0),
    };
    const embedding: RagEmbedding = {
      id: RagEmbeddingDao.readString(rs, 'embedding_id', ''),
      chunkId: chunk.id,
      provider: RagEmbeddingDao.readString(rs, 'provider', ''),
      model: RagEmbeddingDao.readString(rs, 'model', ''),
      dimension: RagEmbeddingDao.readLong(rs, 'dimension', 0),
      metric: RagEmbeddingDao.readString(rs, 'metric', 'cosine'),
      vectorJson: RagEmbeddingDao.readString(rs, 'vector_json', '[]'),
      createdAt: RagEmbeddingDao.readLong(rs, 'embedding_created_at', 0),
      updatedAt: RagEmbeddingDao.readLong(rs, 'embedding_updated_at', 0),
    };
    return { chunk: chunk, embedding: embedding };
  }

  private static toChunkBucket(chunk: RagChunk): relationalStore.ValuesBucket {
    return {
      'id': chunk.id,
      'unit_id': chunk.unitId,
      'chunk_index': chunk.chunkIndex,
      'title': chunk.title,
      'content': chunk.content,
      'content_hash': chunk.contentHash,
      'token_count': chunk.tokenCount,
      'created_at': chunk.createdAt,
      'updated_at': chunk.updatedAt,
    };
  }

  private async insertChunk(chunk: RagChunk): Promise<number> {
    const bucket: relationalStore.ValuesBucket = RagEmbeddingDao.toChunkBucket(chunk);
    return new Promise<number>((resolve, reject) => {
      this.store.insert('rag_chunk', bucket, (err: Error, rowId: number) => {
        if (err) {
          reject(new Error('RagEmbeddingDao.insertChunk failed: ' + err.message));
          return;
        }
        resolve(rowId);
      });
    });
  }

  private async insertEmbedding(embedding: RagEmbedding): Promise<number> {
    const bucket: relationalStore.ValuesBucket = RagEmbeddingDao.toEmbeddingBucket(embedding);
    return new Promise<number>((resolve, reject) => {
      this.store.insert('rag_embedding', bucket, (err: Error, rowId: number) => {
        if (err) {
          reject(new Error('RagEmbeddingDao.insertEmbedding failed: ' + err.message));
          return;
        }
        resolve(rowId);
      });
    });
  }

  private static toEmbeddingBucket(embedding: RagEmbedding): relationalStore.ValuesBucket {
    return {
      'id': embedding.id,
      'chunk_id': embedding.chunkId,
      'provider': embedding.provider,
      'model': embedding.model,
      'dimension': embedding.dimension,
      'metric': embedding.metric,
      'vector_json': embedding.vectorJson,
      'created_at': embedding.createdAt,
      'updated_at': embedding.updatedAt,
    };
  }

  private static stringifyVector(value: number[]): string {
    try {
      return JSON.stringify(value);
    } catch (e) {
      return '[]';
    }
  }

  private static readString(rs: relationalStore.ResultSet, columnName: string, fallback: string): string {
    const index: number = rs.getColumnIndex(columnName);
    if (index < 0) {
      return fallback;
    }
    return rs.getString(index);
  }

  private static readLong(rs: relationalStore.ResultSet, columnName: string, fallback: number): number {
    const index: number = rs.getColumnIndex(columnName);
    if (index < 0) {
      return fallback;
    }
    return rs.getLong(index);
  }
}
