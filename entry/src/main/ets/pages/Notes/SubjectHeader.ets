// ============================================================================
//  pages/Notes/SubjectHeader.ets - subject detail top bar
// ============================================================================

import { BG_DARK, MINT, TEXT, TEXT_3, S_2, S_4, S_5, F_XS, F_MD, W_SEMIBOLD } from "common"
import { AppIcon } from "../../shared/atoms/AppIcon"

@Component
export struct SubjectHeader {
  @Prop statusBarHeight: number = 0
  @Prop subject: string = ""
  @Prop count: number = 0
  onBack: () => void = (): void => {}

  build() {
    Column() {
      Row()
        .width("100%")
        .height(this.statusBarHeight)
        .backgroundColor(BG_DARK)

      Row() {
        Button() {
          AppIcon({ name: "chevron-right", iconSize: 24, color: MINT, strokeWidth: 2 })
            .rotate({ angle: 180 })
        }
        .width(32)
        .height(32)
        .backgroundColor(Color.Transparent)
        .margin({ right: S_2 })
        .onClick((): void => this.onBack())

        Text(this.subject)
          .fontSize(F_MD)
          .fontWeight(W_SEMIBOLD)
          .fontColor(TEXT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        Text(this.count.toString() + " 条")
          .fontSize(F_XS)
          .fontColor(TEXT_3)
      }
      .width("100%")
      .padding({ left: S_4, right: S_5, top: S_4, bottom: S_4 })
      .alignItems(VerticalAlign.Center)
    }
    .width("100%")
  }
}
