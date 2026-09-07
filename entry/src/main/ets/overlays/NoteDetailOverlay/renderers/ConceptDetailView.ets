/**
 * ConceptDetailView.ets - concept-specific note detail renderer
 *
 * Path: entry/src/main/ets/overlays/NoteDetailOverlay/renderers/ConceptDetailView.ets
 * Responsibility: Render concept notes as definition-first reading content.
 * Dependencies: DetailRenderModel, MarkdownRenderer, DetailMetaFooter.
 *
 * Data flow:
 *   DetailRenderModel -> ConceptDetailView -> concept reading blocks
 *
 * ArkTS 1.1 strict:
 *   - Explicit typed values throughout
 *   - Uses while / for...of only
 *   - Struct helper logic uses arrow fields or @Builder
 */

import {
  MINT, TEXT, TEXT_2, TEXT_3, BORDER,
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

const TITLE_DEFINITION: string = '\u5148\u8bfb\uff1a\u5b9a\u4e49\u8fb9\u754c'
const TITLE_PROPERTIES: string = '\u518d\u770b\uff1a\u5224\u65ad\u6027\u8d28'
const TITLE_EXAMPLES: string = '\u6700\u540e\uff1a\u4f8b\u5b50\u548c\u53cd\u4f8b'
const TITLE_RELATED: string = '\u5173\u8054\u6982\u5ff5'
const LABEL_DEFINITION: string = '\u5b9a\u4e49'
const LABEL_CHECK: string = '\u5224\u65ad'
const LABEL_EXAMPLE: string = '\u4f8b\u5b50'
const LABEL_LINK: string = '\u5173\u8054'

const CONCEPT_DEFINITION_KEYS: string[] = ['definition', '\u5b9a\u4e49', '\u5185\u5bb9', 'content']
const CONCEPT_PROPERTIES_KEYS: string[] = ['properties', '\u6027\u8d28', '\u7279\u5f81']
const CONCEPT_EXAMPLES_KEYS: string[] = ['examples', '\u793a\u4f8b', '\u4f8b\u5b50', '\u53cd\u4f8b']
const CONCEPT_RELATED_KEYS: string[] = ['relatedconcepts', '\u76f8\u5173\u6982\u5ff5']
const CONCEPT_TEMPLATE_KEYS: string[] = [
  'definition', '\u5b9a\u4e49', '\u5185\u5bb9', 'content',
  'properties', '\u6027\u8d28', '\u7279\u5f81',
  'examples', '\u793a\u4f8b', '\u4f8b\u5b50', '\u53cd\u4f8b',
  'relatedconcepts', '\u76f8\u5173\u6982\u5ff5',
]

function conceptTextHash(text: string): string {
  let hash: number = 5381
  let index: number = 0
  while (index < text.length) {
    hash = ((hash << 5) + hash + text.charCodeAt(index)) | 0
    index += 1
  }
  const positive: number = hash < 0 ? -hash : hash
  return text.length.toString() + ':' + positive.toString()
}

function conceptModelKey(model: DetailRenderModel): string {
  return model.category + '|' + conceptTextHash(model.summary) + '|' + conceptTextHash(model.body)
}

@Component
export struct ConceptDetailView {
  @Prop @Watch('onModelChanged') model: DetailRenderModel = emptyDetailRenderModel()
  @State visibleStage: number = 0
  private renderKey: string = ''
  private renderSeq: number = 0

  aboutToAppear(): void {
    this.resetConceptFlow()
  }

  aboutToDisappear(): void {
    this.renderSeq += 1
  }

  onModelChanged(): void {
    this.resetConceptFlow()
  }

  build() {
    Column() {
      this.DefinitionBlock(sectionTextByKeys(this.model, CONCEPT_DEFINITION_KEYS))

      if (this.visibleStage >= 1) {
        this.PropertiesBlock(sectionTextByKeys(this.model, CONCEPT_PROPERTIES_KEYS))
      }

      if (this.visibleStage >= 2) {
        this.ExamplesBlock(sectionTextByKeys(this.model, CONCEPT_EXAMPLES_KEYS))
      }

      if (this.visibleStage >= 3) {
        this.RelatedBlock(sectionTextByKeys(this.model, CONCEPT_RELATED_KEYS))
        this.SupplementBlock(unmatchedSectionText(this.model, CONCEPT_TEMPLATE_KEYS))
      }

      if (!hasAnySectionKey(this.model, CONCEPT_TEMPLATE_KEYS)
        && unmatchedSectionText(this.model, CONCEPT_TEMPLATE_KEYS).length === 0) {
        this.DefinitionBlock(fallbackMainText(this.model))
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
  ConceptLabel(text: string, color: ResourceColor) {
    Text(text)
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
  DefinitionBlock(content: string) {
    if (content.trim().length > 0) {
      Column() {
        this.ConceptLabel(LABEL_DEFINITION, MINT)
        Text(TITLE_DEFINITION)
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
  PropertiesBlock(content: string) {
    if (content.trim().length > 0) {
      Column() {
        this.ConceptLabel(LABEL_CHECK, MINT)
        Text(TITLE_PROPERTIES)
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
  ExamplesBlock(content: string) {
    if (content.trim().length > 0) {
      Column() {
        this.ConceptLabel(LABEL_EXAMPLE, MINT)
        Text(TITLE_EXAMPLES)
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
  RelatedBlock(content: string) {
    if (content.trim().length > 0) {
      Column() {
        this.ConceptLabel(LABEL_LINK, TEXT_3)
        Text(TITLE_RELATED)
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

  private resetConceptFlow = (): void => {
    const key: string = conceptModelKey(this.model)
    if (key === this.renderKey) {
      return
    }
    this.renderKey = key
    this.renderSeq += 1
    const seq: number = this.renderSeq
    this.visibleStage = 0
    this.scheduleConceptStage(seq, 1, 48)
    this.scheduleConceptStage(seq, 2, 120)
    this.scheduleConceptStage(seq, 3, 220)
  }

  private scheduleConceptStage = (seq: number, stage: number, delay: number): void => {
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
