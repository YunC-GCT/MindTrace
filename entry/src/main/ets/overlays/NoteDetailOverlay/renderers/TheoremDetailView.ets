/**
 * TheoremDetailView.ets - theorem-specific note detail renderer
 *
 * Path: entry/src/main/ets/overlays/NoteDetailOverlay/renderers/TheoremDetailView.ets
 * Responsibility: Render theorem notes around statement, conclusion, conditions,
 * proof insight, and applications.
 * Dependencies: DetailRenderModel, MarkdownRenderer, DetailMetaFooter.
 *
 * ArkTS 1.1 strict:
 *   - Explicit typed values throughout
 *   - No C-style for loops
 *   - Struct helper logic uses arrow fields or @Builder
 */

import {
  PURPLE, TEXT, TEXT_2, TEXT_3, BORDER,
  S_1, S_2, S_3, S_4,
  F_XS, F_SM,
  W_BOLD, W_SEMIBOLD,
} from 'common'
import {
  DetailRenderModel,
  emptyDetailRenderModel,
  sectionTextByKeys,
  fallbackMainText,
  hasAnySectionKey,
  unmatchedSectionText,
  EXTRA_SECTION_TITLE,
} from '../model/DetailRenderModel'
import { MarkdownRenderer } from '../../../shared/molecules/MarkdownRenderer'
import { DetailMetaFooter } from '../components/DetailMetaFooter'

const TITLE_STATEMENT: string = '\u5148\u8bfb\uff1a\u5b9a\u7406\u9648\u8ff0'
const TITLE_CONDITION: string = '\u5148\u6838\u5bf9\uff1a\u6761\u4ef6'
const TITLE_CONCLUSION: string = '\u8981\u8bb0\u4f4f\uff1a\u7ed3\u8bba'
const TITLE_INSIGHT: string = '\u7406\u89e3\uff1a\u8bc1\u660e\u601d\u8def'
const TITLE_APPLICATIONS: string = '\u5e94\u7528'
const LABEL_STATEMENT: string = '\u5b9a\u7406'
const LABEL_CONCLUSION: string = '\u7ed3\u8bba'
const LABEL_CONDITION: string = '\u6761\u4ef6'
const LABEL_REASON: string = '\u7406\u89e3'
const LABEL_APPLY: string = '\u5e94\u7528'

const THEOREM_STATEMENT_KEYS: string[] = ['statement', '\u9648\u8ff0', '\u5b9a\u7406\u9648\u8ff0', '\u5185\u5bb9', 'content']
const THEOREM_CONDITION_KEYS: string[] = ['range', '\u6761\u4ef6', '\u9002\u7528\u8303\u56f4']
const THEOREM_CONCLUSION_KEYS: string[] = ['conclusion', '\u7ed3\u8bba']
const THEOREM_INSIGHT_KEYS: string[] = ['insight', '\u8bc1\u660e\u601d\u8def', '\u601d\u8def', '\u5173\u952e\u601d\u8def']
const THEOREM_APPLICATION_KEYS: string[] = ['applications', '\u5e94\u7528']
const THEOREM_TEMPLATE_KEYS: string[] = [
  'statement', '\u9648\u8ff0', '\u5b9a\u7406\u9648\u8ff0', '\u5185\u5bb9', 'content',
  'range', '\u6761\u4ef6', '\u9002\u7528\u8303\u56f4',
  'conclusion', '\u7ed3\u8bba',
  'insight', '\u8bc1\u660e\u601d\u8def', '\u601d\u8def', '\u5173\u952e\u601d\u8def',
  'applications', '\u5e94\u7528',
]

function theoremTextHash(text: string): string {
  let hash: number = 5381
  let index: number = 0
  while (index < text.length) {
    hash = ((hash << 5) + hash + text.charCodeAt(index)) | 0
    index += 1
  }
  const positive: number = hash < 0 ? -hash : hash
  return text.length.toString() + ':' + positive.toString()
}

function theoremModelKey(model: DetailRenderModel): string {
  return model.category + '|' + theoremTextHash(model.summary) + '|' + theoremTextHash(model.body)
}

@Component
export struct TheoremDetailView {
  @Prop @Watch('onModelChanged') model: DetailRenderModel = emptyDetailRenderModel()
  @State visibleStage: number = 0
  private renderKey: string = ''
  private renderSeq: number = 0

  aboutToAppear(): void {
    this.resetTheoremFlow()
  }

  aboutToDisappear(): void {
    this.renderSeq += 1
  }

  onModelChanged(): void {
    this.resetTheoremFlow()
  }

  build() {
    Column() {
      this.StatementBlock(sectionTextByKeys(this.model, THEOREM_STATEMENT_KEYS))
      this.ConclusionBlock(sectionTextByKeys(this.model, THEOREM_CONCLUSION_KEYS))

      if (this.visibleStage >= 1) {
        this.ConditionBlock(sectionTextByKeys(this.model, THEOREM_CONDITION_KEYS))
      }

      if (this.visibleStage >= 2) {
        this.InsightBlock(sectionTextByKeys(this.model, THEOREM_INSIGHT_KEYS))
      }

      if (this.visibleStage >= 3) {
        this.ApplicationBlock(sectionTextByKeys(this.model, THEOREM_APPLICATION_KEYS))
        this.SupplementBlock(unmatchedSectionText(this.model, THEOREM_TEMPLATE_KEYS))
      }

      if (!hasAnySectionKey(this.model, THEOREM_TEMPLATE_KEYS)
        && unmatchedSectionText(this.model, THEOREM_TEMPLATE_KEYS).length === 0) {
        this.StatementBlock(fallbackMainText(this.model))
      }

      if (this.visibleStage >= 3) {
        DetailMetaFooter({ model: this.model })
        Blank().height(80)
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: S_2, bottom: S_2 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  Tag(label: string, color: ResourceColor) {
    Text(label)
      .fontSize(F_XS)
      .fontWeight(W_BOLD)
      .fontColor(color)
      .letterSpacing(0)
      .padding({ left: S_2, right: S_2, top: S_1, bottom: S_1 })
      .border({ width: 0.5, color: BORDER })
      .borderRadius(6)
      .margin({ bottom: S_2 })
  }

  @Builder
  StatementBlock(content: string) {
    if (content.trim().length > 0) {
      Column() {
        this.Tag(LABEL_STATEMENT, PURPLE)
        Text(TITLE_STATEMENT)
          .fontSize(F_SM)
          .fontWeight(W_BOLD)
          .fontColor(TEXT)
          .width('100%')
          .margin({ bottom: S_2 })
        MarkdownRenderer({ text: content, progressive: true })
      }
      .width('100%')
      .padding({ top: S_3, bottom: S_4 })
      .border({ width: { bottom: 0.5 }, color: BORDER })
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  ConclusionBlock(content: string) {
    if (content.trim().length > 0) {
      Column() {
        this.Tag(LABEL_CONCLUSION, PURPLE)
        Text(TITLE_CONCLUSION)
          .fontSize(F_SM)
          .fontWeight(W_BOLD)
          .fontColor(TEXT)
          .width('100%')
          .margin({ bottom: S_2 })
        MarkdownRenderer({ text: content, progressive: true })
      }
      .width('100%')
      .padding({ top: S_3, bottom: S_4 })
      .border({ width: { bottom: 0.5 }, color: BORDER })
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  ConditionBlock(content: string) {
    if (content.trim().length > 0) {
      Column() {
        this.Tag(LABEL_CONDITION, PURPLE)
        Text(TITLE_CONDITION)
          .fontSize(F_SM)
          .fontWeight(W_SEMIBOLD)
          .fontColor(TEXT_2)
          .width('100%')
          .margin({ bottom: S_2 })
        MarkdownRenderer({ text: content, progressive: true })
      }
      .width('100%')
      .padding({ top: S_4, bottom: S_3 })
      .border({ width: { bottom: 0.5 }, color: BORDER })
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  InsightBlock(content: string) {
    if (content.trim().length > 0) {
      Column() {
        this.Tag(LABEL_REASON, TEXT_3)
        Text(TITLE_INSIGHT)
          .fontSize(F_SM)
          .fontWeight(W_SEMIBOLD)
          .fontColor(TEXT_2)
          .width('100%')
          .margin({ bottom: S_2 })
        MarkdownRenderer({ text: content, progressive: true })
      }
      .width('100%')
      .padding({ top: S_4, bottom: S_3 })
      .border({ width: { bottom: 0.5 }, color: BORDER })
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  ApplicationBlock(content: string) {
    if (content.trim().length > 0) {
      Column() {
        this.Tag(LABEL_APPLY, TEXT_3)
        Text(TITLE_APPLICATIONS)
          .fontSize(F_SM)
          .fontWeight(W_SEMIBOLD)
          .fontColor(TEXT_2)
          .width('100%')
          .margin({ bottom: S_2 })
        MarkdownRenderer({ text: content, progressive: true })
      }
      .width('100%')
      .padding({ top: S_4, bottom: S_3 })
      .border({ width: { bottom: 0.5 }, color: BORDER })
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  SupplementBlock(content: string) {
    if (content.trim().length > 0) {
      Column() {
        Text(EXTRA_SECTION_TITLE)
          .fontSize(F_SM)
          .fontWeight(W_SEMIBOLD)
          .fontColor(TEXT_3)
          .width('100%')
          .margin({ bottom: S_2 })
        MarkdownRenderer({ text: content, progressive: true })
      }
      .width('100%')
      .padding({ top: S_4, bottom: S_3 })
      .border({ width: { bottom: 0.5 }, color: BORDER })
      .alignItems(HorizontalAlign.Start)
    }
  }

  private resetTheoremFlow = (): void => {
    const key: string = theoremModelKey(this.model)
    if (key === this.renderKey) {
      return
    }
    this.renderKey = key
    this.renderSeq += 1
    const seq: number = this.renderSeq
    this.visibleStage = 0
    this.scheduleTheoremStage(seq, 1, 60)
    this.scheduleTheoremStage(seq, 2, 140)
    this.scheduleTheoremStage(seq, 3, 240)
  }

  private scheduleTheoremStage = (seq: number, stage: number, delay: number): void => {
    setTimeout((): void => {
      if (seq !== this.renderSeq) {
        return
      }
      if (this.visibleStage < stage) {
        this.visibleStage = stage
      }
    }, delay)
  }
}
