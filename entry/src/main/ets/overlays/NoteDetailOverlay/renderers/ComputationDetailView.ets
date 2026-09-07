/**
 * ComputationDetailView.ets - computation-specific note detail renderer
 *
 * Path: entry/src/main/ets/overlays/NoteDetailOverlay/renderers/ComputationDetailView.ets
 * Responsibility: Render computation notes as problem, steps, answer, method,
 * and mistakes in a calculation-first flow.
 * Dependencies: DetailRenderModel, MarkdownRenderer, DetailStepList, DetailMetaFooter.
 *
 * ArkTS 1.1 strict:
 *   - Explicit typed values throughout
 *   - No C-style for loops
 *   - Struct helper logic uses arrow fields or @Builder
 */

import {
  TEXT, TEXT_2, TEXT_3, BORDER,
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

const COMPUTE_ACCENT: string = '#FF64B7C8'
const TITLE_PROBLEM: string = '\u5148\u770b\uff1a\u95ee\u9898'
const TITLE_STEPS: string = '\u5c55\u5f00\uff1a\u6b65\u9aa4'
const TITLE_ANSWER: string = '\u6838\u5bf9\uff1a\u7b54\u6848'
const TITLE_METHOD: string = '\u5e26\u8d70\uff1a\u65b9\u6cd5\u603b\u7ed3'
const TITLE_NOTES: string = '\u6700\u540e\u68c0\u67e5\uff1a\u5e38\u89c1\u9519\u8bef'
const LABEL_PROBLEM: string = '\u9898\u76ee'
const LABEL_STEPS: string = '\u6b65\u9aa4'
const LABEL_ANSWER: string = '\u7b54\u6848'
const LABEL_METHOD: string = '\u65b9\u6cd5'
const LABEL_MISTAKE: string = '\u9519\u8bef'

const COMPUTE_PROBLEM_KEYS: string[] = ['problem', '\u95ee\u9898', '\u9898\u76ee', '\u5185\u5bb9', 'content']
const COMPUTE_STEPS_KEYS: string[] = ['steps', '\u6b65\u9aa4', '\u89e3\u9898\u6b65\u9aa4']
const COMPUTE_ANSWER_KEYS: string[] = ['answer', '\u7b54\u6848', '\u7ed3\u679c']
const COMPUTE_METHOD_KEYS: string[] = ['methodsummary', '\u65b9\u6cd5\u603b\u7ed3']
const COMPUTE_NOTES_KEYS: string[] = ['notes', '\u5e38\u89c1\u9519\u8bef', '\u6613\u9519\u70b9', '\u5907\u6ce8']
const COMPUTE_TEMPLATE_KEYS: string[] = [
  'problem', '\u95ee\u9898', '\u9898\u76ee', '\u5185\u5bb9', 'content',
  'steps', '\u6b65\u9aa4', '\u89e3\u9898\u6b65\u9aa4',
  'answer', '\u7b54\u6848', '\u7ed3\u679c',
  'methodsummary', '\u65b9\u6cd5\u603b\u7ed3',
  'notes', '\u5e38\u89c1\u9519\u8bef', '\u6613\u9519\u70b9', '\u5907\u6ce8',
]

function computationTextHash(text: string): string {
  let hash: number = 5381
  let index: number = 0
  while (index < text.length) {
    hash = ((hash << 5) + hash + text.charCodeAt(index)) | 0
    index += 1
  }
  const positive: number = hash < 0 ? -hash : hash
  return text.length.toString() + ':' + positive.toString()
}

function computationModelKey(model: DetailRenderModel): string {
  return model.category + '|' + computationTextHash(model.summary) + '|' + computationTextHash(model.body)
}

@Component
export struct ComputationDetailView {
  @Prop @Watch('onModelChanged') model: DetailRenderModel = emptyDetailRenderModel()
  @State visibleStage: number = 0
  private renderKey: string = ''
  private renderSeq: number = 0

  aboutToAppear(): void {
    this.resetComputationFlow()
  }

  aboutToDisappear(): void {
    this.renderSeq += 1
  }

  onModelChanged(): void {
    this.resetComputationFlow()
  }

  build() {
    Column() {
      this.ProblemBlock(sectionTextByKeys(this.model, COMPUTE_PROBLEM_KEYS))
      this.StepsBlock(splitReadableLines(sectionTextByKeys(this.model, COMPUTE_STEPS_KEYS)))
      this.AnswerBlock(sectionTextByKeys(this.model, COMPUTE_ANSWER_KEYS))

      if (this.visibleStage >= 1) {
        this.MethodBlock(sectionTextByKeys(this.model, COMPUTE_METHOD_KEYS))
      }

      if (this.visibleStage >= 2) {
        this.NotesBlock(sectionTextByKeys(this.model, COMPUTE_NOTES_KEYS))
      }

      if (this.visibleStage >= 3) {
        this.SupplementBlock(unmatchedSectionText(this.model, COMPUTE_TEMPLATE_KEYS))
      }

      if (!hasAnySectionKey(this.model, COMPUTE_TEMPLATE_KEYS)
        && unmatchedSectionText(this.model, COMPUTE_TEMPLATE_KEYS).length === 0) {
        this.ProblemBlock(fallbackMainText(this.model))
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
  ComputeTag(label: string, color: ResourceColor) {
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
  ProblemBlock(content: string) {
    if (content.trim().length > 0) {
      Column() {
        this.ComputeTag(LABEL_PROBLEM, COMPUTE_ACCENT)
        Text(TITLE_PROBLEM)
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
  StepsBlock(items: string[]) {
    if (items.length > 0) {
      Column() {
        this.ComputeTag(LABEL_STEPS, COMPUTE_ACCENT)
        Text(TITLE_STEPS)
          .fontSize(F_SM)
          .fontWeight(W_BOLD)
          .fontColor(TEXT)
          .width('100%')
          .margin({ bottom: S_2 })
        DetailStepList({ items: items, accentColor: COMPUTE_ACCENT })
      }
      .width('100%')
      .padding({ top: S_3, bottom: S_4 })
      .border({ width: { bottom: 0.5 }, color: BORDER })
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  AnswerBlock(content: string) {
    if (content.trim().length > 0) {
      Column() {
        this.ComputeTag(LABEL_ANSWER, COMPUTE_ACCENT)
        Text(TITLE_ANSWER)
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
  MethodBlock(content: string) {
    if (content.trim().length > 0) {
      Column() {
        this.ComputeTag(LABEL_METHOD, TEXT_3)
        Text(TITLE_METHOD)
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
  NotesBlock(content: string) {
    if (content.trim().length > 0) {
      Column() {
        this.ComputeTag(LABEL_MISTAKE, TEXT_3)
        Text(TITLE_NOTES)
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

  private resetComputationFlow = (): void => {
    const key: string = computationModelKey(this.model)
    if (key === this.renderKey) {
      return
    }
    this.renderKey = key
    this.renderSeq += 1
    const seq: number = this.renderSeq
    this.visibleStage = 0
    this.scheduleComputationStage(seq, 1, 90)
    this.scheduleComputationStage(seq, 2, 180)
    this.scheduleComputationStage(seq, 3, 280)
  }

  private scheduleComputationStage = (seq: number, stage: number, delay: number): void => {
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
