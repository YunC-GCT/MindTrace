/**
 * KnowledgeUnitNotesChangedEffect.ets — 写后副作用：通知 UI 缓存失效
 *
 * 路径: entry/src/main/ets/services/KnowledgeUnitNotesChangedEffect.ets
 * 职责: 数据库提交后通知内存缓存刷新（notesVersion / 明细缓存）
 * 依赖: UiDataCacheService
 *
 * 为什么单独成文件：卡片刷新副作用背后是 @kit.FormKit（只允许 main/form 进程），
 *          扩展进程（小艺端A2A :agent）也要走正规写路径，不能被它拖进受限 Kit。
 */
import { KnowledgeUnit } from 'common';
import { KnowledgeUnitPostCommitEffect } from '../models/KnowledgeUnitWriteModels';
import { UiDataCacheService } from './UiDataCacheService';

export class KnowledgeUnitNotesChangedEffect implements KnowledgeUnitPostCommitEffect {
  name: string = 'notes_changed';

  async run(unit: KnowledgeUnit): Promise<void> {
    UiDataCacheService.notifyNoteChanged(unit.id);
  }
}
