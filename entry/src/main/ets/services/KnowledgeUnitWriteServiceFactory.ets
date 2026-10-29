/**
 * KnowledgeUnitWriteServiceFactory.ets — 生产写入服务组合根
 *
 * 路径: entry/src/main/ets/services/KnowledgeUnitWriteServiceFactory.ets
 * 职责: 用唯一 NoteDao 和写后副作用构造 KnowledgeUnitWriteService
 * 依赖: DatabaseHelper, NoteDao, KnowledgeUnitPostCommitEffects, KnowledgeUnitChapterEdgeEffect
 *
 * 数据流:
 *   entry caller → factory → configured KnowledgeUnitWriteService
 */
import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { DatabaseHelper } from 'common';
import { NoteDao } from '../database/NoteDao';
import { KnowledgeUnitPostCommitEffect } from '../models/KnowledgeUnitWriteModels';
import { KnowledgeUnitNotesChangedEffect } from './KnowledgeUnitNotesChangedEffect';
import { KnowledgeUnitUiEffects } from './KnowledgeUnitUiEffects';
import { KnowledgeUnitChapterEdgeEffect } from './KnowledgeUnitChapterEdgeEffect';
import { KnowledgeUnitWriteService } from './KnowledgeUnitWriteService';

export class KnowledgeUnitWriteServiceFactory {
  /**
   * @param context 应用进程传 UIAbilityContext；扩展进程（小艺端A2A）只有 ExtensionContext，
   *                此时把 includeUiEffects 置 false，跳过依赖 UI 的卡片刷新副作用。
   */
  static async create(context: common.Context, includeUiEffects: boolean = true): Promise<KnowledgeUnitWriteService> {
    const existing: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    const store: relationalStore.RdbStore = existing !== null ? existing : await DatabaseHelper.init(context);
    const effects: KnowledgeUnitPostCommitEffect[] = [];
    effects.push(new KnowledgeUnitNotesChangedEffect());
    if (includeUiEffects) {
      // UI 副作用由主进程注册（EntryAbility.onCreate）后取用；
      // 工厂自己不 import 卡片模块，扩展进程（:agent）因此碰不到 @kit.FormKit。
      const uiEffects: KnowledgeUnitPostCommitEffect[] = KnowledgeUnitUiEffects.build(context);
      for (let i = 0; i < uiEffects.length; i++) {
        effects.push(uiEffects[i]);
      }
    }
    // createOnly: 只在新笔记首次落库后补同章节边，编辑已有笔记不重复补。
    effects.push(new KnowledgeUnitChapterEdgeEffect(store));
    return new KnowledgeUnitWriteService(new NoteDao(store), effects);
  }
}
