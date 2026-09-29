/**
 * ReviewTabContent.ets — 复习 TabContent 装配
 *
 * 路径: entry/src/main/ets/pages/MainTabs/ReviewTabContent.ets
 * 职责: 将复习页面与 AI 助手回调装配到 Tabs 内容项。
 * 依赖: ReviewPage
 *
 * 数据流:
 *   Index 回调 → ReviewPage → onGoAI → AgentFloatWindow
 */

import { ReviewPage } from "../Review/ReviewPage"

@Component
export struct ReviewTabContent {
  onGoAI: () => void = (): void => {}

  build() {
    TabContent() {
      ReviewPage({ onGoAI: this.onGoAI })
    }
  }
}
