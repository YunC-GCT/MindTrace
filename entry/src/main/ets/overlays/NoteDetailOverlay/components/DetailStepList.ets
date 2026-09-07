/**
 * DetailStepList.ets — 详情页步骤/过程列表
 *
 * 路径: entry/src/main/ets/overlays/NoteDetailOverlay/components/DetailStepList.ets
 * 职责: 将证明过程、计算步骤等内容渲染为编号阅读路径。
 * 依赖: common tokens, MarkdownRenderer
 *
 * 数据流:
 *   renderer splitReadableLines(content) → DetailStepList → MarkdownRenderer
 *
 * ArkTS 1.1 strict 适配:
 *   - ForEach 使用稳定 key
 *   - struct 内无普通方法
 */

import {
  MINT, TEXT_2, BORDER,
  S_2, S_3,
  R_FULL,
  F_SM,
  W_BOLD,
} from 'common'
import { MarkdownRenderer } from '../../../shared/molecules/MarkdownRenderer'
import { AppIcon } from '../../../shared/atoms/AppIcon'

const DETAIL_STEP_INITIAL_COUNT: number = 3
const DETAIL_STEP_BATCH_SIZE: number = 3

@Component
export struct DetailStepList {
  @Prop @Watch('onItemsChanged') items: string[] = []
  @Prop accentColor: ResourceColor = MINT
  @State visibleItemCount: number = DETAIL_STEP_INITIAL_COUNT

  aboutToAppear(): void {
    this.resetVisibleItems()
  }

  onItemsChanged(): void {
    this.resetVisibleItems()
  }

  build() {
    Column() {
      ForEach(this.visibleItems(),
        (item: string, index: number): void => {
          Row() {
            Text((index + 1).toString())
              .fontSize(F_SM)
              .fontWeight(W_BOLD)
              .fontColor(this.accentColor)
              .width(24)
              .height(24)
              .textAlign(TextAlign.Center)
              .borderRadius(R_FULL)
              .backgroundColor('#0DFFFFFF')
              .border({ width: 0.5, color: BORDER })
              .margin({ right: S_2 })

            Column() {
              MarkdownRenderer({ text: item, progressive: true })
            }
            .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          .margin({ bottom: S_3 })
        },
        (item: string, index: number): string => index.toString() + '_' + item
      )

      if (this.items.length > this.visibleItemCount) {
        Row() {
          Text('继续阅读')
            .fontSize(F_SM)
            .fontWeight(W_BOLD)
            .fontColor(this.accentColor)

          Blank().width(S_2)
          AppIcon({ name: 'chevron-down', iconSize: F_SM, color: this.accentColor, strokeWidth: 1.8 })
        }
        .width('100%')
        .height(40)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick((): void => this.showNextItemBatch())
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private resetVisibleItems = (): void => {
    if (this.items.length <= DETAIL_STEP_INITIAL_COUNT) {
      this.visibleItemCount = this.items.length
      return
    }
    this.visibleItemCount = DETAIL_STEP_INITIAL_COUNT
  }

  private showNextItemBatch = (): void => {
    this.visibleItemCount = this.items.length
  }

  private visibleItems = (): string[] => {
    if (this.items.length <= this.visibleItemCount) {
      return this.items
    }
    return this.items.slice(0, this.visibleItemCount)
  }
}
