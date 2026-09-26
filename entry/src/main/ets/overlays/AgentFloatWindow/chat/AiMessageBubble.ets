/**
 * AiMessageBubble.ets - AI 消息展示入口
 *
 * 路径: overlays/AgentFloatWindow/chat/AiMessageBubble.ets
 * 职责: 渲染 AI 标识并把有序运行步骤交给独立步骤路由
 * 依赖: common UI tokens, AgentRunModels, AgentRunPanel, NoteReviewModels
 *
 * 数据流:
 *   ChatBubble props -> AiMessageBubble -> AgentRunPanel
 */

import {
  BORDER,
  GLASS_10,
  MINT,
  R_MD,
  S_1,
  S_2,
  S_3,
  TEXT_2,
  TEXT_3,
  TEXT_4,
  W_MEDIUM,
  W_SEMIBOLD,
} from 'common'
import { NoteEvidenceCitation } from '../../../models/NoteEvidenceModels'
import { NoteReviewAnswer, NoteReviewFeedback } from '../../../models/NoteReviewModels'
import { AgentRunPart } from './AgentRunModels'
import { AgentRunPanel } from './AgentRunPanel'
import { NoteReviewSourceCard } from './NoteReviewSourceCard'

@Component
export struct AiMessageBubble {
  @Prop parts: AgentRunPart[] = []
  @Prop streaming: boolean = false
  @Prop noteReview: NoteReviewAnswer | null = null
  onSourceTap: (citation: NoteEvidenceCitation) => void = (_citation: NoteEvidenceCitation): void => {}
  onFeedback: (feedback: NoteReviewFeedback) => void = (_feedback: NoteReviewFeedback): void => {}

  build() {
    Row() {
      Column() {
        Row() {
          Text('MindTrace AI')
            .fontSize(10)
            .fontColor(MINT)
            .fontWeight(W_SEMIBOLD)
          if (this.streaming) {
            Text('正在处理')
              .fontSize(9)
              .fontColor(TEXT_4)
              .margin({ left: S_1 })
          }
        }
        .margin({ bottom: S_1, left: S_1 })

        AgentRunPanel({
          parts: this.parts,
          streaming: this.streaming,
        })

        if (this.noteReview !== null) {
          this.NoteReviewMeta(this.noteReview)
        }
      }
      .alignItems(HorizontalAlign.Start)
      Blank()
    }
    .width('100%')
    .margin({ top: S_2 })
  }

  @Builder
  NoteReviewMeta(review: NoteReviewAnswer) {
    Column() {
      if (review.citations.length > 0) {
        Text('来源')
          .fontSize(11)
          .fontColor(TEXT_3)
          .fontWeight(W_SEMIBOLD)
          .margin({ left: S_1, bottom: S_1 })

        ForEach(review.citations,
          (citation: NoteEvidenceCitation, index: number): void => {
            NoteReviewSourceCard({
              citation: citation,
              index: index,
              onOpen: this.onSourceTap,
            })
            .margin({ bottom: S_2 })
          },
          (citation: NoteEvidenceCitation, index: number): string =>
            citation.noteId + ':' + citation.version.toString() + ':' + index.toString()
        )
      } else {
        Column() {
          Text(this.reviewStatusText(review))
            .fontSize(11)
            .fontColor(MINT)
            .fontWeight(W_SEMIBOLD)
            .width('100%')
          if (review.reason.length > 0) {
            Text(review.reason)
              .fontSize(11)
              .fontColor(TEXT_2)
              .fontWeight(W_MEDIUM)
              .lineHeight(16)
              .width('100%')
              .margin({ top: S_1 })
          }
        }
        .width('100%')
        .padding({ left: S_3, right: S_3, top: S_2, bottom: S_2 })
        .borderRadius(R_MD)
        .backgroundColor(GLASS_10)
        .border({ width: 0.5, color: BORDER })
      }

      if (!this.streaming) {
        Row() {
          this.FeedbackButton('有帮助', 'helpful', review.feedback)
          Blank().width(S_2)
          this.FeedbackButton('没帮助', 'unhelpful', review.feedback)
          Blank().width(S_2)
          this.FeedbackButton('引用有误', 'citation-incorrect', review.feedback)
        }
        .width('100%')
        .margin({ top: S_1 })
      }
    }
    .width('94%')
    .margin({ top: S_2, left: S_3 })
  }

  @Builder
  FeedbackButton(label: string, feedback: NoteReviewFeedback, selected: NoteReviewFeedback | undefined) {
    Text(label)
      .fontSize(11)
      .fontColor(selected === feedback ? MINT : TEXT_3)
      .fontWeight(W_SEMIBOLD)
      .padding({ left: S_2, right: S_2, top: S_1, bottom: S_1 })
      .borderRadius(R_MD)
      .backgroundColor(selected === feedback ? 'rgba(91,227,176,0.14)' : 'rgba(255,255,255,0.04)')
      .border({ width: 0.5, color: selected === feedback ? MINT : BORDER })
      .onClick((): void => { this.onFeedback(feedback) })
  }

  private reviewStatusText = (review: NoteReviewAnswer): string => {
    if (review.status === 'grounded') {
      return '已基于笔记回答'
    }
    if (review.status === 'insufficient') {
      return '证据不足'
    }
    return '笔记暂不可用'
  }
}
