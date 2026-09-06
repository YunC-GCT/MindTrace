// ============================================================================
//  pages/Home/HomeTopBar.ets — 首页顶栏
//  ----------------------------------------------------------------------------
//  职责: 状态栏避让占位 + 6 边形 Logo + MindTrace 标题。
//
//  布局:
//    [状态栏占位 (statusBarH 高)]
//    [HexLogo + "MindTrace" 标题 (HEADER_H 高)]
//
//  依赖:
//    pages: HexLogo
//    common 令牌: BG_DARK / TEXT / S_2 / S_4 / F_MD / W_MEDIUM / HEADER_H
//
//  Props:
//    statusBarHeight: 状态栏高度(由 AppStorage 注入,用于沉浸式占位)
//  ============================================================================

import { BG_DARK, TEXT, S_2, S_4, F_MD, W_MEDIUM, HEADER_H } from "common"
import { HexLogo } from "./HexLogo"

@Component
export struct HomeTopBar {
  // 状态栏高度(从 Index 注入)
  @Prop statusBarHeight: number = 0

  build() {
    Column() {
      // 状态栏占位(沉浸式布局需要让出高度)
      Row()
        .width("100%")
        .height(this.statusBarHeight)
        .backgroundColor(BG_DARK)

      // Logo + 标题
      Row() {
        HexLogo()
        Text("MindTrace")
          .fontFamily("HarmonyOS Sans Condensed")
          .fontSize(F_MD + 2)
          .fontWeight(W_MEDIUM)
          .fontColor(TEXT)
          .margin({ left: S_2 })
      }
      .width("100%")
      .height(HEADER_H)
      .padding({ left: S_4, right: S_4 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor(BG_DARK)
    }
    .width("100%")
  }
}
