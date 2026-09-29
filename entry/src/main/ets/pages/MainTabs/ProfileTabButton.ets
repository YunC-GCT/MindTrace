/**
 * ProfileTabButton.ets — 我的底栏入口
 *
 * 路径: entry/src/main/ets/pages/MainTabs/ProfileTabButton.ets
 * 职责: 提供个人中心图标、文案和选中态，并向导航层转发点击事件。
 * 依赖: TabButton
 *
 * 数据流:
 *   用户点击 → onTap → MainTabNavigation
 */

import { TabButton } from "./TabButton"

@Component
export struct ProfileTabButton {
  @Prop active: boolean = false
  onTap: () => void = (): void => {}

  build() {
    TabButton({
      icon: $r("app.media.ic_me"),
      label: "我的",
      active: this.active,
      onTap: this.onTap,
    })
  }
}
