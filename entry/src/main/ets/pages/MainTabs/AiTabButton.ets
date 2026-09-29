// ============================================================================
//  pages/MainTabs/AiTabButton.ets — 星轨 AI 入口原子组件
//  ----------------------------------------------------------------------------
//  职责: 渲染星轨图形、AI 按钮及其说明文字；承托背景由 TabBar 提供。
//  来源: 从 Index.ets AiBtn @Builder 转换为 @Component。
//  接口:
//    onTap — 点击回调
//  ============================================================================

import {
  MINT, BG_DARK, BORDER,
  AI_BTN_SIZE, SHADOW_AI_BTN,
  F_XS, W_MEDIUM, S_1,
} from "common"
import { StarOrbitMark } from "./StarOrbitMark"

@Component
export struct AiTabButton {
  onTap: () => void = (): void => {}

  build() {
    Column() {
      Stack() {
        StarOrbitMark({ orbitSize: 30, color: MINT })
      }
      .width(AI_BTN_SIZE + 8).height(AI_BTN_SIZE + 8)
      .borderRadius(AI_BTN_SIZE / 2)
      .backgroundColor(BG_DARK)
      .border({ width: 1, color: BORDER })
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
