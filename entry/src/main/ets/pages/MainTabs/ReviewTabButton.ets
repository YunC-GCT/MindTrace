/**
 * ReviewTabButton.ets — 复习底栏入口
 *
 * 路径: entry/src/main/ets/pages/MainTabs/ReviewTabButton.ets
 * 职责: 提供复习图标、文案和选中态，并向导航层转发点击事件。
 * 依赖: TabButton
 *
 * 数据流:
 *   用户点击 → onTap → MainTabNavigation
 */

import { TabButton } from "./TabButton"

@Component
export struct ReviewTabButton {
  @Prop active: boolean = false
  onTap: () => void = (): void => {}

  build() {
    TabButton({
      icon: $r("app.media.ic_review"),
      label: "复习",
      active: this.active,
      onTap: this.onTap,
    })
  }
}
