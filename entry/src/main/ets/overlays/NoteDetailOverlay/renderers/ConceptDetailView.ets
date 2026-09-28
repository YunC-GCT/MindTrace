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
import { DetailReleaseGate } from '../DetailReleaseGate'
import {
  DetailRenderSession,
  DETAIL_RENDER_PRIORITY_VISIBLE_TEXT,
  DETAIL_RENDER_PRIORITY_VISIBLE_FORMULA,
  DETAIL_RENDER_PRIORITY_NEAR_VIEWPORT,
  DETAIL_RENDER_PRIORITY_OFFSCREEN_TEXT,
  DETAIL_RENDER_PRIORITY_OFFSCREEN_FORMULA,
} from '../components/DetailRenderSession'

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
  @Prop model: DetailRenderModel = emptyDetailRenderModel()
  @Prop renderSession: DetailRenderSession = new DetailRenderSession()

  build() {
    Column() {
      DetailReleaseGate({
        renderSession: this.renderSession,
        releaseKey: this.renderSession.scopeKey('concept|' + conceptModelKey(this.model) + '|definition'),
        releaseContent: sectionTextByKeys(this.model, CONCEPT_DEFINITION_KEYS),
        releasePriority: DETAIL_RENDER_PRIORITY_VISIBLE_TEXT,
        formulaPriority: DETAIL_RENDER_PRIORITY_VISIBLE_FORMULA,
      }) {
        this.DefinitionBlock(sectionTextByKeys(this.model, CONCEPT_DEFINITION_KEYS),
          DETAIL_RENDER_PRIORITY_VISIBLE_FORMULA)
      }

      DetailReleaseGate({
        renderSession: this.renderSession,
        releaseKey: this.renderSession.scopeKey('concept|' + conceptModelKey(this.model) + '|properties'),
        releaseContent: sectionTextByKeys(this.model, CONCEPT_PROPERTIES_KEYS),
        releasePriority: DETAIL_RENDER_PRIORITY_NEAR_VIEWPORT,
        formulaPriority: DETAIL_RENDER_PRIORITY_NEAR_VIEWPORT,
      }) {
        this.PropertiesBlock(sectionTextByKeys(this.model, CONCEPT_PROPERTIES_KEYS),
          DETAIL_RENDER_PRIORITY_NEAR_VIEWPORT)
      }

      DetailReleaseGate({
        renderSession: this.renderSession,
        releaseKey: this.renderSession.scopeKey('concept|' + conceptModelKey(this.model) + '|examples'),
        releaseContent: sectionTextByKeys(this.model, CONCEPT_EXAMPLES_KEYS),
        releasePriority: DETAIL_RENDER_PRIORITY_OFFSCREEN_TEXT,
        formulaPriority: DETAIL_RENDER_PRIORITY_OFFSCREEN_FORMULA,
      }) {
        this.ExamplesBlock(sectionTextByKeys(this.model, CONCEPT_EXAMPLES_KEYS),
          DETAIL_RENDER_PRIORITY_OFFSCREEN_FORMULA)
      }

      DetailReleaseGate({
        renderSession: this.renderSession,
        releaseKey: this.renderSession.scopeKey('concept|' + conceptModelKey(this.model) + '|related'),
        releaseContent: sectionTextByKeys(this.model, CONCEPT_RELATED_KEYS),
        releasePriority: DETAIL_RENDER_PRIORITY_OFFSCREEN_TEXT,
        formulaPriority: DETAIL_RENDER_PRIORITY_OFFSCREEN_FORMULA,
      }) {
        this.RelatedBlock(sectionTextByKeys(this.model, CONCEPT_RELATED_KEYS),
          DETAIL_RENDER_PRIORITY_OFFSCREEN_FORMULA)
      }

      DetailReleaseGate({
        renderSession: this.renderSession,
        releaseKey: this.renderSession.scopeKey('concept|' + conceptModelKey(this.model) + '|supplement'),
        releaseContent: unmatchedSectionText(this.model, CONCEPT_TEMPLATE_KEYS),
        releasePriority: DETAIL_RENDER_PRIORITY_OFFSCREEN_TEXT,
        formulaPriority: DETAIL_RENDER_PRIORITY_OFFSCREEN_FORMULA,
      }) {
        this.SupplementBlock(unmatchedSectionText(this.model, CONCEPT_TEMPLATE_KEYS),
          DETAIL_RENDER_PRIORITY_OFFSCREEN_FORMULA)
      }

      if (!hasAnySectionKey(this.model, CONCEPT_TEMPLATE_KEYS)
        && unmatchedSectionText(this.model, CONCEPT_TEMPLATE_KEYS).length === 0) {
        DetailReleaseGate({
          renderSession: this.renderSession,
          releaseKey: this.renderSession.scopeKey('concept|' + conceptModelKey(this.model) + '|fallback'),
          releaseContent: fallbackMainText(this.model),
          releasePriority: DETAIL_RENDER_PRIORITY_VISIBLE_TEXT,
          formulaPriority: DETAIL_RENDER_PRIORITY_VISIBLE_FORMULA,
        }) {
          this.DefinitionBlock(fallbackMainText(this.model), DETAIL_RENDER_PRIORITY_VISIBLE_FORMULA)
        }
      }

      DetailMetaFooter({ model: this.model, renderSession: this.renderSession })
      Blank().height(80)
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
  DefinitionBlock(content: string, renderPriority: number) {
    if (content.trim().length > 0) {
      Column() {
        this.ConceptLabel(LABEL_DEFINITION, MINT)
        Text(TITLE_DEFINITION)
          .fontSize(F_SM)
          .fontWeight(W_BOLD)
          .fontColor(TEXT)
          .width('100%')
          .margin({ bottom: S_2 })
        MarkdownRenderer({
          text: content,
          progressive: false,
          profile: 'note',
          renderBudget: this.renderSession,
          renderPriority: renderPriority,
        })
      }
      .width('100%')
      .padding({ top: S_3, bottom: S_4 })
      .border({ width: { bottom: 0.5 }, color: BORDER })
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  PropertiesBlock(content: string, renderPriority: number) {
    if (content.trim().length > 0) {
      Column() {
        this.ConceptLabel(LABEL_CHECK, MINT)
        Text(TITLE_PROPERTIES)
          .fontSize(F_SM)
          .fontWeight(W_SEMIBOLD)
          .fontColor(TEXT_2)
          .width('100%')
          .margin({ bottom: S_2 })
        MarkdownRenderer({
          text: content,
          progressive: false,
          profile: 'note',
          renderBudget: this.renderSession,
          renderPriority: renderPriority,
        })
      }
      .width('100%')
      .padding({ top: S_4, bottom: S_3 })
      .border({ width: { bottom: 0.5 }, color: BORDER })
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  ExamplesBlock(content: string, renderPriority: number) {
    if (content.trim().length > 0) {
      Column() {
        this.ConceptLabel(LABEL_EXAMPLE, MINT)
        Text(TITLE_EXAMPLES)
          .fontSize(F_SM)
          .fontWeight(W_SEMIBOLD)
          .fontColor(TEXT_2)
          .width('100%')
          .margin({ bottom: S_2 })
        MarkdownRenderer({
          text: content,
          progressive: false,
          profile: 'note',
          renderBudget: this.renderSession,
          renderPriority: renderPriority,
        })
      }
      .width('100%')
      .padding({ top: S_4, bottom: S_3 })
      .border({ width: { bottom: 0.5 }, color: BORDER })
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  RelatedBlock(content: string, renderPriority: number) {
    if (content.trim().length > 0) {
      Column() {
        this.ConceptLabel(LABEL_LINK, TEXT_3)
        Text(TITLE_RELATED)
          .fontSize(F_SM)
          .fontWeight(W_SEMIBOLD)
          .fontColor(TEXT_2)
          .width('100%')
          .margin({ bottom: S_2 })
        MarkdownRenderer({
          text: content,
          progressive: false,
          profile: 'note',
          renderBudget: this.renderSession,
          renderPriority: renderPriority,
        })
      }
      .width('100%')
      .padding({ top: S_4, bottom: S_3 })
      .border({ width: { bottom: 0.5 }, color: BORDER })
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  SupplementBlock(content: string, renderPriority: number) {
    if (content.trim().length > 0) {
      Column() {
        Text(EXTRA_SECTION_TITLE)
          .fontSize(F_SM)
          .fontWeight(W_SEMIBOLD)
          .fontColor(TEXT_3)
          .width('100%')
          .margin({ bottom: S_2 })
        MarkdownRenderer({
          text: content,
          progressive: false,
          profile: 'note',
          renderBudget: this.renderSession,
          renderPriority: renderPriority,
        })
      }
      .width('100%')
      .padding({ top: S_4, bottom: S_3 })
      .border({ width: { bottom: 0.5 }, color: BORDER })
      .alignItems(HorizontalAlign.Start)
    }
  }

}
