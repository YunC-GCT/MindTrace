// ============================================================================
//  services/NoteReviewSourceService.ets — 复习回答来源原版本解析
// ============================================================================
// 职责: 按 noteId/version 只读解析来源; 先确认当前笔记存活, 删除后不从 revision 复活。
// 约束: UI 不访问 DAO; 测试可注入 NoteReviewSourceReader 替身。
// ============================================================================

import { relationalStore } from '@kit.ArkData';
import { DatabaseHelper, KnowledgeUnit } from 'common';
import { NoteDao } from '../database/NoteDao';
import { KnowledgeUnitRevision } from '../models/KnowledgeUnitWriteModels';
import { NoteEvidenceCitation } from '../models/NoteEvidenceModels';
import {
  NoteReviewSourceResolver,
  NoteReviewSourceResult,
} from '../models/NoteReviewModels';

export interface NoteReviewSourceReader {
  queryCurrentUnit(noteId: string): Promise<KnowledgeUnit | null>;
  queryRevision(noteId: string, version: number): Promise<KnowledgeUnitRevision | null>;
}

class NoteDaoSourceReader implements NoteReviewSourceReader {
  private readonly dao: NoteDao;

  constructor(store: relationalStore.RdbStore) {
    this.dao = new NoteDao(store);
  }

  async queryCurrentUnit(noteId: string): Promise<KnowledgeUnit | null> {
    return await this.dao.queryCurrentUnit(noteId);
  }

  async queryRevision(noteId: string, version: number): Promise<KnowledgeUnitRevision | null> {
    return await this.dao.queryRevision(noteId, version);
  }
}

export class NoteReviewSourceService implements NoteReviewSourceResolver {
  private readonly reader: NoteReviewSourceReader | null;

  constructor(reader?: NoteReviewSourceReader) {
    this.reader = reader === undefined ? null : reader;
  }

  async resolve(citation: NoteEvidenceCitation): Promise<NoteReviewSourceResult> {
    const resolvedReader: NoteReviewSourceReader | null = this.resolveReader();
    if (resolvedReader === null) {
      return NoteReviewSourceService.result('unavailable', citation, '', 0, '来源数据库暂不可用');
    }
    try {
      const current: KnowledgeUnit | null = await resolvedReader.queryCurrentUnit(citation.noteId);
      if (current === null) {
        return NoteReviewSourceService.result('deleted', citation, '', 0, '来源笔记已删除，不能通过历史版本复活');
      }
      if (current.version === citation.version) {
        return NoteReviewSourceService.result('current', citation, current.content, current.version, '当前版本');
      }
      const revision: KnowledgeUnitRevision | null = await resolvedReader.queryRevision(citation.noteId, citation.version);
      if (revision === null) {
        return NoteReviewSourceService.result(
          'missing-version',
          citation,
          '',
          current.version,
          '找不到引用版本，已保留当前版本号提示',
        );
      }
      return NoteReviewSourceService.result(
        'historical',
        citation,
        revision.unit.content,
        current.version,
        '历史版本，当前版本为 ' + current.version.toString(),
      );
    } catch (e) {
      return NoteReviewSourceService.result('unavailable', citation, '', 0, '来源读取失败');
    }
  }

  private resolveReader(): NoteReviewSourceReader | null {
    if (this.reader !== null) {
      return this.reader;
    }
    const store: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    if (store === null) {
      return null;
    }
    return new NoteDaoSourceReader(store);
  }

  private static result(
    status: 'current' | 'historical' | 'deleted' | 'missing-version' | 'unavailable',
    citation: NoteEvidenceCitation,
    content: string,
    currentVersion: number,
    message: string,
  ): NoteReviewSourceResult {
    return {
      status: status,
      citation: citation,
      content: content,
      currentVersion: currentVersion,
      message: message,
    };
  }
}
