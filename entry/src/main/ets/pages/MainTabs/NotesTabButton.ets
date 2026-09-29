/**
 * NotesTabButton.ets — 笔记底栏入口
 *
 * 路径: entry/src/main/ets/pages/MainTabs/NotesTabButton.ets
 * 职责: 提供笔记图标、文案和选中态，并向导航层转发点击事件。
 * 依赖: TabButton
 *
 * 数据流:
 *   用户点击 → onTap → MainTabNavigation
 */

import { TabButton } from "./TabButton"

@Component
export struct NotesTabButton {
  @Prop active: boolean = false
  onTap: () => void = (): void => {}

  build() {
    TabButton({
      icon: $r("app.media.ic_notes"),
      label: "笔记",
      active: this.active,
      onTap: this.onTap,
    })
  }
}
