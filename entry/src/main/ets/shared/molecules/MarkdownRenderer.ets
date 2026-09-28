// ============================================================================
//  shared/molecules/MarkdownRenderer.ets - lightweight native markdown renderer
// ============================================================================

import {
  MINT,
  BG_CARD,
  TEXT,
  TEXT_2,
  TEXT_3,
  BORDER,
  GLASS_10,
  S_1, S_2, S_3,
  R_MD,
  F_SM, F_BASE, F_MD, F_LG,
  W_MEDIUM, W_SEMIBOLD, W_BOLD,
  ContentProtocol,
} from 'common'
import { MarkdownBlock } from '../../utils/MarkdownParser'
import { MarkdownInlineSegment } from '../../utils/MarkdownInlineParser'
import { cachedParseMarkdown, cachedParseMarkdownInline } from '../../utils/MarkdownParseCache'
import { MathTextRenderer } from '../atoms/MathTextRenderer'
import { DEFAULT_MATH_RENDER_PRIORITY } from '../../services/MathRenderBudget'
import type { MathRenderBudget } from '../../services/MathRenderBudget'
import { MarkdownContentReleaseBarrier } from '../../services/MarkdownContentReleaseBarrier'

const MARKDOWN_PARSE_DEFER_MS: number = 16
const MARKDOWN_IMMEDIATE_PARSE_LIMIT: number = 280
const MARKDOWN_PREVIEW_LIMIT: number = 420
let markdownContentScopeClock: number = 0

function nextMarkdownContentScope(): string {
  markdownContentScopeClock += 1
  return 'markdown-' + markdownContentScopeClock.toString()
}

@Component
struct MarkdownListItemRenderer {
  @Prop @Watch('onTextChanged') text: string = ''
  @Prop ordered: boolean = false
  @Prop itemIndex: number = 0
  @Prop profile: 'note' | 'chat' = 'note'
  @Prop renderBudget: MathRenderBudget | null = null
  @Prop renderPriority: number = DEFAULT_MATH_RENDER_PRIORITY
  onContentReady: () => void = (): void => {}
  @State private contentReady: boolean = false
  private contentProtocol: ContentProtocol = new ContentProtocol()

  aboutToAppear(): void {
    this.contentReady = false
  }

  onTextChanged(): void {
    this.contentReady = false
  }

  build() {
    Row() {
      if (this.hasFormula()) {
        if (this.contentReady) {
          Text(this.markerText())
            .fontSize(this.bodyFontSize())
            .fontColor(MINT)
            .fontWeight(W_SEMIBOLD)
            .width(this.markerWidth())
            .textAlign(TextAlign.Start)
        } else {
          Blank()
            .width(this.markerWidth())
            .height(0)
        }

        Column() {
          MathTextRenderer({
            text: this.text,
            profile: this.mathProfile(),
            metricSurface: this.profile === 'note' ? 'noteDetail' : 'none',
            renderBudget: this.renderBudget,
            renderPriority: this.renderPriority,
            onContentReady: this.markContentReady,
            textColor: TEXT_2,
            formulaColor: TEXT_2,
            formulaBackground: 'rgba(255,255,255,0.04)',
            formulaBorder: 'rgba(255,255,255,0.10)',
            fontSize: this.bodyFontSize(),
            lineHeight: this.bodyLineHeight(),
            formulaFontSize: this.bodyFontSize(),
            formulaLineHeight: this.bodyLineHeight(),
          })
        }
        .layoutWeight(1)
      } else {
        Text(this.markerText())
          .fontSize(this.bodyFontSize())
          .fontColor(MINT)
          .fontWeight(W_SEMIBOLD)
          .width(this.markerWidth())
          .textAlign(TextAlign.Start)

        Text() {
          ForEach(cachedParseMarkdownInline(this.text),
            (segment: MarkdownInlineSegment, index: number): void => {
              Span(segment.text)
                .fontSize(this.bodyFontSize())
                .fontColor(segment.kind === 'code' ? TEXT : TEXT_2)
                .fontWeight(segment.kind === 'bold' ? W_BOLD : W_MEDIUM)
                .fontFamily(segment.kind === 'code' ? 'monospace' : '')
            },
            (_segment: MarkdownInlineSegment, index: number): string => index.toString()
          )
        }
        .fontSize(this.bodyFontSize())
        .fontColor(TEXT_2)
        .lineHeight(this.bodyLineHeight())
        .layoutWeight(1)
        .textAlign(TextAlign.Start)
        .margin({ bottom: this.paragraphBottomMargin() })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  private markContentReady = (): void => {
    if (this.contentReady) {
      return
    }
    this.contentReady = true
    this.onContentReady()
  }

  private hasFormula = (): boolean => {
    return this.contentProtocol.hasFormulaSyntax(this.text)
  }

  private markerText = (): string => {
    return this.ordered ? (this.itemIndex + 1).toString() + '.' : '•'
  }

  private markerWidth = (): number => {
    return this.profile === 'chat' ? 20 : 24
  }

  private bodyFontSize = (): number => {
    return this.profile === 'chat' ? F_SM : F_BASE
  }

  private bodyLineHeight = (): number => {
    return this.profile === 'chat' ? 20 : 26
  }

  private paragraphBottomMargin = (): number => {
    return this.profile === 'chat' ? S_1 : S_2
  }

  private mathProfile = (): 'note' | 'chat' => {
    return this.profile === 'chat' ? 'chat' : 'note'
  }
}

@Component
export struct MarkdownRenderer {
  @Prop @Watch('onTextChanged') text: string = ''
  @Prop progressive: boolean = true
  @Prop profile: 'note' | 'chat' = 'note'
  @Prop renderBudget: MathRenderBudget | null = null
  @Prop renderPriority: number = DEFAULT_MATH_RENDER_PRIORITY
  @State parseReady: boolean = false
  @State parsedBlocks: MarkdownBlock[] = []
  @State releasedUnitKeys: string[] = []
  private renderSeq: number = 0
  private parsedKey: string = ''
  private contentScope: string = nextMarkdownContentScope()
  private contentProtocol: ContentProtocol = new ContentProtocol()
  private contentBarrier: MarkdownContentReleaseBarrier = new MarkdownContentReleaseBarrier()
  private deferredBlockIndex: number = -1
  private deferredItemIndex: number = 0
  private deferredSeq: number = 0

  aboutToAppear(): void {
    this.resetRender()
  }

  aboutToDisappear(): void {
    this.renderSeq += 1
  }

  onTextChanged(): void {
    this.resetRender()
  }

  build() {
    Column() {
      if (this.parseReady) {
        ForEach(this.parsedBlocks,
          (block: MarkdownBlock, index: number): void => {
            if (block.kind === 'list' && this.hasReleasedListItem(block, index)) {
              this.ListBlock(block, index)
            } else if (this.isUnitReleased(this.blockUnitKey(index)) && block.kind === 'heading') {
              this.Heading(block)
            } else if (this.isUnitReleased(this.blockUnitKey(index)) && block.kind === 'quote') {
              this.QuoteBlock(block, index)
            } else if (this.isUnitReleased(this.blockUnitKey(index)) && block.kind === 'code') {
              this.CodeBlock(block)
            } else if (this.isUnitReleased(this.blockUnitKey(index)) && block.kind === 'formula') {
              this.FormulaBlock(block, index)
            } else if (this.isUnitReleased(this.blockUnitKey(index)) && block.kind === 'rule') {
              this.RuleBlock()
            } else if (this.isUnitReleased(this.blockUnitKey(index)) && block.kind !== 'list') {
              this.Paragraph(block.text, this.blockUnitKey(index))
            }
          },
          (block: MarkdownBlock, index: number): string => this.blockKey(block, index)
        )
      } else {
        this.PreviewText(this.previewText())
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  PreviewText(text: string) {
    if (text.length > 0) {
      Text(text)
        .fontSize(this.bodyFontSize())
        .fontColor(TEXT_2)
        .lineHeight(this.bodyLineHeight())
        .width('100%')
        .textAlign(TextAlign.Start)
        .margin({ bottom: this.paragraphBottomMargin() })
    }
  }

  @Builder
  Heading(block: MarkdownBlock) {
    Text(block.text)
      .fontSize(this.headingSize(block.level))
      .fontWeight(W_BOLD)
      .fontColor(block.level === 1 ? TEXT : MINT)
      .lineHeight(this.headingLineHeight(block.level))
      .width('100%')
      .margin({ top: this.headingTopMargin(block.level), bottom: this.headingBottomMargin() })
  }

  @Builder
  Paragraph(text: string, unitKey: string) {
    if (this.containsFormulaSyntax(text)) {
      MathTextRenderer({
        text: text,
        profile: this.mathProfile(),
        metricSurface: this.profile === 'note' ? 'noteDetail' : 'none',
        renderBudget: this.renderBudget,
        renderPriority: this.renderPriority,
        onContentReady: (): void => this.markUnitContentReady(unitKey),
        textColor: TEXT_2,
        formulaColor: TEXT_2,
        formulaBackground: 'rgba(255,255,255,0.04)',
        formulaBorder: 'rgba(255,255,255,0.10)',
        fontSize: this.bodyFontSize(),
        lineHeight: this.bodyLineHeight(),
        formulaFontSize: this.bodyFontSize(),
        formulaLineHeight: this.bodyLineHeight(),
      })
    } else {
      Text() {
        ForEach(cachedParseMarkdownInline(text),
          (segment: MarkdownInlineSegment, index: number): void => {
            Span(segment.text)
              .fontSize(this.bodyFontSize())
              .fontColor(segment.kind === 'code' ? TEXT : TEXT_2)
              .fontWeight(segment.kind === 'bold' ? W_BOLD : W_MEDIUM)
              .fontFamily(segment.kind === 'code' ? 'monospace' : '')
          },
          (_segment: MarkdownInlineSegment, index: number): string => index.toString()
        )
      }
      .fontSize(this.bodyFontSize())
      .fontColor(TEXT_2)
      .lineHeight(this.bodyLineHeight())
      .width('100%')
      .textAlign(TextAlign.Start)
      .margin({ bottom: this.paragraphBottomMargin() })
    }
  }

  @Builder
  ListBlock(block: MarkdownBlock, blockIndex: number) {
    Column() {
      ForEach(block.items,
        (item: string, index: number): void => {
          if (this.isUnitReleased(this.listItemUnitKey(blockIndex, index))) {
            MarkdownListItemRenderer({
              text: item,
              ordered: block.ordered,
              itemIndex: index,
              profile: this.profile,
              renderBudget: this.renderBudget,
              renderPriority: this.renderPriority,
              onContentReady: (): void => this.markUnitContentReady(
                this.listItemUnitKey(blockIndex, index)),
            })
          }
        },
        (item: string, index: number): string => index.toString() + item
      )
    }
    .width('100%')
    .margin({ top: this.profile === 'chat' ? 0 : S_1, bottom: S_1 })
  }

  @Builder
  QuoteBlock(block: MarkdownBlock, blockIndex: number) {
    Row() {
      Column()
        .width(3)
        .height('100%')
        .backgroundColor(MINT)
        .borderRadius(2)
        .margin({ right: S_2 })

      Column() {
        this.Paragraph(block.text, this.blockUnitKey(blockIndex))
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: S_2, right: S_2, top: S_2, bottom: S_2 })
    .margin({ top: S_1, bottom: S_2 })
    .borderRadius(R_MD)
    .backgroundColor(GLASS_10)
  }

  @Builder
  CodeBlock(block: MarkdownBlock) {
    Column() {
      if (block.lang.length > 0) {
        Text(block.lang)
          .fontSize(F_SM)
          .fontColor(TEXT_3)
          .fontWeight(W_SEMIBOLD)
          .width('100%')
          .margin({ bottom: S_1 })
      }

      Text(block.text)
        .fontSize(F_SM)
        .fontColor(TEXT)
        .fontFamily('monospace')
        .lineHeight(22)
        .width('100%')
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .padding({ left: S_3, right: S_3, top: S_2, bottom: S_2 })
    .margin({ top: S_1, bottom: S_2 })
    .borderRadius(R_MD)
    .backgroundColor(BG_CARD)
    .border({ width: 1, color: BORDER })
  }

  @Builder
  FormulaBlock(block: MarkdownBlock, blockIndex: number) {
    MathTextRenderer({
      text: block.text,
      profile: this.mathProfile(),
      metricSurface: this.profile === 'note' ? 'noteDetail' : 'none',
      renderBudget: this.renderBudget,
      renderPriority: this.renderPriority,
      onContentReady: (): void => this.markUnitContentReady(this.blockUnitKey(blockIndex)),
      forceDisplay: true,
      textColor: TEXT_2,
      formulaColor: TEXT_2,
      formulaBackground: 'rgba(255,255,255,0.04)',
      formulaBorder: 'rgba(255,255,255,0.10)',
      fontSize: this.bodyFontSize(),
      lineHeight: this.bodyLineHeight(),
      formulaFontSize: this.bodyFontSize(),
      formulaLineHeight: this.bodyLineHeight(),
    })
  }

  @Builder
  RuleBlock() {
    Divider()
      .strokeWidth(1)
      .color(BORDER)
      .width('100%')
      .margin({ top: S_3, bottom: S_3 })
  }

  private headingSize = (level: number): number => {
    if (this.profile === 'chat') {
      if (level === 1) { return F_MD }
      if (level === 2) { return F_BASE }
      return F_SM
    }
    if (level === 1) { return F_LG }
    if (level === 2) { return F_MD }
    return F_SM
  }

  private headingLineHeight = (level: number): number => {
    if (this.profile === 'chat') {
      if (level === 1) { return 24 }
      if (level === 2) { return 22 }
      return 20
    }
    if (level === 1) { return 28 }
    if (level === 2) { return 24 }
    return 20
  }

  private bodyFontSize = (): number => {
    return this.profile === 'chat' ? F_SM : F_BASE
  }

  private bodyLineHeight = (): number => {
    return this.profile === 'chat' ? 20 : 26
  }

  private paragraphBottomMargin = (): number => {
    return this.profile === 'chat' ? S_1 : S_2
  }

  private headingTopMargin = (level: number): number => {
    if (this.profile === 'chat') {
      return level === 1 ? S_2 : S_1
    }
    return level === 1 ? S_3 : S_2
  }

  private headingBottomMargin = (): number => {
    return this.profile === 'chat' ? S_1 : S_2
  }

  private mathProfile = (): 'note' | 'chat' => {
    return this.profile === 'chat' ? 'chat' : 'note'
  }

  private containsFormulaSyntax = (text: string): boolean => {
    return this.contentProtocol.hasFormulaSyntax(text)
  }

  private resetRender = (): void => {
    this.renderSeq += 1
    const seq: number = this.renderSeq
    const key: string = this.textSignature()
    if (key === this.parsedKey && this.parseReady) {
      this.resumeContentRelease(this.parsedBlocks, seq)
      return
    }
    this.parsedKey = key
    this.parsedBlocks = []
    this.releasedUnitKeys = []
    this.resetContentBarrier()
    this.parseReady = false
    if (!this.progressive || this.text.trim().length <= MARKDOWN_IMMEDIATE_PARSE_LIMIT) {
      this.applyParsedBlocks(cachedParseMarkdown(this.text), seq)
      return
    }
    this.scheduleParse(seq)
  }

  private scheduleParse = (seq: number): void => {
    setTimeout((): void => {
      if (seq !== this.renderSeq) {
        return
      }
      this.applyParsedBlocks(cachedParseMarkdown(this.text), seq)
    }, MARKDOWN_PARSE_DEFER_MS)
  }

  private applyParsedBlocks = (blocks: MarkdownBlock[], seq: number): void => {
    if (seq !== this.renderSeq) {
      return
    }
    this.parsedBlocks = blocks
    this.parseReady = true
    if (this.profile !== 'note' || this.renderBudget === null) {
      this.releasedUnitKeys = this.allUnitKeys(blocks)
      return
    }
    this.scheduleContentUnit(blocks, 0, 0, seq)
  }

  private scheduleContentUnit = (blocks: MarkdownBlock[], blockIndex: number,
    itemIndex: number, seq: number): void => {
    if (seq !== this.renderSeq || this.renderBudget === null || blockIndex >= blocks.length) {
      return
    }
    const block: MarkdownBlock = blocks[blockIndex]
    if (block.kind === 'list' && itemIndex >= block.items.length) {
      if (this.contentBarrier.deferNextBlock()) {
        this.deferContinuation(blockIndex + 1, 0, seq)
        return
      }
      this.scheduleContentUnit(blocks, blockIndex + 1, 0, seq)
      return
    }
    const unitKey: string = block.kind === 'list'
      ? this.listItemUnitKey(blockIndex, itemIndex)
      : this.blockUnitKey(blockIndex)
    const waitsForContent: boolean = this.unitWaitsForContent(block, itemIndex)
    if (waitsForContent) {
      this.contentBarrier.waitFor(unitKey)
      if (block.kind !== 'list') {
        this.contentBarrier.deferNextBlock()
        this.deferContinuation(blockIndex + 1, 0, seq)
      }
    }
    this.renderBudget.enqueueContent(this.contentScope + '|' + this.textSignature() + '|' + unitKey,
      this.renderPriority, (): void => {
        if (seq !== this.renderSeq) {
          return
        }
        this.releasedUnitKeys = this.releasedUnitKeys.concat(unitKey)
        if (block.kind === 'list') {
          this.scheduleContentUnit(blocks, blockIndex, itemIndex + 1, seq)
        } else if (!waitsForContent) {
          this.scheduleContentUnit(blocks, blockIndex + 1, 0, seq)
        }
      })
  }

  private markUnitContentReady = (unitKey: string): void => {
    if (!this.contentBarrier.complete(unitKey) || this.deferredSeq !== this.renderSeq
      || this.deferredBlockIndex < 0) {
      return
    }
    const blockIndex: number = this.deferredBlockIndex
    const itemIndex: number = this.deferredItemIndex
    const seq: number = this.deferredSeq
    this.clearDeferredContinuation()
    this.scheduleContentUnit(this.parsedBlocks, blockIndex, itemIndex, seq)
  }

  private unitWaitsForContent = (block: MarkdownBlock, itemIndex: number): boolean => {
    if (block.kind === 'formula') {
      return true
    }
    if (block.kind === 'list') {
      return itemIndex < block.items.length
        && this.containsFormulaSyntax(block.items[itemIndex])
    }
    return (block.kind === 'paragraph' || block.kind === 'quote')
      && this.containsFormulaSyntax(block.text)
  }

  private deferContinuation = (blockIndex: number, itemIndex: number, seq: number): void => {
    this.deferredBlockIndex = blockIndex
    this.deferredItemIndex = itemIndex
    this.deferredSeq = seq
  }

  private clearDeferredContinuation = (): void => {
    this.deferredBlockIndex = -1
    this.deferredItemIndex = 0
    this.deferredSeq = 0
  }

  private resetContentBarrier = (): void => {
    this.contentBarrier.reset()
    this.clearDeferredContinuation()
  }

  private resumeContentRelease = (blocks: MarkdownBlock[], seq: number): void => {
    if (this.profile !== 'note' || this.renderBudget === null) {
      return
    }
    const waitsForPendingContent: boolean = this.contentBarrier.deferNextBlock()
    let blockIndex: number = 0
    while (blockIndex < blocks.length) {
      const block: MarkdownBlock = blocks[blockIndex]
      if (block.kind === 'list') {
        let itemIndex: number = 0
        while (itemIndex < block.items.length) {
          if (!this.isUnitReleased(this.listItemUnitKey(blockIndex, itemIndex))) {
            if (waitsForPendingContent) {
              this.deferContinuation(blockIndex, itemIndex, seq)
            } else {
              this.scheduleContentUnit(blocks, blockIndex, itemIndex, seq)
            }
            return
          }
          itemIndex += 1
        }
      } else if (!this.isUnitReleased(this.blockUnitKey(blockIndex))) {
        if (waitsForPendingContent) {
          this.deferContinuation(blockIndex, 0, seq)
        } else {
          this.scheduleContentUnit(blocks, blockIndex, 0, seq)
        }
        return
      }
      blockIndex += 1
    }
  }

  private allUnitKeys = (blocks: MarkdownBlock[]): string[] => {
    const keys: string[] = []
    let blockIndex: number = 0
    while (blockIndex < blocks.length) {
      const block: MarkdownBlock = blocks[blockIndex]
      if (block.kind === 'list') {
        let itemIndex: number = 0
        while (itemIndex < block.items.length) {
          keys.push(this.listItemUnitKey(blockIndex, itemIndex))
          itemIndex += 1
        }
      } else {
        keys.push(this.blockUnitKey(blockIndex))
      }
      blockIndex += 1
    }
    return keys
  }

  private hasReleasedListItem = (block: MarkdownBlock, blockIndex: number): boolean => {
    let itemIndex: number = 0
    while (itemIndex < block.items.length) {
      if (this.isUnitReleased(this.listItemUnitKey(blockIndex, itemIndex))) {
        return true
      }
      itemIndex += 1
    }
    return false
  }

  private isUnitReleased = (key: string): boolean => {
    return this.releasedUnitKeys.indexOf(key) >= 0
  }

  private blockUnitKey = (blockIndex: number): string => {
    return 'block-' + blockIndex.toString()
  }

  private listItemUnitKey = (blockIndex: number, itemIndex: number): string => {
    return 'list-' + blockIndex.toString() + '-' + itemIndex.toString()
  }

  private previewText = (): string => {
    const normalized: string = this.text.replace(/\r\n/g, '\n').replace(/\r/g, '\n').trim()
    if (normalized.length <= MARKDOWN_PREVIEW_LIMIT) {
      return normalized
    }
    return normalized.substring(0, MARKDOWN_PREVIEW_LIMIT).trim() + '...'
  }

  private textSignature = (): string => {
    let hash: number = 5381
    let index: number = 0
    while (index < this.text.length) {
      hash = ((hash << 5) + hash + this.text.charCodeAt(index)) | 0
      index += 1
    }
    const positive: number = hash < 0 ? -hash : hash
    return this.text.length.toString() + ':' + positive.toString() + ':'
      + (this.progressive ? '1' : '0') + ':' + this.profile
  }

  private blockKey = (block: MarkdownBlock, index: number): string => {
    return index.toString() + ':' + block.kind + ':' + block.text.length.toString()
  }
}
