// ============================================================================
//  pages/Notes/NotesHeader.ets — 笔记列表页顶栏
//  ----------------------------------------------------------------------------
//  职责: 状态栏避让占位 + "笔记"标题 + 学科/笔记计数。
//
//  布局:
//    [状态栏占位]
//    ["笔记" ............ "N 门学科 · M 条"]
//
//  依赖: common 令牌(BG_DARK / TEXT / TEXT_3 / S_4 / S_5 / F_XS / F_MD / W_SEMIBOLD)
//
//  Props:
//    statusBarHeight: 状态栏高度(由 AppStorage 注入)
//    subjectCount:    学科数
//    totalCount:      笔记总数
//  ============================================================================

import {
  BG_DARK, BORDER, GLASS_8, TEXT, TEXT_3,
  S_4, S_5,
  F_XS, F_MD,
  R_MD,
  W_SEMIBOLD,
} from "common"
import { AppIcon } from "../../shared/atoms/AppIcon"

@Component
export struct NotesHeader {
  // 状态栏高度(沉浸式占位)
  @Prop statusBarHeight: number = 0

  @Prop subjectCount: number = 0
  @Prop totalCount: number = 0
  onSearchTap: () => void = (): void => {}

  build() {
    Column() {
      // 状态栏占位
      Row()
        .width("100%")
        .height(this.statusBarHeight)
        .backgroundColor(BG_DARK)

      Row() {
        Text("笔记")
          .fontSize(F_MD)
          .fontWeight(W_SEMIBOLD)
          .fontColor(TEXT)
        Blank()
        Text(this.subjectCount + " 门学科 · " + this.totalCount + " 条")
          .fontSize(F_XS)
          .fontColor(TEXT_3)
          .margin({ right: 10 })
        Row() {
          AppIcon({ name: "search", iconSize: 16, color: TEXT_3, strokeWidth: 1.8 })
        }
        .width(32)
        .height(32)
        .borderRadius(R_MD)
        .backgroundColor(GLASS_8)
        .border({ width: 0.5, color: BORDER })
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick((): void => this.onSearchTap())
      }
      .width("100%")
      .padding({ left: S_5, right: S_5, top: S_4, bottom: S_4 })
      .alignItems(VerticalAlign.Center)
    }
    .width("100%")
  }
}
