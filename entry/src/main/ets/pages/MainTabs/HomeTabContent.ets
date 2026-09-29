/**
 * HomeTabContent.ets — 首页 TabContent 装配
 *
 * 路径: entry/src/main/ets/pages/MainTabs/HomeTabContent.ets
 * 职责: 将首页页面与外部导航回调装配到 Tabs 内容项。
 * 依赖: HomePage
 *
 * 数据流:
 *   Index 回调 → HomePage → 用户操作回调
 */

import { HomePage } from "../Home/HomePage"

@Component
export struct HomeTabContent {
  onGoCamera: () => void = (): void => {}
  onGoReview: () => void = (): void => {}

  build() {
    TabContent() {
      HomePage({
        onGoCamera: this.onGoCamera,
        onGoReview: this.onGoReview,
      })
    }
  }
}
