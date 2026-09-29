/**
 * ReviewPlanRow.ets — 复习计划卡片
 * 路径: entry/src/main/ets/pages/Review/ReviewPlanRow.ets
 * 职责: 展示标题、优先级与队列动作；拖动标题区发出排序意图。
 * 依赖: common 设计令牌、ReviewQueueMoveButton、DeleteButton。
 * 数据流: ReviewPlanView → 展示属性 → 操作回调；业务由父页面处理。
 */
import {
  AMBER, BG_CARD, BORDER, GLASS_8, MINT, PINK, TEXT, TEXT_2, TEXT_3,
  S_1, S_2, S_3,
  R_LG, R_FULL,
  F_XS, F_BASE,
  W_BOLD, W_SEMIBOLD,
} from "common"
import { ReviewQueueMoveButton } from "./ReviewQueueMoveButton"
import { DeleteButton } from "../../shared/atoms/DeleteButton"

@Component
export struct ReviewPlanRow {
  @Prop title: string = ""
  @Prop meta: string = ""
  @Prop tag: string = ""
  @Prop tone: number = 0
  @Prop actionIcon: string = ""
  @Prop actionColor: ResourceColor = TEXT_2
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

      Row({ space: S_1 }) {
        Column({ space: S_1 }) {
          Text(this.title)
            .fontSize(F_BASE)
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
        .height(48)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Start)
        .accessibilityDescription("拖动标题区域调整顺序")
        .gesture(
          PanGesture({ direction: PanDirection.Vertical })
            .onActionStart((): void => { this.dragStartY = this.dragOffset })
            .onActionUpdate((event: GestureEvent): void => {
              this.dragOffset = Math.max(-120, Math.min(120, this.dragStartY + event.offsetY))
              this.updateDragMode()
            })
            .onActionEnd((): void => this.finishDrag())
            .onActionCancel((): void => {
              this.dragOffset = 0
              this.dragMode = 0
            })
        )

        Text(this.tag)
          .fontSize(F_XS)
          .fontWeight(W_BOLD)
          .fontColor(this.dotColor())
          .padding({ left: S_2, right: S_2 })
          .flexShrink(0)

        if (this.actionIcon.length > 0) {
          ReviewQueueMoveButton({
            moveUp: this.actionIcon === "chevron-up",
            color: this.actionColor,
            onTap: (): void => this.onAction(),
          })
        }

        DeleteButton({
          boxSize: 28,
          iconSize: F_XS + 6,
          onTap: (): void => this.onRemovePlan(),
        })
      }
      .width("100%")
      .padding({ left: S_3, right: S_2, top: S_2, bottom: S_2 })
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
  }
}
