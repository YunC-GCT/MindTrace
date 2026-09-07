// ============================================================================
//  kit/BackgroundTaskFacade.ets — D4 P0 Kit 接缝契约 (spec 013)
//  ----------------------------------------------------------------------------
//  职责: 定义后台任务 (BackgroundTasksKit) 的最小 facade 接口。
//  约束: 本文件只声明契约, 不 import @kit.*; 实现类由 entry 层注入。
//  ============================================================================

export type BackgroundTaskTag = 'review_sync' | 'note_backup';

export interface BackgroundTaskFacade {
  // 申请一次短时后台任务; 返回是否获批 (系统可能拒绝)
  requestOneShot(tag: BackgroundTaskTag): Promise<boolean>;
  // 查询当前是否已有同 tag 任务在执行
  hasPending(tag: BackgroundTaskTag): boolean;
}
