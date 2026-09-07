/**
 * DetailSection.ets — 阅读型详情页主分块
 *
 * 路径: entry/src/main/ets/overlays/NoteDetailOverlay/components/DetailSection.ets
 * 职责: 提供唯一明显正文分块，内部交给 MarkdownRenderer 渲染内容。
 * 依赖: common tokens, MarkdownRenderer
 *
 * 数据流:
 *   renderer → DetailSection → MarkdownRenderer
 *
 * ArkTS 1.1 strict 适配:
 *   - struct 内无普通方法
 *   - 字段名避开 CommonAttribute 方法
 */

import {
  MINT, TEXT, TEXT_2, BORDER,
  S_2, S_3, S_4,
  F_SM,
  W_BOLD,
} from 'common'
import { MarkdownRenderer } from '../../../shared/molecules/MarkdownRenderer'
import {
  DETAIL_RENDER_PRIORITY_NORMAL,
  enqueueDetailRender,
} from './DetailRenderQueue'

export function detailTextSignature(text: string): string {
  let hash: number = 5381
  let index: number = 0
  while (index < text.length) {
    hash = ((hash << 5) + hash + text.charCodeAt(index)) | 0
    index += 1
  }
  const positive: number = hash < 0 ? -hash : hash
  return text.length.toString() + ':' + positive.toString()
}

export function detailLinesSignature(items: string[]): string {
  let hash: number = 5381
  let length: number = 0
  for (const item of items) {
    length += item.length + 1
    let index: number = 0
    while (index < item.length) {
      hash = ((hash << 5) + hash + item.charCodeAt(index)) | 0
      index += 1
    }
    hash = ((hash << 5) + hash + 10) | 0
  }
  const positive: number = hash < 0 ? -hash : hash
  return length.toString() + ':' + positive.toString()
}

@Component
export struct DetailSection {
  @Prop @Watch('onContentChanged') title: string = ''
  @Prop @Watch('onContentChanged') content: string = ''
  @Prop accentColor: ResourceColor = MINT
  @Prop @Watch('onContentChanged') emphasized: boolean = false
  @State contentReady: boolean = false
  private renderSeq: number = 0
  private contentRenderKey: string = ''

  aboutToAppear(): void {
    this.resetContentRender()
  }

  aboutToDisappear(): void {
    this.renderSeq += 1
  }

  onContentChanged(): void {
    this.resetContentRender()
  }

  build() {
    if (this.content.trim().length > 0 && this.shouldRenderContent()) {
      Column() {
        if (this.title.trim().length > 0) {
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
        }

        MarkdownRenderer({ text: this.content, progressive: true })
      }
      .width('100%')
      .padding({ top: S_4, bottom: S_3 })
      .border({ width: { bottom: 0.5 }, color: BORDER })
      .alignItems(HorizontalAlign.Start)
    }
  }

  private resetContentRender = (): void => {
    const content: string = this.content.trim()
    const key: string = this.title + '|' + detailTextSignature(content) + '|' + (this.emphasized ? '1' : '0')
    if (key === this.contentRenderKey) {
      return
    }
    this.contentRenderKey = key
    this.renderSeq += 1
    const seq: number = this.renderSeq
    if (content.length === 0) {
      this.contentReady = false
      return
    }
    if (this.emphasized) {
      this.contentReady = true
      return
    }
    this.contentReady = false
    enqueueDetailRender(key, DETAIL_RENDER_PRIORITY_NORMAL, (): void => {
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
