// ============================================================================
//  pages/AiSettings/ActionBar.ets — 设置页底部操作栏
//  ----------------------------------------------------------------------------
//  职责: 设置页底部 OCR 专用"重置 OCR"+"保存 OCR"两个操作按钮。
//
//  布局:
//    [重置 OCR (灰色背景)] [保存 OCR (MINT 品牌色背景)]
//
//  依赖: common 令牌(MINT / BG_DARK / TEXT_3 / F_SM / R_MD / S_2)
//
//  Props:
//    onReset: "重置 OCR" 按钮回调
//    onSave:  "保存 OCR" 按钮回调
//  ============================================================================

import { MINT, BG_DARK, TEXT_3, F_SM, R_MD, S_2 } from "common"

@Component
export struct ActionBar {
  // 恢复默认回调
  onReset?: () => void = (): void => {}

  // 保存配置回调
  onSave?: () => void = (): void => {}

  build() {
    Row() {
      // 左侧: 重置 OCR(灰色)
      Button("重置 OCR")
        .fontSize(F_SM)
        .fontColor(TEXT_3)
        .height(44)
        .borderRadius(R_MD)
        .backgroundColor("#1AFFFFFF")
        .layoutWeight(1)
        .onClick((): void => {
          if (this.onReset) { this.onReset() }
        })

      // 右侧: 保存 OCR(MINT 品牌色,主操作)
      Button("保存 OCR")
        .fontSize(F_SM)
        .fontColor(BG_DARK)
        .height(44)
        .borderRadius(R_MD)
        .backgroundColor(MINT)
        .layoutWeight(1)
        .margin({ left: 12 })
        .onClick((): void => {
          if (this.onSave) { this.onSave() }
        })
    }
    .width("100%")
    .padding({ left: S_2, right: S_2, top: 20 })
  }
}
