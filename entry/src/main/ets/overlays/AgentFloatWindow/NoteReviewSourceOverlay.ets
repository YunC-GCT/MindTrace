/**
 * NoteReviewSourceOverlay.ets - 笔记复习来源只读浮层
 *
 * 路径: overlays/AgentFloatWindow/NoteReviewSourceOverlay.ets
 * 职责: 展示 NoteReviewSourceService.resolve 返回的引用原版本状态与只读正文
 * 依赖: common UI tokens, NoteReviewModels, MarkdownRenderer, AppIcon
 */

import {
  BG_DARK,
  BORDER,
  GLASS_10,
  MINT,
  OVERLAY_MASK_SOLID,
  R_MD,
  R_XL,
  S_1,
  S_2,
  S_3,
  S_4,
  S_5,
  TEXT,
  TEXT_2,
  TEXT_3,
  W_MEDIUM,
  W_SEMIBOLD,
} from 'common'
import { NoteEvidenceCitation } from '../../models/NoteEvidenceModels'
import { NoteReviewSourceResult } from '../../models/NoteReviewModels'
import { MarkdownRenderer } from '../../shared/molecules/MarkdownRenderer'
import { AppIcon } from '../../shared/atoms/AppIcon'

@Component
export struct NoteReviewSourceOverlay {
  @Prop loading: boolean = false
  @Prop citation: NoteEvidenceCitation | null = null
  @Prop result: NoteReviewSourceResult | null = null
  onClose: () => void = (): void => {}

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(OVERLAY_MASK_SOLID)
        .onClick((): void => { this.onClose() })

      Column() {
        Row() {
          Column() {
            Text(this.titleText())
              .fontSize(16)
              .fontColor(TEXT)
              .fontWeight(W_SEMIBOLD)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')

            Text(this.subtitleText())
              .fontSize(11)
              .fontColor(TEXT_3)
              .fontWeight(W_MEDIUM)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ top: S_1 })
          }
          .layoutWeight(1)

          Stack() {
            AppIcon({ name: 'close', iconSize: 15, color: TEXT_2, strokeWidth: 1.8 })
          }
          .width(34)
          .height(34)
          .borderRadius(17)
          .backgroundColor(GLASS_10)
          .onClick((): void => { this.onClose() })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        Row() {
          Text(this.statusLabel())
            .fontSize(11)
            .fontColor(MINT)
            .fontWeight(W_SEMIBOLD)
          if (this.statusDetail().length > 0) {
            Text(this.statusDetail())
              .fontSize(11)
              .fontColor(TEXT_3)
              .fontWeight(W_MEDIUM)
              .margin({ left: S_2 })
          }
        }
        .width('100%')
        .padding({ left: S_3, right: S_3, top: S_2, bottom: S_2 })
        .borderRadius(R_MD)
        .backgroundColor('rgba(91,227,176,0.08)')
        .margin({ top: S_3 })

        if (this.loading) {
          Column() {
            Text('正在读取引用版本')
              .fontSize(13)
              .fontColor(TEXT_2)
              .fontWeight(W_MEDIUM)
          }
          .width('100%')
          .padding({ top: S_5, bottom: S_5 })
          .alignItems(HorizontalAlign.Center)
        } else if (this.canRenderContent()) {
          Scroll() {
            Column() {
              MarkdownRenderer({
                text: this.result === null ? '' : this.result.content,
                progressive: false,
                profile: 'note',
              })
            }
            .width('100%')
          }
          .layoutWeight(1)
          .width('100%')
          .margin({ top: S_3 })
          .scrollBar(BarState.Off)
        } else {
          Column() {
            Text(this.emptyMessage())
              .fontSize(13)
              .fontColor(TEXT_2)
              .fontWeight(W_MEDIUM)
              .lineHeight(20)
              .textAlign(TextAlign.Center)
              .width('100%')
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
      }
      .width('92%')
      .height('78%')
      .padding({ left: S_4, right: S_4, top: S_4, bottom: S_4 })
      .borderRadius(R_XL)
      .backgroundColor(BG_DARK)
      .border({ width: 0.5, color: BORDER })
      .shadow({ radius: 24, color: 'rgba(0,0,0,0.28)', offsetX: 0, offsetY: 12 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  private titleText = (): string => {
    if (this.result !== null) {
      return this.result.citation.title.length > 0 ? this.result.citation.title : '来源笔记'
    }
    if (this.citation !== null) {
      return this.citation.title.length > 0 ? this.citation.title : '来源笔记'
    }
    return '来源笔记'
  }

  private subtitleText = (): string => {
    const citation: NoteEvidenceCitation | null = this.result !== null ? this.result.citation : this.citation
    if (citation === null) {
      return '只读查看引用版本'
    }
    return 'noteId=' + citation.noteId + ' · 引用版本 v' + citation.version.toString()
  }

  private statusLabel = (): string => {
    if (this.loading || this.result === null) {
      return '读取中'
    }
    if (this.result.status === 'current') {
      return '当前版本'
    }
    if (this.result.status === 'historical') {
      return '历史版本'
    }
    if (this.result.status === 'deleted') {
      return '已删除'
    }
    if (this.result.status === 'missing-version') {
      return '缺失版本'
    }
    return '读取失败'
  }

  private statusDetail = (): string => {
    if (this.result === null) {
      return ''
    }
    const citationVersion: number = this.result.citation.version
    if (this.result.status === 'current') {
      return 'v' + citationVersion.toString()
    }
    if (this.result.status === 'historical') {
      return '引用 v' + citationVersion.toString() + '，当前 v' + this.result.currentVersion.toString()
    }
    return this.result.message
  }

  private canRenderContent = (): boolean => {
    if (this.result === null || this.result.content.trim().length === 0) {
      return false
    }
    return this.result.status === 'current' || this.result.status === 'historical'
  }

  private emptyMessage = (): string => {
    if (this.result === null) {
      return '暂时没有可展示的来源内容'
    }
    if (this.result.message.length > 0) {
      return this.result.message
    }
    if (this.result.status === 'deleted') {
      return '来源笔记已删除，不能通过历史记录复活正文。'
    }
    if (this.result.status === 'missing-version') {
      return '引用的历史版本不存在，未替换为当前正文。'
    }
    return '来源暂时不可用'
  }
}
