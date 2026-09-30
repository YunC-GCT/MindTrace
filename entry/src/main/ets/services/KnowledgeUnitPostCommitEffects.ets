/**
 * KnowledgeUnitPostCommitEffects.ets — KnowledgeUnit 写后副作用适配器
 *
 * 路径: entry/src/main/ets/services/KnowledgeUnitPostCommitEffects.ets
 * 职责: 在数据库提交后刷新缓存、notesVersion 和卡片快照
 * 依赖: UiDataCacheService, CardSnapshotService
 *
 * 数据流:
 *   KnowledgeUnitWriteService → effect.run → cache / UI signal / form card
 */
import { common } from '@kit.AbilityKit';
import { KnowledgeUnit } from 'common';
import { KnowledgeUnitPostCommitEffect } from '../models/KnowledgeUnitWriteModels';
import { CardSnapshotService } from './CardSnapshotService';
import { UiDataCacheService } from './UiDataCacheService';

export class KnowledgeUnitNotesChangedEffect implements KnowledgeUnitPostCommitEffect {
  name: string = 'notes_changed';

  async run(unit: KnowledgeUnit): Promise<void> {
    UiDataCacheService.notifyNoteChanged(unit.id);
  }
}

export class KnowledgeUnitCardRefreshEffect implements KnowledgeUnitPostCommitEffect {
  name: string = 'card_refresh';
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async run(unit: KnowledgeUnit): Promise<void> {
    await CardSnapshotService.refresh(this.context);
  }
}
