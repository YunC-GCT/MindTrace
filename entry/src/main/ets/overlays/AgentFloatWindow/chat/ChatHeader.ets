// ============================================================================
//  overlays/AgentFloatWindow/chat/ChatHeader.ets — 浮窗头部
//  ----------------------------------------------------------------------------
//  职责: 模型名 + 在线状态 + 新建对话 + 关闭按钮。
//
//  布局:
//    [● 模型名]  [+]  [✕]
//
//  Props:
//    modelName: 模型名(默认 "DeepSeek-V4-Pro")
//    onNewChat: 新建对话回调
//    onClose:   关闭浮窗回调
//
//  依赖: common ColorTokens + SVG Circle/Path
//  ============================================================================

import { MINT, TEXT_2, TEXT_3,
  S_1, S_2, S_3, S_4,
  F_XS, F_MD, W_MEDIUM,
} from "common"

@Component
export struct ChatHeader {
  // 模型名
  @Prop modelName: string = "DeepSeek-V4-Pro"

  // 新建对话回调
  onNewChat?: () => void = (): void => {}

  // 关闭回调
  onClose?: () => void = (): void => {}

  build() {
    Row() {
      // [● 模型名]
      Circle({ width: 6, height: 6 })
        .fill(MINT)
        .margin({ right: S_2 })
      Text(this.modelName)
        .fontSize(F_XS)
        .fontColor(TEXT_2)
        .fontWeight(W_MEDIUM)

      // [+] 新建对话
      Text("+")
        .fontSize(F_MD)
        .fontColor(TEXT_3)
        .width(32).height(44)
        .textAlign(TextAlign.Center)
        .onClick((): void => {
          if (this.onNewChat) { this.onNewChat() }
        })

      Blank()

      // [✕] 关闭浮窗(用 Path 画 X,不用 emoji)
      Stack() {
        Path()
          .width(14).height(14)
          .commands("M18 6 L6 18 M6 6 L18 18")
          .stroke(TEXT_3)
          .strokeWidth(2)
          .strokeLineCap(LineCapStyle.Round)
          .fill(Color.Transparent)
      }
      .width(32).height(44)
      .alignContent(Alignment.Center)
      .onClick((): void => {
        if (this.onClose) { this.onClose() }
      })
    }
    .width("100%")
    .padding({ left: S_4, right: S_3, top: S_2, bottom: S_1 })
  }
}
