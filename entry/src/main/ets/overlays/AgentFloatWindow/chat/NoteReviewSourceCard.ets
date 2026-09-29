/**
 * NoteReviewSourceCard.ets - 笔记复习回答来源卡片
 *
 * 路径: overlays/AgentFloatWindow/chat/NoteReviewSourceCard.ets
 * 职责: 展示单条冻结引用的标题、版本与摘录，并把点击事件交给只读来源浮层
 * 依赖: common UI tokens, NoteEvidenceCitation, AppIcon
 */

import {
  BORDER,
  GLASS_10,
  MINT,
  R_MD,
  S_1,
  S_2,
  S_3,
  TEXT,
  TEXT_2,
  TEXT_3,
  W_MEDIUM,
  W_SEMIBOLD,
} from 'common'
import { NoteEvidenceCitation } from '../../../models/NoteEvidenceModels'
import { AppIcon } from '../../../shared/atoms/AppIcon'

@Component
export struct NoteReviewSourceCard {
  @Prop citation: NoteEvidenceCitation = {
    noteId: '',
    version: 0,
    title: '',
    excerpt: '',
    role: 'hit',
    score: 0,
    matchedFields: [],
    subject: '',
    chapter: '',
  }
  @Prop index: number = 0
  onOpen: (citation: NoteEvidenceCitation) => void = (_citation: NoteEvidenceCitation): void => {}

  build() {
    Row() {
      Column() {
        Text((this.index + 1).toString())
          .fontSize(10)
          .fontColor(MINT)
          .fontWeight(W_SEMIBOLD)
      }
      .width(22)
      .height(22)
      .borderRadius(11)
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .backgroundColor('rgba(91,227,176,0.12)')

      Column() {
        Row() {
          Text(this.citation.title.length > 0 ? this.citation.title : '未命名笔记')
            .fontSize(12)
            .fontColor(TEXT)
            .fontWeight(W_SEMIBOLD)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          Text('v' + this.citation.version.toString())
            .fontSize(10)
            .fontColor(MINT)
            .fontWeight(W_SEMIBOLD)
            .margin({ left: S_2 })
        }
        .width('100%')

        Text(this.citation.excerpt)
          .fontSize(11)
          .fontColor(TEXT_2)
          .fontWeight(W_MEDIUM)
          .lineHeight(16)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: S_1 })

        Row() {
          Text(this.roleLabel())
            .fontSize(10)
            .fontColor(TEXT_3)
          Blank()
          AppIcon({ name: 'chevron-right', iconSize: 13, color: TEXT_3, strokeWidth: 1.6 })
        }
        .width('100%')
        .margin({ top: S_1 })
      }
      .layoutWeight(1)
      .margin({ left: S_2 })
    }
    .width('100%')
    .padding({ left: S_3, right: S_2, top: S_2, bottom: S_2 })
    .borderRadius(R_MD)
    .backgroundColor(GLASS_10)
    .border({ width: 0.5, color: BORDER })
    .onClick((): void => { this.onOpen(this.citation) })
  }

  private roleLabel = (): string => {
    if (this.citation.role === 'prerequisite') {
      return '前置来源'
    }
    if (this.citation.role === 'related') {
      return '关联来源'
    }
    return '直接命中'
  }
}
