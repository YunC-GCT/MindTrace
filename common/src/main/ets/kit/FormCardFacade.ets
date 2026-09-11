// ============================================================================
//  kit/FormCardFacade.ets — D4 P0 Kit 接缝契约 (spec 013)
//  ----------------------------------------------------------------------------
//  职责: 定义桌面服务卡片 (FormKit) 数据回灌的最小 facade 接口,
//        替代现有 FormAbility mock 数据源。
//  约束: 本文件只声明契约, 不 import @ohos.app.form.*; 实现类由 entry 层注入。
//  ============================================================================

// 卡片快照: 今日待复习数 / 连续打卡 / 新增知识点 / 总进度
export interface CardSnapshot {
  todayReviewCount: number;
  streakDays: number;
  newUnitCount: number;
  masteredRatio: number; // 0.0 - 1.0
  updatedAt: number; // ms since epoch
}

export class CardSnapshotBinding {
  todayReviewCount: string = '0';
  streakDays: string = '0';
  newUnitCount: string = '0';
  masteredPercent: string = '0';
  updatedAt: string = '0';

  constructor(snapshot: CardSnapshot) {
    this.todayReviewCount = snapshot.todayReviewCount.toString();
    this.streakDays = snapshot.streakDays.toString();
    this.newUnitCount = snapshot.newUnitCount.toString();
    this.masteredPercent = Math.round(snapshot.masteredRatio * 100).toString();
    this.updatedAt = snapshot.updatedAt.toString();
  }
}

export interface FormCardFacade {
  // 将最新快照推送到全部已添加的卡片实例
  pushSnapshot(snapshot: CardSnapshot): Promise<void>;
}
