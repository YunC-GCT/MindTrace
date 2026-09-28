/**
 * FormulaDetailView.ets - formula-specific note detail renderer
 *
 * Path: entry/src/main/ets/overlays/NoteDetailOverlay/renderers/FormulaDetailView.ets
 * Responsibility: Render formula notes around expression, variables, scope,
 * derivation, and caveats.
 * Dependencies: DetailRenderModel, MarkdownRenderer, DetailMetaFooter.
 *
 * ArkTS 1.1 strict:
 *   - Explicit typed values throughout
 *   - No C-style for loops
 *   - Struct helper logic uses arrow fields or @Builder
 */

import {
  PINK, TEXT, TEXT_2, TEXT_3, BORDER,
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

const TITLE_EXPRESSION: string = '\u5148\u8bb0\u4f4f\uff1a\u6838\u5fc3\u516c\u5f0f'
const TITLE_PARAMETERS: string = '\u518d\u786e\u8ba4\uff1a\u53c2\u6570'
const TITLE_RANGE: string = '\u9002\u7528\u8303\u56f4'
const TITLE_DERIVATION: string = '\u7406\u89e3\uff1a\u63a8\u5bfc'
const TITLE_NOTES: string = '\u6700\u540e\u68c0\u67e5\uff1a\u6613\u9519\u70b9'
const LABEL_FORMULA: string = '\u516c\u5f0f'
const LABEL_SYMBOL: string = '\u7b26\u53f7'
const LABEL_RANGE: string = '\u6761\u4ef6'
const LABEL_DERIVE: string = '\u63a8\u5bfc'
const LABEL_WARN: string = '\u6613\u9519'

const FORMULA_EXPRESSION_KEYS: string[] = ['expression', '\u8868\u8fbe\u5f0f', '\u6838\u5fc3\u516c\u5f0f', '\u516c\u5f0f', '\u5185\u5bb9', 'content']
const FORMULA_PARAMETER_KEYS: string[] = ['parameters', '\u53c2\u6570', '\u53d8\u91cf', '\u7b26\u53f7\u8bf4\u660e', '\u53c2\u6570\u8bf4\u660e']
const FORMULA_RANGE_KEYS: string[] = ['range', '\u9002\u7528\u8303\u56f4', '\u6761\u4ef6', '\u4f7f\u7528\u6761\u4ef6']
const FORMULA_DERIVATION_KEYS: string[] = ['derivation', '\u63a8\u5bfc', '\u63a8\u5bfc\u8fc7\u7a0b']
const FORMULA_NOTES_KEYS: string[] = ['notes', '\u5907\u6ce8', '\u6613\u9519\u70b9', '\u5e38\u89c1\u9519\u8bef']
const FORMULA_TEMPLATE_KEYS: string[] = [
  'expression', '\u8868\u8fbe\u5f0f', '\u6838\u5fc3\u516c\u5f0f', '\u516c\u5f0f', '\u5185\u5bb9', 'content',
  'parameters', '\u53c2\u6570', '\u53d8\u91cf', '\u7b26\u53f7\u8bf4\u660e', '\u53c2\u6570\u8bf4\u660e',
  'range', '\u9002\u7528\u8303\u56f4', '\u6761\u4ef6', '\u4f7f\u7528\u6761\u4ef6',
  'derivation', '\u63a8\u5bfc', '\u63a8\u5bfc\u8fc7\u7a0b',
  'notes', '\u5907\u6ce8', '\u6613\u9519\u70b9', '\u5e38\u89c1\u9519\u8bef',
]

function formulaTextHash(text: string): string {
  let hash: number = 5381
  let index: number = 0
  while (index < text.length) {
    hash = ((hash << 5) + hash + text.charCodeAt(index)) | 0
    index += 1
  }
  const positive: number = hash < 0 ? -hash : hash
  return text.length.toString() + ':' + positive.toString()
}

function formulaModelKey(model: DetailRenderModel): string {
  return model.category + '|' + formulaTextHash(model.summary) + '|' + formulaTextHash(model.body)
}

@Component
export struct FormulaDetailView {
  @Prop model: DetailRenderModel = emptyDetailRenderModel()
  @Prop renderSession: DetailRenderSession = new DetailRenderSession()

  build() {
    Column() {
      DetailReleaseGate({
        renderSession: this.renderSession,
        releaseKey: this.renderSession.scopeKey('formula|' + formulaModelKey(this.model) + '|expression'),
        releaseContent: sectionTextByKeys(this.model, FORMULA_EXPRESSION_KEYS),
        releasePriority: DETAIL_RENDER_PRIORITY_VISIBLE_TEXT,
        formulaPriority: DETAIL_RENDER_PRIORITY_VISIBLE_FORMULA,
      }) {
        this.ExpressionBlock(sectionTextByKeys(this.model, FORMULA_EXPRESSION_KEYS),
          DETAIL_RENDER_PRIORITY_VISIBLE_FORMULA)
      }

      DetailReleaseGate({
        renderSession: this.renderSession,
        releaseKey: this.renderSession.scopeKey('formula|' + formulaModelKey(this.model) + '|parameters'),
        releaseContent: sectionTextByKeys(this.model, FORMULA_PARAMETER_KEYS),
        releasePriority: DETAIL_RENDER_PRIORITY_VISIBLE_TEXT,
        formulaPriority: DETAIL_RENDER_PRIORITY_VISIBLE_FORMULA,
      }) {
        this.ParameterBlock(sectionTextByKeys(this.model, FORMULA_PARAMETER_KEYS),
          DETAIL_RENDER_PRIORITY_VISIBLE_FORMULA)
      }

      DetailReleaseGate({
        renderSession: this.renderSession,
        releaseKey: this.renderSession.scopeKey('formula|' + formulaModelKey(this.model) + '|range'),
        releaseContent: sectionTextByKeys(this.model, FORMULA_RANGE_KEYS),
        releasePriority: DETAIL_RENDER_PRIORITY_NEAR_VIEWPORT,
        formulaPriority: DETAIL_RENDER_PRIORITY_NEAR_VIEWPORT,
      }) {
        this.RangeBlock(sectionTextByKeys(this.model, FORMULA_RANGE_KEYS),
          DETAIL_RENDER_PRIORITY_NEAR_VIEWPORT)
      }

      DetailReleaseGate({
        renderSession: this.renderSession,
        releaseKey: this.renderSession.scopeKey('formula|' + formulaModelKey(this.model) + '|derivation'),
        releaseContent: sectionTextByKeys(this.model, FORMULA_DERIVATION_KEYS),
        releasePriority: DETAIL_RENDER_PRIORITY_OFFSCREEN_TEXT,
        formulaPriority: DETAIL_RENDER_PRIORITY_OFFSCREEN_FORMULA,
      }) {
        this.DerivationBlock(sectionTextByKeys(this.model, FORMULA_DERIVATION_KEYS),
          DETAIL_RENDER_PRIORITY_OFFSCREEN_FORMULA)
      }

      DetailReleaseGate({
        renderSession: this.renderSession,
        releaseKey: this.renderSession.scopeKey('formula|' + formulaModelKey(this.model) + '|notes'),
        releaseContent: sectionTextByKeys(this.model, FORMULA_NOTES_KEYS),
        releasePriority: DETAIL_RENDER_PRIORITY_OFFSCREEN_TEXT,
        formulaPriority: DETAIL_RENDER_PRIORITY_OFFSCREEN_FORMULA,
      }) {
        this.NotesBlock(sectionTextByKeys(this.model, FORMULA_NOTES_KEYS),
          DETAIL_RENDER_PRIORITY_OFFSCREEN_FORMULA)
      }

      DetailReleaseGate({
        renderSession: this.renderSession,
        releaseKey: this.renderSession.scopeKey('formula|' + formulaModelKey(this.model) + '|supplement'),
        releaseContent: unmatchedSectionText(this.model, FORMULA_TEMPLATE_KEYS),
        releasePriority: DETAIL_RENDER_PRIORITY_OFFSCREEN_TEXT,
        formulaPriority: DETAIL_RENDER_PRIORITY_OFFSCREEN_FORMULA,
      }) {
        this.SupplementBlock(unmatchedSectionText(this.model, FORMULA_TEMPLATE_KEYS),
          DETAIL_RENDER_PRIORITY_OFFSCREEN_FORMULA)
      }

      if (!hasAnySectionKey(this.model, FORMULA_TEMPLATE_KEYS)
        && unmatchedSectionText(this.model, FORMULA_TEMPLATE_KEYS).length === 0) {
        DetailReleaseGate({
          renderSession: this.renderSession,
          releaseKey: this.renderSession.scopeKey('formula|' + formulaModelKey(this.model) + '|fallback'),
          releaseContent: fallbackMainText(this.model),
          releasePriority: DETAIL_RENDER_PRIORITY_VISIBLE_TEXT,
          formulaPriority: DETAIL_RENDER_PRIORITY_VISIBLE_FORMULA,
        }) {
          this.ExpressionBlock(fallbackMainText(this.model), DETAIL_RENDER_PRIORITY_VISIBLE_FORMULA)
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
  FormulaTag(label: string, color: ResourceColor) {
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
  ExpressionBlock(content: string, renderPriority: number) {
    if (content.trim().length > 0) {
      Column() {
        this.FormulaTag(LABEL_FORMULA, PINK)
        Text(TITLE_EXPRESSION)
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
  ParameterBlock(content: string, renderPriority: number) {
    if (content.trim().length > 0) {
      Column() {
        this.FormulaTag(LABEL_SYMBOL, PINK)
        Text(TITLE_PARAMETERS)
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
  RangeBlock(content: string, renderPriority: number) {
    if (content.trim().length > 0) {
      Column() {
        this.FormulaTag(LABEL_RANGE, PINK)
        Text(TITLE_RANGE)
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
  DerivationBlock(content: string, renderPriority: number) {
    if (content.trim().length > 0) {
      Column() {
        this.FormulaTag(LABEL_DERIVE, TEXT_3)
        Text(TITLE_DERIVATION)
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
  NotesBlock(content: string, renderPriority: number) {
    if (content.trim().length > 0) {
      Column() {
        this.FormulaTag(LABEL_WARN, TEXT_3)
        Text(TITLE_NOTES)
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
