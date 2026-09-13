/**
 * KnowledgeUnitPostCommitEffects.ets — KnowledgeUnit 写后副作用适配器
 *
 * 路径: entry/src/main/ets/services/KnowledgeUnitPostCommitEffects.ets
 * 职责: 在数据库提交后刷新缓存、notesVersion 和卡片快照
 * 依赖: UiDataCacheService, CardSnapshotService, AppStorage
 *
 * 数据流:
 *   KnowledgeUnitWriteService → effect.run → cache / UI signal / form card
 */
import { common } from '@kit.AbilityKit';
import { KnowledgeUnit } from 'common';
import { KnowledgeUnitPostCommitEffect } from '../models/KnowledgeUnitWriteModels';
import { CardSnapshotService } from './CardSnapshotService';
import { UiDataCacheService } from './UiDataCacheService';

export class KnowledgeUnitCacheInvalidationEffect implements KnowledgeUnitPostCommitEffect {
  name: string = 'cache_invalidation';

  async run(unit: KnowledgeUnit): Promise<void> {
    UiDataCacheService.invalidateNote(unit.id);
  }
}

export class KnowledgeUnitNotesVersionEffect implements KnowledgeUnitPostCommitEffect {
  name: string = 'notes_version';

  async run(unit: KnowledgeUnit): Promise<void> {
    const version: number = AppStorage.get<number>('notesVersion') ?? 0;
    AppStorage.setOrCreate('notesVersion', version + 1);
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
