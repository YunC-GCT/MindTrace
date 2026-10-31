/**
 * NoteFtsIndex.ets — RAG 检索 FTS 索引的写路径同步（schema v19 note_fts）
 *
 * 路径: entry/src/main/ets/database/NoteFtsIndex.ets
 * 职责: 笔记 create/update/delete 后同步检索索引：note_fts（trigram FTS5，一期检索主链路）
 *       + rag_chunk（既有 chunk 表，为向量/其他检索通道预留；rag_embedding 待 embedding 来源接入）。
 *       尽力而为：索引失败只记日志，绝不阻塞笔记写入主链路。
 * 依赖: common DatabaseHelper（RdbStore）+ KnowledgeUnit 类型。
 */
import { relationalStore } from '@kit.ArkData';
import { DatabaseHelper, KnowledgeUnit, Logger, sourceFingerprint } from 'common';

const log: Logger = new Logger('NoteFtsIndex');
// RAG chunk 粒度：400 字/块（笔记内容通常 <2k 字，够用且便于未来 embedding 对齐）
const CHUNK_SIZE: number = 400;

interface ChunkRow {
  id: string;
  content: string;
}

export class NoteFtsIndex {
  /** 新增/更新后 upsert（delete + insert，保证内容最新）。 */
  static async upsert(unit: KnowledgeUnit): Promise<void> {
    const store: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    if (store === null || unit.id.length === 0) {
      return;
    }
    try {
      await store.executeSql('DELETE FROM note_fts WHERE unit_id = ?', [unit.id]);
      const title: string = unit.title !== undefined ? unit.title : '';
      const content: string = unit.content !== undefined ? unit.content : '';
      const subject: string = unit.subject !== undefined ? unit.subject : '';
      const chapter: string = unit.chapter !== undefined ? unit.chapter : '';
      await store.executeSql(
        'INSERT INTO note_fts (title, content, unit_id, subject, chapter) VALUES (?, ?, ?, ?, ?)',
        [title, content, unit.id, subject, chapter]);
      await NoteFtsIndex.syncChunks(store, unit.id, title, content);
    } catch (error) {
      log.warn('note_fts upsert failed unit=' + unit.id + ' err=' + (error as Error).message);
    }
  }

  /** 同步 rag_chunk（删除该 unit 旧块 → 按 400 字切块插入；embedding 行随旧块清理）。 */
  private static async syncChunks(store: relationalStore.RdbStore, unitId: string,
    title: string, content: string): Promise<void> {
    try {
      const predicates = new relationalStore.RdbPredicates('rag_chunk');
      predicates.equalTo('unit_id', unitId);
      const rs: relationalStore.ResultSet = await store.query(predicates, ['id']);
      const chunkIds: string[] = [];
      try {
        if (rs.goToFirstRow()) {
          do {
            chunkIds.push(rs.getString(rs.getColumnIndex('id')));
          } while (rs.goToNextRow());
        }
      } finally {
        rs.close();
      }
      for (let i = 0; i < chunkIds.length; i++) {
        await store.executeSql('DELETE FROM rag_embedding WHERE chunk_id = ?', [chunkIds[i]]);
      }
      await store.executeSql('DELETE FROM rag_chunk WHERE unit_id = ?', [unitId]);
      const chunks: ChunkRow[] = NoteFtsIndex.splitChunks(unitId, content);
      const now: number = Date.now();
      for (let i = 0; i < chunks.length; i++) {
        const chunk: ChunkRow = chunks[i];
        await store.executeSql(
          'INSERT INTO rag_chunk (id, unit_id, chunk_index, title, content, content_hash, token_count, created_at, updated_at) '
          + 'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [chunk.id, unitId, i, title, chunk.content, sourceFingerprint(chunk.content),
            Math.ceil(chunk.content.length / 4), now, now]);
      }
    } catch (error) {
      log.warn('rag_chunk sync failed unit=' + unitId + ' err=' + (error as Error).message);
    }
  }

  // 确定性切块（无随机、无重叠）：同一内容永远得到同样的 chunk id。
  private static splitChunks(unitId: string, content: string): ChunkRow[] {
    const chunks: ChunkRow[] = [];
    const text: string = content.length > 0 ? content : '';
    if (text.length === 0) {
      return chunks;
    }
    let index: number = 0;
    let offset: number = 0;
    while (offset < text.length) {
      const end: number = offset + CHUNK_SIZE < text.length ? offset + CHUNK_SIZE : text.length;
      const chunk: ChunkRow = { id: unitId + ':c' + index.toString(), content: text.substring(offset, end) };
      chunks.push(chunk);
      index += 1;
      offset = end;
    }
    return chunks;
  }

  /** 删除后清理索引。 */
  static async remove(unitId: string): Promise<void> {
    const store: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    if (store === null || unitId.length === 0) {
      return;
    }
    try {
      await store.executeSql('DELETE FROM note_fts WHERE unit_id = ?', [unitId]);
      await store.executeSql('DELETE FROM rag_chunk WHERE unit_id = ?', [unitId]);
    } catch (error) {
      log.warn('note_fts remove failed unit=' + unitId + ' err=' + (error as Error).message);
    }
  }
}
