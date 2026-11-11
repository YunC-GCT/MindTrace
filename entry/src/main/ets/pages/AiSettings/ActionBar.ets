/**
 * ActionBar.ets — AI 设置页底部操作栏
 *
 * 路径: entry/src/main/ets/pages/AiSettings/ActionBar.ets
 * 职责: 设置页底部的统一保存按钮（模型 + 语义检索等全部设置）。
 * 依赖: common 令牌(MINT / BG_DARK / F_SM / R_MD / S_2)
 *
 * 说明: OCR 走端侧 Kit，原来的 OCR 配置按钮已移除，底部只保留一个保存入口。
 */

import { MINT, BG_DARK, F_SM, R_MD, S_2 } from "common"

@Component
export struct ActionBar {
  onSave?: () => void = (): void => {}

  build() {
    Row() {
      Button("保存设置")
        .fontSize(F_SM)
        .fontColor(BG_DARK)
        .height(44)
        .width("100%")
        .borderRadius(R_MD)
        .backgroundColor(MINT)
        .onClick((): void => {
          if (this.onSave) { this.onSave() }
        })
    }
    .width("100%")
    .padding({ left: S_2, right: S_2, top: 20 })
  }
}
