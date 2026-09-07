/**
 * ProofDetailView.ets - proof-specific note detail renderer
 *
 * Path: entry/src/main/ets/overlays/NoteDetailOverlay/renderers/ProofDetailView.ets
 * Responsibility: Render proof notes as proposition, insight, proof path, and
 * conclusion before auxiliary conditions.
 * Dependencies: DetailRenderModel, MarkdownRenderer, DetailStepList, DetailMetaFooter.
 *
 * ArkTS 1.1 strict:
 *   - Explicit typed values throughout
 *   - No C-style for loops
 *   - Struct helper logic uses arrow fields or @Builder
 */

import {
  AMBER, TEXT, TEXT_2, TEXT_3, BORDER,
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
  splitReadableLines,
  EXTRA_SECTION_TITLE,
} from '../model/DetailRenderModel'
import { MarkdownRenderer } from '../../../shared/molecules/MarkdownRenderer'
import { DetailStepList } from '../components/DetailStepList'
import { DetailMetaFooter } from '../components/DetailMetaFooter'

const TITLE_PROPOSITION: string = '\u5148\u8bfb\uff1a\u547d\u9898'
const TITLE_INSIGHT: string = '\u6293\u4f4f\uff1a\u5173\u952e\u601d\u8def'
const TITLE_GIVEN: string = '\u8f85\u52a9\uff1a\u5df2\u77e5\u6761\u4ef6'
const TITLE_PROCESS: string = '\u5c55\u5f00\uff1a\u8bc1\u660e\u8fc7\u7a0b'
const TITLE_CONCLUSION: string = '\u6536\u675f\uff1a\u7ed3\u8bba'
const LABEL_PROPOSITION: string = '\u547d\u9898'
const LABEL_INSIGHT: string = '\u601d\u8def'
const LABEL_PROCESS: string = '\u8fc7\u7a0b'
const LABEL_CONCLUSION: string = '\u7ed3\u8bba'
const LABEL_GIVEN: string = '\u5df2\u77e5'

const PROOF_PROPOSITION_KEYS: string[] = ['proposition', 'problem', '\u547d\u9898', '\u9898\u76ee', '\u95ee\u9898', '\u5185\u5bb9', 'content']
const PROOF_INSIGHT_KEYS: string[] = ['insight', '\u5173\u952e\u601d\u8def', '\u8bc1\u660e\u601d\u8def', '\u601d\u8def']
const PROOF_GIVEN_KEYS: string[] = ['given', 'range', '\u5df2\u77e5', '\u6761\u4ef6']
const PROOF_PROCESS_KEYS: string[] = ['proofprocess', 'steps', '\u8bc1\u660e\u8fc7\u7a0b', '\u8fc7\u7a0b', '\u6b65\u9aa4']
const PROOF_CONCLUSION_KEYS: string[] = ['conclusion', '\u7ed3\u8bba']
const PROOF_TEMPLATE_KEYS: string[] = [
  'proposition', 'problem', '\u547d\u9898', '\u9898\u76ee', '\u95ee\u9898', '\u5185\u5bb9', 'content',
  'insight', '\u5173\u952e\u601d\u8def', '\u8bc1\u660e\u601d\u8def', '\u601d\u8def',
  'given', 'range', '\u5df2\u77e5', '\u6761\u4ef6',
  'proofprocess', 'steps', '\u8bc1\u660e\u8fc7\u7a0b', '\u8fc7\u7a0b', '\u6b65\u9aa4',
  'conclusion', '\u7ed3\u8bba',
]

function proofTextHash(text: string): string {
  let hash: number = 5381
  let index: number = 0
  while (index < text.length) {
    hash = ((hash << 5) + hash + text.charCodeAt(index)) | 0
    index += 1
  }
  const positive: number = hash < 0 ? -hash : hash
  return text.length.toString() + ':' + positive.toString()
}

function proofModelKey(model: DetailRenderModel): string {
  return model.category + '|' + proofTextHash(model.summary) + '|' + proofTextHash(model.body)
}

@Component
export struct ProofDetailView {
  @Prop @Watch('onModelChanged') model: DetailRenderModel = emptyDetailRenderModel()
  @State visibleStage: number = 0
  private renderKey: string = ''
  private renderSeq: number = 0

  aboutToAppear(): void {
    this.resetProofFlow()
  }

  aboutToDisappear(): void {
    this.renderSeq += 1
  }

  onModelChanged(): void {
    this.resetProofFlow()
  }

  build() {
    Column() {
      this.PropositionBlock(sectionTextByKeys(this.model, PROOF_PROPOSITION_KEYS))
      this.InsightBlock(sectionTextByKeys(this.model, PROOF_INSIGHT_KEYS))
      this.ProcessBlock(splitReadableLines(sectionTextByKeys(this.model, PROOF_PROCESS_KEYS)))
      this.ConclusionBlock(sectionTextByKeys(this.model, PROOF_CONCLUSION_KEYS))

      if (this.visibleStage >= 1) {
        this.GivenBlock(sectionTextByKeys(this.model, PROOF_GIVEN_KEYS))
      }

      if (this.visibleStage >= 2) {
        this.SupplementBlock(unmatchedSectionText(this.model, PROOF_TEMPLATE_KEYS))
      }

      if (!hasAnySectionKey(this.model, PROOF_TEMPLATE_KEYS)
        && unmatchedSectionText(this.model, PROOF_TEMPLATE_KEYS).length === 0) {
        this.PropositionBlock(fallbackMainText(this.model))
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
  ProofTag(label: string, color: ResourceColor) {
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
  PropositionBlock(content: string) {
    if (content.trim().length > 0) {
      Column() {
        this.ProofTag(LABEL_PROPOSITION, AMBER)
        Text(TITLE_PROPOSITION)
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
  InsightBlock(content: string) {
    if (content.trim().length > 0) {
      Column() {
        this.ProofTag(LABEL_INSIGHT, AMBER)
        Text(TITLE_INSIGHT)
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
  ProcessBlock(items: string[]) {
    if (items.length > 0) {
      Column() {
        this.ProofTag(LABEL_PROCESS, AMBER)
        Text(TITLE_PROCESS)
          .fontSize(F_SM)
          .fontWeight(W_BOLD)
          .fontColor(TEXT)
          .width('100%')
          .margin({ bottom: S_2 })
        DetailStepList({ items: items, accentColor: AMBER })
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
        this.ProofTag(LABEL_CONCLUSION, AMBER)
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
  GivenBlock(content: string) {
    if (content.trim().length > 0) {
      Column() {
        this.ProofTag(LABEL_GIVEN, TEXT_3)
        Text(TITLE_GIVEN)
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

  private resetProofFlow = (): void => {
    const key: string = proofModelKey(this.model)
    if (key === this.renderKey) {
      return
    }
    this.renderKey = key
    this.renderSeq += 1
    const seq: number = this.renderSeq
    this.visibleStage = 0
    this.scheduleProofStage(seq, 1, 90)
    this.scheduleProofStage(seq, 2, 190)
    this.scheduleProofStage(seq, 3, 290)
  }

  private scheduleProofStage = (seq: number, stage: number, delay: number): void => {
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
