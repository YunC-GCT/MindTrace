/**
 * NoteFtsIndex.ets — RAG 检索 FTS 索引的写路径同步（schema v19 note_fts）
 *
 * 路径: entry/src/main/ets/database/NoteFtsIndex.ets
 * 职责: 笔记 create/update/delete 后同步 note_fts（trigram FTS5），保证检索与知识库一致。
 *       尽力而为：索引失败只记日志，绝不阻塞笔记写入主链路。
 * 依赖: common DatabaseHelper（RdbStore）+ KnowledgeUnit 类型。
 */
import { relationalStore } from '@kit.ArkData';
import { DatabaseHelper, KnowledgeUnit, Logger } from 'common';

const log: Logger = new Logger('NoteFtsIndex');

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
    } catch (error) {
      log.warn('note_fts upsert failed unit=' + unit.id + ' err=' + (error as Error).message);
    }
  }

  /** 删除后清理索引。 */
  static async remove(unitId: string): Promise<void> {
    const store: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    if (store === null || unitId.length === 0) {
      return;
    }
    try {
      await store.executeSql('DELETE FROM note_fts WHERE unit_id = ?', [unitId]);
    } catch (error) {
      log.warn('note_fts remove failed unit=' + unitId + ' err=' + (error as Error).message);
    }
  }
}
