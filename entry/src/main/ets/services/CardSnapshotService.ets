/**
 * CardSnapshotService.ets — 卡片快照聚合服务
 *
 * 路径: entry/src/main/ets/services/CardSnapshotService.ets
 * 职责: 聚合今日复习卡所需统计(due / new / mastered),并通过 FormCardFacade 推送
 * 依赖: common CardSnapshot/DatabaseHelper/KnowledgeUnit/ReviewStatus, ../database/NoteDao, ../kit/FormCardFacadeImpl
 *
 * 数据流:
 *   NoteDao.queryAllMetadata → 聚合计数 → CardSnapshot → FormCardFacadeImpl.pushSnapshot
 *
 * ArkTS 1.1 strict 适配:
 *   - 全部用静态方法,不持有状态
 *   - Date 构造放函数顶部,避免反复 new
 */
import { common } from '@kit.AbilityKit';
import { CardSnapshot, DatabaseHelper, KnowledgeUnit, ReviewStatus } from 'common';
import { NoteDao } from '../database/NoteDao';
import { getFormCardFacade } from '../kit/FormCardFacadeImpl';

export class CardSnapshotService {
  static async refresh(context: common.UIAbilityContext): Promise<void> {
    const facade = getFormCardFacade();
    if (facade === null) {
      return;
    }
    const store = await DatabaseHelper.init(context);
    const units: KnowledgeUnit[] = await new NoteDao(store).queryAllMetadata();
    const now: number = Date.now();
    const start: Date = new Date(new Date().getFullYear(), new Date().getMonth(), new Date().getDate());
    let dueCount: number = 0;
    let newCount: number = 0;
    let masteredCount: number = 0;
    for (const unit of units) {
      if (unit.reviewStatus !== ReviewStatus.GRADUATED && unit.nextReviewAt <= now) {
        dueCount += 1;
      }
      if (unit.createdAt >= start.getTime()) {
        newCount += 1;
      }
      if (unit.reviewStatus === ReviewStatus.GRADUATED) {
        masteredCount += 1;
      }
    }
    const snapshot: CardSnapshot = {
      todayReviewCount: dueCount,
      streakDays: 0,
      newUnitCount: newCount,
      masteredRatio: units.length > 0 ? masteredCount / units.length : 0,
      updatedAt: now,
    };
    await facade.pushSnapshot(snapshot);
  }
}
