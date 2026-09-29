// ============================================================================
//  pages/MainTabs/AiTabButton.ets — 星轨 AI 入口原子组件
//  ----------------------------------------------------------------------------
//  职责: 渲染星轨图形、AI 按钮及其说明文字；承托背景由 TabBar 提供。
//  来源: 从 Index.ets AiBtn @Builder 转换为 @Component。
//  接口:
//    onTap — 点击回调
//  ============================================================================

import {
  TAB_NAV_ACTIVE, TAB_AI_BG, TAB_AI_BORDER, TAB_AI_INNER_BORDER,
  AI_BTN_SIZE, SHADOW_AI_BTN,
  F_SM, W_MEDIUM, S_2, TAB_LABEL_GAP, TAB_LABEL_HEIGHT, TAB_AI_SLOT_WIDTH,
} from "common"
import { StarOrbitMark } from "./StarOrbitMark"

@Component
export struct AiTabButton {
  onTap: () => void = (): void => {}

  build() {
    Column({ space: TAB_LABEL_GAP }) {
      Stack() {
        Circle({ width: AI_BTN_SIZE - S_2, height: AI_BTN_SIZE - S_2 })
          .fill(Color.Transparent)
          .stroke(TAB_AI_INNER_BORDER)
          .strokeWidth(0.7)
        StarOrbitMark()
      }
      .width(AI_BTN_SIZE).height(AI_BTN_SIZE)
      .borderRadius(AI_BTN_SIZE / 2)
      .backgroundColor(TAB_AI_BG)
      .border({ width: 0.7, color: TAB_AI_BORDER })
      .shadow(SHADOW_AI_BTN)

      Text("AI 助手")
        .fontSize(F_SM)
        .fontWeight(W_MEDIUM)
        .fontColor(TAB_NAV_ACTIVE)
        .height(TAB_LABEL_HEIGHT)
    }
    .width(TAB_AI_SLOT_WIDTH)
    .alignItems(HorizontalAlign.Center)
    .accessibilityText("打开 AI 助手")
    .onClick((): void => { this.onTap() })
  }
}
