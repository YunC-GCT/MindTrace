/**
 * AiTabContent.ets — AI TabContent 占位页装配
 *
 * 路径: entry/src/main/ets/pages/MainTabs/AiTabContent.ets
 * 职责: 保留 AI 入口对应的 TabContent，实际交互由全局助手浮层承载。
 * 依赖: common 设计令牌
 *
 * 数据流:
 *   Tabs 触发索引 2 → MainTabNavigation → AgentFloatWindow
 */

import { BG_DARK } from "common"

@Builder
export function buildAiTabContent() {
  TabContent() {
    Column()
      .width("100%")
      .height("100%")
      .backgroundColor(BG_DARK)
  }
}
