import {
  AMBER, BG_CARD, BORDER, GLASS_8, MINT, PINK, TEXT, TEXT_2, TEXT_3,
  S_2, S_3,
  R_LG, R_FULL,
  F_XS, F_SM,
  W_BOLD, W_SEMIBOLD,
} from "common"
import { AppIcon } from "../../shared/atoms/AppIcon"

@Component
export struct ReviewPlanRow {
  @Prop title: string = ""
  @Prop meta: string = ""
  @Prop tag: string = ""
  @Prop tone: number = 0
  @Prop actionIcon: string = ""
  @Prop actionColor: ResourceColor = TEXT_2
  @Prop deleteIcon: string = ""
  @Prop deleteColor: ResourceColor = TEXT_3
  @State dragOffset: number = 0
  @State dragMode: number = 0
  private dragStartY: number = 0
  onAction: () => void = (): void => {}
  onMoveUp: () => void = (): void => {}
  onMoveDown: () => void = (): void => {}
  onCrossUp: () => void = (): void => {}
  onCrossDown: () => void = (): void => {}
  onRemovePlan: () => void = (): void => {}

  private dotColor(): ResourceColor {
    if (this.tone === 1) {
      return AMBER
    }
    if (this.tone === 2) {
      return PINK
    }
    return MINT
  }

  private rowBg(): ResourceColor {
    if (this.dragMode === 0) {
      return BG_CARD
    }
    return GLASS_8
  }

  private rowBorderColor(): ResourceColor {
    if (this.dragMode === 0) {
      return BORDER
    }
    return MINT
  }

  private handleColor(): ResourceColor {
    if (this.dragMode === 0) {
      return TEXT_2
    }
    return MINT
  }

  private slotColor(): ResourceColor {
    if (this.dragMode === -2 || this.dragMode === 2) {
      return AMBER
    }
    return MINT
  }

  private rowOpacity(): number {
    if (this.dragMode === 0) {
      return 1
    }
    return 0.92
  }

  private rowScale(): number {
    if (this.dragMode === 0) {
      return 1
    }
    return 0.985
  }

  private updateDragMode(): void {
    if (this.dragOffset <= -96) {
      this.dragMode = -2
      return
    }
    if (this.dragOffset <= -24) {
      this.dragMode = -1
      return
    }
    if (this.dragOffset >= 96) {
      this.dragMode = 2
      return
    }
    if (this.dragOffset >= 24) {
      this.dragMode = 1
      return
    }
    this.dragMode = 0
  }

  private finishDrag(): void {
    const mode: number = this.dragMode
    this.dragOffset = 0
    this.dragMode = 0
    if (mode === -2) {
      this.onCrossUp()
      return
    }
    if (mode === -1) {
      this.onMoveUp()
      return
    }
    if (mode === 1) {
      this.onMoveDown()
      return
    }
    if (mode === 2) {
      this.onCrossDown()
    }
  }

  @Builder
  DropSlot() {
    Row()
      .width("100%")
      .height(12)
      .borderRadius(R_FULL)
      .backgroundColor(this.slotColor())
      .opacity(0.75)
  }

  build() {
    Column({ space: 4 }) {
      if (this.dragMode < 0) {
        this.DropSlot()
      }

      Row({ space: S_3 }) {
        AppIcon({ name: "handle", iconSize: F_XS + 7, color: this.handleColor(), strokeWidth: 1.8 })
          .width(16)
          .flexShrink(0)

        Circle({ width: 8, height: 8 })
          .fill(this.dotColor())
          .flexShrink(0)

        Column({ space: 3 }) {
          Text(this.title)
            .fontSize(F_SM + 1)
            .fontWeight(W_SEMIBOLD)
            .fontColor(TEXT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width("100%")

          Text(this.meta)
            .fontSize(F_XS)
            .fontColor(TEXT_3)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width("100%")
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Row({ space: 3 }) {
          Text(this.tag)
            .fontSize(F_XS)
            .fontWeight(W_BOLD)
            .fontColor(MINT)
            .height(24)
            .padding({ left: S_2, right: S_2 })
            .borderRadius(R_FULL)
            .backgroundColor(GLASS_8)

          if (this.actionIcon.length > 0) {
            Button() {
              AppIcon({ name: this.actionIcon, iconSize: F_XS + 6, color: this.actionColor, strokeWidth: 1.8 })
            }
            .width(28)
            .height(28)
            .borderRadius(R_FULL)
            .backgroundColor(GLASS_8)
            .onClick((): void => this.onAction())
          }

          if (this.deleteIcon.length > 0) {
            Button() {
              AppIcon({ name: this.deleteIcon, iconSize: F_XS + 6, color: this.deleteColor, strokeWidth: 1.8 })
            }
            .width(28)
            .height(28)
            .borderRadius(R_FULL)
            .backgroundColor(GLASS_8)
            .onClick((): void => this.onRemovePlan())
          }
        }
        .flexShrink(0)
        .alignItems(VerticalAlign.Center)
      }
      .width("100%")
      .height(58)
      .padding({ left: S_3, right: S_3 })
      .backgroundColor(this.rowBg())
      .border({ width: this.dragMode === 0 ? 0.5 : 1, color: this.rowBorderColor() })
      .borderRadius(R_LG)
      .alignItems(VerticalAlign.Center)
      .opacity(this.rowOpacity())
      .scale({ x: this.rowScale(), y: this.rowScale() })
      .translate({ y: this.dragOffset })

      if (this.dragMode > 0) {
        this.DropSlot()
      }
    }
    .width("100%")
    .gesture(
      PanGesture({ direction: PanDirection.Vertical })
        .onActionStart((): void => {
          this.dragStartY = this.dragOffset
        })
        .onActionUpdate((event: GestureEvent): void => {
          const nextOffset: number = this.dragStartY + event.offsetY
          this.dragOffset = Math.max(-120, Math.min(120, nextOffset))
          this.updateDragMode()
        })
        .onActionEnd((): void => {
          this.finishDrag()
        })
    )
  }
}
