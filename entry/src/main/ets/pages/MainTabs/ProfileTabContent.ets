/**
 * ProfileTabContent.ets — 我的 TabContent 装配
 *
 * 路径: entry/src/main/ets/pages/MainTabs/ProfileTabContent.ets
 * 职责: 将个人中心页面装配到 Tabs 内容项。
 * 依赖: ProfilePage
 *
 * 数据流:
 *   Tabs → ProfilePage
 */

import { ProfilePage } from "../Profile/ProfilePage"

@Builder
export function buildProfileTabContent() {
  TabContent() {
    ProfilePage()
  }
}
