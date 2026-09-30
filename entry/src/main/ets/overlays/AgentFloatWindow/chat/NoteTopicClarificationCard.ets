/**
 * NoteTopicClarificationCard.ets - single-choice note topic clarification card.
 *
 * Path: entry/src/main/ets/overlays/AgentFloatWindow/chat/NoteTopicClarificationCard.ets
 * Responsibility: Render persisted note-topic candidates and emit idempotent selection callbacks.
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
import type { NoteContextClarification, NoteTopicCandidate } from 'common'

@Component
export struct NoteTopicClarificationCard {
  @Prop clarification: NoteContextClarification | null = null
  onSelect: (runId: string, topicId: string) => void = (_runId: string, _topicId: string): void => {}

  build() {
    if (this.clarification !== null) {
      Column() {
        Text(this.titleText(this.clarification))
          .fontSize(12)
          .fontColor(TEXT)
          .fontWeight(W_SEMIBOLD)
        Text(this.statusText(this.clarification))
          .fontSize(10)
          .fontColor(TEXT_3)
          .fontWeight(W_MEDIUM)
          .margin({ top: S_1, bottom: S_1 })

        ForEach(this.clarification.candidates, (candidate: NoteTopicCandidate): void => {
          this.TopicButton(candidate, this.clarification!)
        }, (candidate: NoteTopicCandidate): string => candidate.id)
      }
      .width('94%')
      .padding({ left: S_3, right: S_3, top: S_2, bottom: S_2 })
      .borderRadius(R_MD)
      .backgroundColor(GLASS_10)
      .border({ width: 0.5, color: BORDER })
      .margin({ top: S_2, left: S_3 })
    }
  }

  @Builder
  TopicButton(candidate: NoteTopicCandidate, clarification: NoteContextClarification) {
    Row() {
      Text(candidate.displayName)
        .fontSize(12)
        .fontColor(this.isSelected(candidate, clarification) ? MINT : TEXT_2)
        .fontWeight(W_SEMIBOLD)
        .layoutWeight(1)
      Text(this.confidenceText(candidate))
        .fontSize(10)
        .fontColor(TEXT_3)
    }
    .width('100%')
    .padding({ left: S_2, right: S_2, top: S_2, bottom: S_2 })
    .borderRadius(R_MD)
    .backgroundColor(this.isSelected(candidate, clarification) ? 'rgba(91,227,176,0.14)' : 'rgba(255,255,255,0.04)')
    .border({ width: 0.5, color: this.isSelected(candidate, clarification) ? MINT : BORDER })
    .margin({ top: S_1 })
    .enabled(clarification.status === 'pending')
    .onClick((): void => {
      if (clarification.status === 'pending') {
        this.onSelect(clarification.runId, candidate.id)
      }
    })
  }

  private isSelected = (candidate: NoteTopicCandidate, clarification: NoteContextClarification): boolean => {
    return clarification.selectedTopicId === candidate.id
  }

  private confidenceText = (candidate: NoteTopicCandidate): string => {
    return Math.round(candidate.confidence * 100).toString() + '%'
  }

  private statusText = (clarification: NoteContextClarification): string => {
    if (clarification.status === 'selected') { return '已选择，正在生成单主题笔记' }
    if (clarification.status === 'cancelled') { return '该选择已取消' }
    if (clarification.candidates.length === 0) { return '请在输入框中填写一个具体数学主题' }
    return '检测到多个主题，本次只会生成你选择的一个主题'
  }

  private titleText = (clarification: NoteContextClarification): string => {
    return clarification.candidates.length === 0
      ? '请补充具体数学主题'
      : '请选择要整理的数学主题'
  }
}
