/**
 * NoteFtsIndex.ets — RAG 检索 FTS 索引的写路径同步（schema v19 note_fts）
 *
 * 路径: entry/src/main/ets/database/NoteFtsIndex.ets
 * 职责: 笔记 create/update/delete 时，在写库事务内同步检索索引：note_fts（trigram FTS5，一期检索主链路）
 *       + rag_chunk（既有 chunk 表，为向量/其他检索通道预留；rag_embedding 待 embedding 来源接入）。
 * 依赖: KnowledgeUnit 类型、sourceFingerprint。
 */
import { relationalStore } from '@kit.ArkData';
import { KnowledgeUnit, sourceFingerprint } from 'common';

// RAG chunk 粒度：400 字/块（笔记内容通常 <2k 字，够用且便于未来 embedding 对齐）
const CHUNK_SIZE: number = 400;

interface ChunkRow {
  id: string;
  content: string;
}

export class NoteFtsIndex {
  /**
   * 在笔记写库的同一事务里同步索引：note_fts + rag_chunk 与 knowledge_unit 原子提交。
   * 曾用「提交后异步补同步 + 5s 超时」，应用被杀会留下未索引笔记（实测 196 条里缺 16 条）。
   */
  static async applyToTransaction(transaction: relationalStore.Transaction, unit: KnowledgeUnit): Promise<void> {
    if (unit.id.length === 0) {
      return;
    }
    const title: string = unit.title !== undefined ? unit.title : '';
    const content: string = unit.content !== undefined ? unit.content : '';
    const subject: string = unit.subject !== undefined ? unit.subject : '';
    const chapter: string = unit.chapter !== undefined ? unit.chapter : '';
    await transaction.execute('DELETE FROM note_fts WHERE unit_id = ?', [unit.id]);
    await transaction.execute(
      'INSERT INTO note_fts (title, content, unit_id, subject, chapter) VALUES (?, ?, ?, ?, ?)',
      [title, content, unit.id, subject, chapter]);
    await NoteFtsIndex.syncChunksInTransaction(transaction, unit.id, title, content);
  }

  /** 同步 rag_chunk（删除该 unit 旧块 → 按 400 字切块插入；embedding 行随旧块清理）。 */
  private static async syncChunksInTransaction(transaction: relationalStore.Transaction, unitId: string,
    title: string, content: string): Promise<void> {
    await transaction.execute(
      'DELETE FROM rag_embedding WHERE chunk_id IN (SELECT id FROM rag_chunk WHERE unit_id = ?)', [unitId]);
    await transaction.execute('DELETE FROM rag_chunk WHERE unit_id = ?', [unitId]);
    const chunks: ChunkRow[] = NoteFtsIndex.splitChunks(unitId, content);
    const now: number = Date.now();
    for (let i = 0; i < chunks.length; i++) {
      const chunk: ChunkRow = chunks[i];
      await transaction.execute(
        'INSERT INTO rag_chunk (id, unit_id, chunk_index, title, content, content_hash, token_count, created_at, updated_at) '
        + 'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [chunk.id, unitId, i, title, chunk.content, sourceFingerprint(chunk.content),
          Math.ceil(chunk.content.length / 4), now, now]);
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

  /** 删除笔记时在同一事务里清理索引，避免提交后崩溃留下孤立行。 */
  static async removeFromTransaction(transaction: relationalStore.Transaction, unitId: string): Promise<void> {
    if (unitId.length === 0) {
      return;
    }
    await transaction.execute('DELETE FROM note_fts WHERE unit_id = ?', [unitId]);
    await transaction.execute(
      'DELETE FROM rag_embedding WHERE chunk_id IN (SELECT id FROM rag_chunk WHERE unit_id = ?)', [unitId]);
    await transaction.execute('DELETE FROM rag_chunk WHERE unit_id = ?', [unitId]);
  }
}
