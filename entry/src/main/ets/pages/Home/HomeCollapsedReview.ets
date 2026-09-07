// ============================================================================
//  pages/Home/HomeCollapsedReview.ets - compact review progress entry
// ============================================================================

import {
  BG_CARD, BORDER, GLASS_10, MINT, MINT_LIGHT, TEXT, TEXT_2, TEXT_3,
  S_1, S_2, S_3, S_4,
  R_LG, R_XL,
  F_XS, F_BASE, F_LG,
  W_BOLD, W_SEMIBOLD,
} from "common"
import { AppIcon } from "../../shared/atoms/AppIcon"

@Component
export struct HomeCollapsedReview {
  @Prop avg: number = 0
  @Prop notesCount: number = 0
  @Prop todayCount: number = 0
  @Prop dateText: string = ""
  @Prop cardHeight: number = 78
  @Prop cardRadius: number = R_XL
  onGoReview: () => void = (): void => {}

  private progressWidth(): string {
    const pct: number = Math.max(0, Math.min(100, this.avg))
    return pct.toString() + "%"
  }

  build() {
    Column() {
      Row() {
        Stack() {
          Circle({ width: 42, height: 42 })
            .fill(MINT_LIGHT)
            .stroke(MINT)
            .strokeWidth(1)
          AppIcon({ name: "review", iconSize: 20, color: MINT, strokeWidth: 1.8 })
        }
        .width(46)
        .height(46)

        Column() {
          Row() {
            Text("复习进度")
              .fontSize(F_BASE)
              .fontWeight(W_SEMIBOLD)
              .fontColor(TEXT)
            Blank()
            Text(this.avg.toString() + "%")
              .fontSize(F_LG)
              .fontWeight(W_BOLD)
              .fontColor(MINT)
          }
          .width("100%")
          .alignItems(VerticalAlign.Center)

          Stack({ alignContent: Alignment.Start }) {
            Row()
              .width("100%")
              .height(6)
              .borderRadius(R_LG)
              .backgroundColor(GLASS_10)
            Row()
              .width(this.progressWidth())
              .height(6)
              .borderRadius(R_LG)
              .backgroundColor(MINT)
          }
          .width("100%")
          .height(6)
          .margin({ top: S_2 })

          Row() {
            Text(this.notesCount.toString() + " 笔记")
              .fontSize(F_XS)
              .fontColor(TEXT_3)
            Text("今日 " + this.todayCount.toString())
              .fontSize(F_XS)
              .fontColor(TEXT_3)
              .margin({ left: S_3 })
            Blank()
            Text(this.dateText)
              .fontSize(F_XS)
              .fontColor(TEXT_2)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width("100%")
          .margin({ top: S_1 })
        }
        .layoutWeight(1)
        .margin({ left: S_3 })

        AppIcon({ name: "chevron-right", iconSize: 16, color: TEXT_2, strokeWidth: 1.8 })
          .margin({ left: S_2 })
      }
      .width("90%")
      .height(this.cardHeight)
      .padding({ left: S_4, right: S_4, top: S_3, bottom: S_3 })
      .alignSelf(ItemAlign.Center)
      .alignItems(VerticalAlign.Center)
      .borderRadius(this.cardRadius)
      .backgroundColor(BG_CARD)
      .border({ width: 0.5, color: BORDER })
      .onClick((): void => { this.onGoReview() })

      Stack() {
        Row()
          .width(16)
          .height(2)
          .borderRadius(1)
          .backgroundColor(TEXT_2)
          .opacity(0.30)
          .rotate({ angle: 26 })
          .position({ x: 7, y: 7 })
        Row()
          .width(16)
          .height(2)
          .borderRadius(1)
          .backgroundColor(TEXT_2)
          .opacity(0.30)
          .rotate({ angle: -26 })
          .position({ x: 21, y: 7 })
      }
        .width(44)
        .height(16)
        .alignSelf(ItemAlign.Center)
        .margin({ top: 0 })
    }
    .width("100%")
    .margin({ top: S_1, bottom: 0 })
  }
}
