/**
 * NoteWritePortFactory.ets — NoteWritePort 的组合根工厂
 *
 * 路径: entry/src/main/ets/services/NoteWritePortFactory.ets
 * 职责: 把 NoteWritePort 的生产链装配起来：KnowledgeUnitWriteService（事务 + post-commit effects）
 *       + NoteGenerationRepository（commitKey 查询）+ NoteDao（版本快照）→ NoteWritePortAdapter。
 * 依赖: 允许 services 层装配 database 实现；业务 service（AiService）只依赖本工厂，不直连 DAO。
 *
 * 数据流:
 *   AiService → NoteWritePortFactory.create → NoteWritePortAdapter(KnowledgeUnitNoteWriteStore)
 *   PersistNode → NoteWritePort.commit → 写服务事务 + post-commit effects
 */
import { common } from '@kit.AbilityKit';
import { DatabaseHelper } from 'common';
import type { NoteWritePort } from 'common';
import { NoteDao } from '../database/NoteDao';
import { NoteGenerationRepository } from '../database/NoteGenerationRepository';
import { KnowledgeUnitNoteWriteStore } from '../database/KnowledgeUnitNoteWriteStore';
import { NoteWritePortAdapter } from '../database/NoteWritePortAdapter';
import { KnowledgeUnitWriteService } from './KnowledgeUnitWriteService';
import { KnowledgeUnitWriteServiceFactory } from './KnowledgeUnitWriteServiceFactory';

export class NoteWritePortFactory {
  static async create(context: common.UIAbilityContext, includeUiEffects: boolean): Promise<NoteWritePort> {
    const service: KnowledgeUnitWriteService =
      await KnowledgeUnitWriteServiceFactory.create(context, includeUiEffects);
    const existing = DatabaseHelper.getStore();
    const store = existing !== null ? existing : await DatabaseHelper.init(context);
    const dao: NoteDao = new NoteDao(store);
    const repository: NoteGenerationRepository = new NoteGenerationRepository(store, dao);
    return new NoteWritePortAdapter(new KnowledgeUnitNoteWriteStore(service, repository, dao));
  }
}
