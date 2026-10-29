/**
 * KnowledgeUnitPostCommitEffects.ets — KnowledgeUnit 写后副作用：卡片快照刷新
 *
 * 路径: entry/src/main/ets/services/KnowledgeUnitPostCommitEffects.ets
 * 职责: 数据库提交后刷新桌面卡片快照（依赖 @kit.FormKit，只能在 main/form 进程加载）
 * 依赖: CardSnapshotService
 *
 * 注意: 缓存/notesVersion 那条副作用已拆到 KnowledgeUnitNotesChangedEffect.ets，
 *      扩展进程也要写库，不能顺着这里把 FormKit 带进 :agent。
 */
import { common } from '@kit.AbilityKit';
import { KnowledgeUnit } from 'common';
import { KnowledgeUnitPostCommitEffect } from '../models/KnowledgeUnitWriteModels';
import { KnowledgeUnitUiEffectProvider } from './KnowledgeUnitUiEffects';
import { CardSnapshotService } from './CardSnapshotService';

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

/** 主进程注册用：EntryAbility.onCreate 里 register，扩展进程永远不会走到这里。 */
export class CardUiEffectProvider implements KnowledgeUnitUiEffectProvider {
  build(context: common.Context): KnowledgeUnitPostCommitEffect {
    return new KnowledgeUnitCardRefreshEffect(context as common.UIAbilityContext);
  }
}
