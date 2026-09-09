// ============================================================================
//  pages/AiSettings/ConnectionStatus.ets — 设置页连接状态行
//  ----------------------------------------------------------------------------
//  职责: 显示当前 LLM 连接状态(文字 + 状态圆点 + 测试按钮),给用户一眼判断。
//
//  布局:
//    ["连接状态" 标签 + 状态文字]  [... 空白 ...]  [状态圆点]  [测试按钮]
//
//  依赖: common 令牌(MINT / BG_CARD / BG_DARK / TEXT / TEXT_3 / TEXT_4 / F_XS /
//         F_BASE / W_SEMIBOLD / S_4 / R_LG / R_MD)
//
//  Props:
//    configured: 是否已配置 API Key(决定圆点和文字颜色)
//    statusText: 状态文字(如 "已配置 · 连接正常" / "未配置")
//    testing:    是否正在测试连接(决定按钮禁用 + 显示 "...")
//    onTest:     测试按钮点击回调
//  ============================================================================

import { MINT, BG_CARD, BG_DARK, TEXT, TEXT_3, TEXT_4, F_XS, F_BASE, W_SEMIBOLD, S_4, R_LG, R_MD } from "common"

@Component
export struct ConnectionStatus {
  // 是否已配置(决定圆点 + 文字颜色,MINT = 已配置,灰色 = 未配置)
  @Prop configured: boolean = false

  // 状态文字(如 "已配置 · 连接正常")
  @Prop statusText: string = "未配置"

  // 是否正在测试连接
  @Prop testing: boolean = false

  // 测试按钮点击回调
  onTest?: () => void = (): void => {}

  build() {
    Row() {
      // 左侧: 标签 + 状态文字
      Column() {
        Text("连接状态")
          .fontSize(F_XS)
          .fontColor(TEXT_3)
          .margin({ bottom: 4 })

        Text(this.statusText)
          .fontSize(F_BASE)
          .fontWeight(W_SEMIBOLD)
          .fontColor(this.configured ? MINT : TEXT_4)
      }
      .alignItems(HorizontalAlign.Start)

      Blank()

      // 状态圆点
      Circle({ width: 10, height: 10 })
        .fill(this.configured ? MINT : TEXT_4)
        .margin({ right: 12 })

      // 测试按钮(放最右,2026-09-08 UX 调整)
      Button(this.testing ? "..." : "测试")
        .fontSize(F_XS)
        .fontColor(BG_DARK)
        .height(32)
        .borderRadius(R_MD)
        .backgroundColor(MINT)
        .enabled(!this.testing)
        .onClick((): void => {
          if (this.onTest) { this.onTest() }
        })
    }
    .width("100%")
    .padding(S_4)
    .borderRadius(R_LG)
    .backgroundColor(BG_CARD)
    .margin({ left: 8, right: 8 })
  }
}
