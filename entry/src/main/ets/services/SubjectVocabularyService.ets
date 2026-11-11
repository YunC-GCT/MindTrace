/**
 * SubjectVocabularyService.ets — 采集前取一次「库里已有的学科名」。
 *
 * 路径: entry/src/main/ets/services/SubjectVocabularyService.ets
 * 职责: 只读。把 knowledge_unit 里出现过的 subject 去重后交给分类 agent，
 *       让它优先复用已有学科，只有确实没见过才新建。
 * 依赖: DatabaseHelper + NoteDao(只读元数据，不拉正文)
 *
 * 为什么单独一个文件：AiService 属于写侧入口，架构上不允许直连 NoteDao
 * （knowledge-unit-write-service 契约测试会拦），所以读词表单独成 seam。
 */

import { relationalStore } from '@kit.ArkData';
import { DatabaseHelper, KnowledgeUnit } from 'common';
import { NoteDao } from '../database/NoteDao';

export class SubjectVocabularyService {
  /** 去重且保持出现顺序；库未就绪时返回空数组，采集照常走（等价于没有词表）。 */
  static async list(): Promise<string[]> {
    const store: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    if (store === null) {
      return [];
    }
    const dao: NoteDao = new NoteDao(store);
    const units: KnowledgeUnit[] = await dao.queryAllMetadata();
    const subjects: string[] = [];
    for (let i = 0; i < units.length; i++) {
      const subject: string = units[i].subject.trim();
      if (subject.length > 0 && subjects.indexOf(subject) < 0) {
        subjects.push(subject);
      }
    }
    return subjects;
  }
}
