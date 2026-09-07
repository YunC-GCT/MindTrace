// ============================================================================
//  overlays/NoteDetailOverlay/NoteCloseButton.ets — 笔记详情浮层关闭按钮
//  ----------------------------------------------------------------------------
//  职责: 浮层右上角的圆形 X 关闭按钮(纯展示 + 点击回调)。
//
//  布局:
//    [ ✕ ] (玻璃底,圆形,中央 X 图标)
//
//  Props:
//    onClose: 点击回调
//
//  依赖:
//    shared: AppIcon(name=close)
//    common 令牌: TEXT_2 / GLASS_10 / S_4
//
//  来源: 从 NoteDetailOverlay 拆出(2026-07-15 W2 原子化)
//  ============================================================================

import { TEXT_2, GLASS_10, S_4 } from "common"
import { AppIcon } from "../../shared/atoms/AppIcon"

@Component
export struct NoteCloseButton {
  // 关闭回调
  onClose: () => void = (): void => {}

  build() {
    Stack() {
      // 关闭图标(lucide close)
      AppIcon({ name: "close", iconSize: 16, color: TEXT_2, strokeWidth: 2 })
    }
    .width(S_4 * 2)  // 32vp
    .height(S_4 * 2)
    .borderRadius(22)
    .backgroundColor(GLASS_10)
    .alignContent(Alignment.Center)
    .onClick((): void => this.onClose())
  }
}
