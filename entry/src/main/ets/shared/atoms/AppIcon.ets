// ============================================================================
//  shared/atoms/AppIcon.ets — 共享图标原子组件
// ----------------------------------------------------------------------------
//  路径: entry/src/main/ets/shared/atoms/AppIcon.ets
//  职责: 五入口图标共享草稿的 Lucide 路径，支持描边颜色、线宽和尺寸。
//  依赖: common 令牌；状态: name / iconSize / color / strokeWidth 输入。
//  数据流: 底栏、个人中心、登录及其他页面 → AppIcon → ArkUI Shape。
//  Lucide 路径授权见 resources/rawfile/lucide-license.txt。
// ============================================================================

import { TEXT_3, W_BOLD } from "common"

// 固定 24 × 24 的原稿坐标，不按各页面分别重画图标。
function outlinePath(name: string): string {
  if (name === "home") {
    return "M15 21v-8a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1v8 " +
      "M3 10a2 2 0 0 1 .709-1.528l7-6a2 2 0 0 1 2.582 0l7 6A2 2 0 0 1 21 10v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"
  }
  if (name === "notes") {
    return "M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"
  }
  if (name === "review") {
    return "M4 3H20A2 2 0 0 1 22 5V15A2 2 0 0 1 20 17H4A2 2 0 0 1 2 15V5A2 2 0 0 1 4 3Z M8 21H16 M12 17V21"
  }
  if (name === "me") {
    return "M17 8A5 5 0 1 1 7 8A5 5 0 1 1 17 8Z M20 21a8 8 0 0 0-16 0"
  }
  if (name === "ai") {
    return "M20.341 6.484A10 10 0 0 1 10.266 21.85 M3.659 17.516A10 10 0 0 1 13.74 2.152 " +
      "M15 12A3 3 0 1 1 9 12A3 3 0 1 1 15 12Z M21 5A2 2 0 1 1 17 5A2 2 0 1 1 21 5Z " +
      "M7 19A2 2 0 1 1 3 19A2 2 0 1 1 7 19Z"
  }
  return ""
}

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
      if (outlinePath(this.name).length > 0) {
        Shape() {
          Path().commands(outlinePath(this.name))
        }
        // Path 命令使用 px；视口也必须用 px，避免高密度屏幕缩小图形。
        .viewPort({ x: 0, y: 0, width: "24px", height: "24px" })
        .width(this.iconSize).height(this.iconSize)
        .fill(Color.Transparent)
        .stroke(this.color)
        .strokeWidth(`${this.strokeWidth}px`)
        .strokeLineCap(LineCapStyle.Round)
        .strokeLineJoin(LineJoinStyle.Round)
      } else if (this.name === "camera") {
        Image($r("app.media.ic_camera")).width(this.iconSize).height(this.iconSize).fillColor(this.color)
      } else if (this.name === "album") {
        Image($r("app.media.ic_album")).width(this.iconSize).height(this.iconSize).fillColor(this.color)
      } else if (this.name === "recycle") {
        Image($r("app.media.ic_recycle")).width(this.iconSize).height(this.iconSize).fillColor(this.color)
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
