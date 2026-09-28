/**
 * DetailStepsSection.ets — 带标题的步骤型详情分块
 *
 * 路径: entry/src/main/ets/overlays/NoteDetailOverlay/components/DetailStepsSection.ets
 * 职责: 为证明过程、计算步骤提供阅读型编号分块。
 * 依赖: common tokens, DetailStepList
 *
 * 数据流:
 *   renderer → DetailStepsSection → DetailStepList
 *
 * ArkTS 1.1 strict 适配:
 *   - struct 内无普通方法
 */

import {
  MINT, TEXT, TEXT_2, BORDER,
  S_2, S_3, S_4,
  F_SM,
  W_BOLD,
} from 'common'
import { DetailStepList } from './DetailStepList'
import { detailLinesSignature } from './DetailSection'
import {
  DetailRenderSession,
  DETAIL_RENDER_PRIORITY_NEAR_VIEWPORT,
} from './DetailRenderSession'

@Component
export struct DetailStepsSection {
  @Prop renderSession: DetailRenderSession = new DetailRenderSession()
  @Prop renderPriority: number = DETAIL_RENDER_PRIORITY_NEAR_VIEWPORT
  @Prop @Watch('onItemsChanged') title: string = ''
  @Prop @Watch('onItemsChanged') items: string[] = []
  @Prop accentColor: ResourceColor = MINT
  @Prop @Watch('onItemsChanged') emphasized: boolean = false
  @State contentReady: boolean = false
  private renderSeq: number = 0
  private contentRenderKey: string = ''

  aboutToAppear(): void {
    this.resetContentRender()
  }

  aboutToDisappear(): void {
    this.renderSeq += 1
  }

  onItemsChanged(): void {
    this.resetContentRender()
  }

  build() {
    if (this.items.length > 0 && this.shouldRenderContent()) {
      Column() {
        Row() {
          Column()
            .width(3)
            .height(16)
            .borderRadius(2)
            .backgroundColor(this.accentColor)
            .margin({ right: S_2 })

          Text(this.title)
            .fontSize(F_SM)
            .fontWeight(W_BOLD)
            .fontColor(this.emphasized ? TEXT : TEXT_2)
            .letterSpacing(0)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: S_2 })

        DetailStepList({
          renderSession: this.renderSession,
          renderPriority: this.renderPriority,
          items: this.items,
          accentColor: this.accentColor,
        })
      }
      .width('100%')
      .padding({ top: S_4, bottom: S_3 })
      .border({ width: { bottom: 0.5 }, color: BORDER })
      .alignItems(HorizontalAlign.Start)
    }
  }

  private resetContentRender = (): void => {
    const key: string = this.title + '|' + detailLinesSignature(this.items) + '|' + (this.emphasized ? '1' : '0')
    if (key === this.contentRenderKey) {
      return
    }
    this.contentRenderKey = key
    this.renderSeq += 1
    const seq: number = this.renderSeq
    if (this.items.length === 0) {
      this.contentReady = false
      return
    }
    if (this.emphasized) {
      this.contentReady = true
      return
    }
    this.contentReady = false
    this.renderSession.enqueue('steps|' + key, DETAIL_RENDER_PRIORITY_NEAR_VIEWPORT, (): void => {
      if (seq !== this.renderSeq) {
        return
      }
      this.contentReady = true
    })
  }

  private shouldRenderContent = (): boolean => {
    return this.emphasized || this.contentReady
  }
}
