// ============================================================================
//  pages/MainTabs/AiTabButton.ets — 中央 AI 入口原子组件
//  ----------------------------------------------------------------------------
//  职责: 渲染中央 AI 图形按钮及其说明文字；承托背景由 TabBar 提供。
//  来源: 从 Index.ets AiBtn @Builder 转换为 @Component。
//  接口:
//    onTap — 点击回调
//  ============================================================================

import {
  MINT, PURPLE, BG_DARK,
  AI_BTN_SIZE, AI_ICON_SIZE, SHADOW_AI_BTN,
  F_XS, W_MEDIUM, S_1,
} from "common"

@Component
export struct AiTabButton {
  onTap: () => void = (): void => {}

  build() {
    Column() {
      Stack() {
        Image($r("app.media.ic_ai"))
          .width(AI_ICON_SIZE).height(AI_ICON_SIZE)
          .fillColor(BG_DARK)
      }
      .width(AI_BTN_SIZE).height(AI_BTN_SIZE)
      .borderRadius(AI_BTN_SIZE / 2)
      .linearGradient({
        angle: 135,
        colors: [[MINT, 0], [PURPLE, 1]],
      })
      .shadow(SHADOW_AI_BTN)

      Text("AI 助手")
        .fontSize(F_XS)
        .fontWeight(W_MEDIUM)
        .fontColor(MINT)
        .margin({ top: S_1 })
    }
    .alignItems(HorizontalAlign.Center)
    .onClick((): void => { this.onTap() })
  }
}
