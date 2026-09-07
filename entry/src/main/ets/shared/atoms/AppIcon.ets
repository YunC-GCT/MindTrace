// ============================================================================
//  shared/atoms/AppIcon.ets - lightweight icon component
// ----------------------------------------------------------------------------
//  Prefer existing SVG resources. For missing assets, use compact glyph marks
//  with stable sizing instead of hand-rolled Path viewBox math.
// ============================================================================

import { TEXT_3, W_BOLD } from "common"

@Component
export struct AppIcon {
  @Prop name: string = "notes"
  @Prop iconSize: number = 16
  @Prop color: ResourceColor = TEXT_3
  @Prop strokeWidth: number = 2

  private glyph = (): string => {
    if (this.name === "close") { return "x" }
    if (this.name === "check") { return "\u2713" }
    if (this.name === "plus") { return "+" }
    if (this.name === "edit") { return "Edit" }
    if (this.name === "share") { return "\u2197" }
    if (this.name === "more") { return "..." }
    if (this.name === "copy") { return "Copy" }
    if (this.name === "refresh") { return "\u21bb" }
    if (this.name === "feedback") { return "!" }
    if (this.name === "book") { return "Book" }
    if (this.name === "chevron-right") { return "\u203a" }
    if (this.name === "chevron-up") { return "\u02c4" }
    if (this.name === "chevron-down") { return "\u25be" }
    if (this.name === "handle") { return "\u2261" }
    if (this.name === "star") { return "\u2726" }
    if (this.name === "paperclip") { return "Link" }
    return ""
  }

  build() {
    Stack() {
      if (this.name === "notes") {
        Image($r("app.media.ic_notes")).width(this.iconSize).height(this.iconSize).fillColor(this.color)
      } else if (this.name === "ai") {
        Image($r("app.media.ic_ai")).width(this.iconSize).height(this.iconSize).fillColor(this.color)
      } else if (this.name === "review") {
        Image($r("app.media.ic_review")).width(this.iconSize).height(this.iconSize).fillColor(this.color)
      } else if (this.name === "me") {
        Image($r("app.media.ic_me")).width(this.iconSize).height(this.iconSize).fillColor(this.color)
      } else if (this.name === "home") {
        Image($r("app.media.ic_home")).width(this.iconSize).height(this.iconSize).fillColor(this.color)
      } else if (this.name === "camera") {
        Image($r("app.media.ic_camera")).width(this.iconSize).height(this.iconSize).fillColor(this.color)
      } else if (this.name === "album") {
        Image($r("app.media.ic_album")).width(this.iconSize).height(this.iconSize).fillColor(this.color)
      } else if (this.name === "recycle") {
        Image($r("app.media.ic_recycle")).width(this.iconSize).height(this.iconSize).fillColor(this.color)
      } else if (this.name === "trash") {
        Stack() {
          Row()
            .width(this.iconSize * 0.68)
            .height(this.strokeWidth)
            .backgroundColor(this.color)
            .borderRadius(this.strokeWidth / 2)
            .translate({ y: -this.iconSize * 0.34 })
          Row()
            .width(this.iconSize * 0.28)
            .height(this.strokeWidth)
            .backgroundColor(this.color)
            .borderRadius(this.strokeWidth / 2)
            .translate({ y: -this.iconSize * 0.46 })
          Row() {
            Column()
              .width(this.strokeWidth)
              .height(this.iconSize * 0.52)
              .backgroundColor(this.color)
              .borderRadius(this.strokeWidth / 2)
            Blank().width(this.iconSize * 0.18)
            Column()
              .width(this.strokeWidth)
              .height(this.iconSize * 0.52)
              .backgroundColor(this.color)
              .borderRadius(this.strokeWidth / 2)
          }
          .width(this.iconSize * 0.5)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .translate({ y: this.iconSize * 0.04 })
          Row()
            .width(this.iconSize * 0.58)
            .height(this.strokeWidth)
            .backgroundColor(this.color)
            .borderRadius(this.strokeWidth / 2)
            .translate({ y: this.iconSize * 0.32 })
        }
        .width(this.iconSize)
        .height(this.iconSize)
        .alignContent(Alignment.Center)
      } else if (this.name === "search") {
        Stack() {
          Circle({ width: this.iconSize * 0.62, height: this.iconSize * 0.62 })
            .fill(Color.Transparent)
            .stroke(this.color)
            .strokeWidth(this.strokeWidth)
            .translate({ x: -this.iconSize * 0.08, y: -this.iconSize * 0.08 })
          Row()
            .width(this.iconSize * 0.38)
            .height(this.strokeWidth)
            .backgroundColor(this.color)
            .borderRadius(this.strokeWidth / 2)
            .rotate({ angle: 45 })
            .translate({ x: this.iconSize * 0.22, y: this.iconSize * 0.22 })
        }
        .width(this.iconSize)
        .height(this.iconSize)
        .alignContent(Alignment.Center)
      } else if (this.name === "circle") {
        Circle({ width: this.iconSize * 0.72, height: this.iconSize * 0.72 })
          .fill(Color.Transparent)
          .stroke(this.color)
          .strokeWidth(this.strokeWidth)
      } else {
        Text(this.glyph())
          .fontSize(this.iconSize <= 14 ? this.iconSize - 3 : this.iconSize - 4)
          .fontColor(this.color)
          .fontWeight(W_BOLD)
          .maxLines(1)
          .textAlign(TextAlign.Center)
          .width(this.iconSize * 1.8)
      }
    }
    .width(this.iconSize).height(this.iconSize)
    .alignContent(Alignment.Center)
  }
}
