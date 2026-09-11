/**
 * KnowledgeUnitWriteServiceFactory.ets — 生产写入服务组合根
 *
 * 路径: entry/src/main/ets/services/KnowledgeUnitWriteServiceFactory.ets
 * 职责: 用唯一 NoteDao 和写后副作用构造 KnowledgeUnitWriteService
 * 依赖: DatabaseHelper, NoteDao, KnowledgeUnitPostCommitEffects
 *
 * 数据流:
 *   entry caller → factory → configured KnowledgeUnitWriteService
 */
import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { DatabaseHelper } from 'common';
import { NoteDao } from '../database/NoteDao';
import { KnowledgeUnitPostCommitEffect } from '../models/KnowledgeUnitWriteModels';
import {
  KnowledgeUnitCacheInvalidationEffect,
  KnowledgeUnitCardRefreshEffect,
  KnowledgeUnitNotesVersionEffect,
} from './KnowledgeUnitPostCommitEffects';
import { KnowledgeUnitWriteService } from './KnowledgeUnitWriteService';

export class KnowledgeUnitWriteServiceFactory {
  static async create(context: common.UIAbilityContext): Promise<KnowledgeUnitWriteService> {
    const existing: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    const store: relationalStore.RdbStore = existing !== null ? existing : await DatabaseHelper.init(context);
    const effects: KnowledgeUnitPostCommitEffect[] = [
      new KnowledgeUnitCacheInvalidationEffect(),
      new KnowledgeUnitNotesVersionEffect(),
      new KnowledgeUnitCardRefreshEffect(context),
    ];
    return new KnowledgeUnitWriteService(new NoteDao(store), effects);
  }
}
