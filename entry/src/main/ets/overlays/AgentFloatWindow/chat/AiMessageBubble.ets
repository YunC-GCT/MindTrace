/**
 * AiMessageBubble.ets - AI 消息展示入口
 *
 * 路径: overlays/AgentFloatWindow/chat/AiMessageBubble.ets
 * 职责: 渲染 AI 标识并把有序运行步骤交给独立步骤路由
 * 依赖: common UI tokens, AgentRunModels, AgentRunPanel
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
  TEXT,
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
import { ChatMessageOutcome } from './ChatModels'
import { NoteReviewSourceCard } from './NoteReviewSourceCard'

@Component
export struct AiMessageBubble {
  @Prop parts: AgentRunPart[] = []
  @Prop streaming: boolean = false
  @Prop outcome: ChatMessageOutcome = 'completed'
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
          } else if (this.outcome !== 'completed') {
            Text(this.outcomeLabel())
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
          this.NoteReviewBlock(this.noteReview)
        }
      }
      .alignItems(HorizontalAlign.Start)
      Blank()
    }
    .width('100%')
    .margin({ top: S_2 })
  }

  private outcomeLabel = (): string => {
    if (this.outcome === 'cancelled') { return '已取消' }
    if (this.outcome === 'interrupted') { return '已中断' }
    if (this.outcome === 'failed') { return '失败' }
    return ''
  }

  @Builder
  NoteReviewBlock(review: NoteReviewAnswer) {
    Column() {
      Row() {
        Text(this.reviewStatusText(review))
          .fontSize(11)
          .fontColor(MINT)
          .fontWeight(W_SEMIBOLD)
        Blank()
        Text(this.reviewReasonText(review))
          .fontSize(10)
          .fontColor(TEXT_3)
          .fontWeight(W_MEDIUM)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')

      if (review.citations.length > 0) {
        ForEach(review.citations, (citation: NoteEvidenceCitation, index: number): void => {
          NoteReviewSourceCard({
            citation: citation,
            index: index,
            onOpen: this.onSourceTap,
          })
            .margin({ top: S_2 })
        }, (citation: NoteEvidenceCitation, index: number): string => citation.noteId + ':' + citation.version.toString() + ':' + index.toString())
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
    .padding({ left: S_3, right: S_3, top: S_2, bottom: S_2 })
    .borderRadius(R_MD)
    .backgroundColor(GLASS_10)
    .border({ width: 0.5, color: BORDER })
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

  private reviewReasonText = (review: NoteReviewAnswer): string => {
    if (review.reason === 'ambiguous-topic') {
      return '请补充具体笔记主题'
    }
    if (review.reason === 'ambiguous-pronoun') {
      return '指代不够明确'
    }
    if (review.reason === 'no-match') {
      return '没有找到足够依据'
    }
    if (review.reason === 'compare-needs-two-topics') {
      return '比较需要两个主题'
    }
    if (review.reason === 'compare-topic-missing') {
      return '比较证据不足'
    }
    if (review.reason === 'no-accepted-prerequisite') {
      return '没有已确认前置关系'
    }
    if (review.reason === 'missing-evidence') {
      return '回答证据丢失'
    }
    if (review.reason === 'model-missing-valid-citation') {
      return '缺少可验证引用'
    }
    if (review.status === 'unavailable') {
      return '检索暂不可用'
    }
    return '请换一个更具体的主题'
  }
}
