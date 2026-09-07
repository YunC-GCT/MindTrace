// ============================================================================
//  kit/ReminderFacade.ets — D4 P0 Kit 接缝契约 (spec 013)
//  ----------------------------------------------------------------------------
//  职责: 定义复习提醒 (NotificationKit.ReminderAgent) 的最小 facade 接口。
//  约束: 本文件只声明契约, 不 import @kit.*; 实现类由 entry 层注入
//        (entry 可依赖 @kit, common/agents 不依赖 UI/Kit 实现)。
//  ============================================================================

// 提醒请求快照: 由调用方组装, facade 实现负责映射到 ReminderAgent API
export interface ReviewReminderRequest {
  // 关联 KnowledgeUnit.id, 用于取消/去重
  unitId: string;
  // 提醒标题 (如笔记 title)
  title: string;
  // 触发时间戳 (ms since epoch)
  fireAt: number;
  // 可选副标题 (如学科/章节)
  subtitle?: string;
}

export interface ReminderFacade {
  // 安排一次复习提醒; 同 unitId 重复安排应先取消旧提醒
  scheduleReviewReminder(request: ReviewReminderRequest): Promise<void>;
  // 取消该 unit 的全部未触发提醒
  cancelByUnit(unitId: string): Promise<void>;
}
