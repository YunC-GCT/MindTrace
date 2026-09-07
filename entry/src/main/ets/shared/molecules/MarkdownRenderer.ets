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
import { AppIcon } from '../atoms/AppIcon'

const MARKDOWN_INITIAL_BLOCK_LIMIT: number = 3
const MARKDOWN_BLOCK_BATCH_SIZE: number = 3
const MARKDOWN_PARSE_DEFER_MS: number = 16
const MARKDOWN_IMMEDIATE_PARSE_LIMIT: number = 280
const MARKDOWN_PREVIEW_LIMIT: number = 420

@Component
export struct MarkdownRenderer {
  @Prop @Watch('onTextChanged') text: string = ''
  @Prop progressive: boolean = true
  @Prop profile: 'note' | 'chat' = 'note'
  @State visibleBlockCount: number = MARKDOWN_INITIAL_BLOCK_LIMIT
  @State parseReady: boolean = false
  @State parsedBlocks: MarkdownBlock[] = []
  private renderSeq: number = 0
  private parsedKey: string = ''
  private contentProtocol: ContentProtocol = new ContentProtocol()

  aboutToAppear(): void {
    this.resetVisibleBlocks()
  }

  aboutToDisappear(): void {
    this.renderSeq += 1
  }

  onTextChanged(): void {
    this.resetVisibleBlocks()
  }

  build() {
    Column() {
      if (this.parseReady) {
        ForEach(this.visibleBlocks(),
          (block: MarkdownBlock, index: number): void => {
            if (block.kind === 'heading') {
              this.Heading(block)
            } else if (block.kind === 'list') {
              this.ListBlock(block)
            } else if (block.kind === 'quote') {
              this.QuoteBlock(block)
            } else if (block.kind === 'code') {
              this.CodeBlock(block)
            } else if (block.kind === 'formula') {
              this.FormulaBlock(block)
            } else if (block.kind === 'rule') {
              this.RuleBlock()
            } else {
              this.Paragraph(block.text)
            }
          },
          (block: MarkdownBlock, index: number): string => this.blockKey(block, index)
        )
      } else {
        this.PreviewText(this.previewText())
      }

      if (this.hasDeferredBlocks()) {
        this.ContinueReading()
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
  Paragraph(text: string) {
    if (this.containsFormulaSyntax(text)) {
      MathTextRenderer({
        text: text,
        profile: this.mathProfile(),
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
  ListBlock(block: MarkdownBlock) {
    Column() {
      ForEach(block.items,
        (item: string, index: number): void => {
          Row() {
            Text(block.ordered ? (index + 1).toString() + '.' : '•')
              .fontSize(this.bodyFontSize())
              .fontColor(MINT)
              .fontWeight(W_SEMIBOLD)
              .width(this.profile === 'chat' ? 20 : 24)
              .textAlign(TextAlign.Start)

            Column() {
              this.Paragraph(item)
            }
            .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        },
        (item: string, index: number): string => index.toString() + item
      )
    }
    .width('100%')
    .margin({ top: this.profile === 'chat' ? 0 : S_1, bottom: S_1 })
  }

  @Builder
  QuoteBlock(block: MarkdownBlock) {
    Row() {
      Column()
        .width(3)
        .height('100%')
        .backgroundColor(MINT)
        .borderRadius(2)
        .margin({ right: S_2 })

      Column() {
        this.Paragraph(block.text)
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
  FormulaBlock(block: MarkdownBlock) {
    MathTextRenderer({
      text: block.text,
      profile: this.mathProfile(),
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

  @Builder
  ContinueReading() {
    Row() {
      Text('继续阅读')
        .fontSize(F_SM)
        .fontWeight(W_SEMIBOLD)
        .fontColor(MINT)

      Blank().width(S_1)
      AppIcon({ name: 'chevron-down', iconSize: F_SM, color: MINT, strokeWidth: 1.8 })
    }
    .width('100%')
    .height(40)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .onClick((): void => this.showNextBlockBatch())
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

  private resetVisibleBlocks = (): void => {
    this.renderSeq += 1
    const seq: number = this.renderSeq
    const key: string = this.textSignature()
    if (key === this.parsedKey && this.parseReady) {
      return
    }
    this.parsedKey = key
    this.parsedBlocks = []
    this.parseReady = false
    this.visibleBlockCount = 0
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
    if (!this.progressive) {
      this.visibleBlockCount = blocks.length
      return
    }
    if (blocks.length <= MARKDOWN_INITIAL_BLOCK_LIMIT) {
      this.visibleBlockCount = blocks.length
      return
    }
    this.visibleBlockCount = MARKDOWN_INITIAL_BLOCK_LIMIT
  }

  private showNextBlockBatch = (): void => {
    if (!this.parseReady) {
      return
    }
    this.visibleBlockCount = this.parsedBlocks.length
  }

  private visibleBlocks = (): MarkdownBlock[] => {
    if (!this.progressive) {
      return this.parsedBlocks
    }
    if (this.parsedBlocks.length <= this.visibleBlockCount) {
      return this.parsedBlocks
    }
    return this.parsedBlocks.slice(0, this.visibleBlockCount)
  }

  private hasDeferredBlocks = (): boolean => {
    if (!this.progressive || !this.parseReady) {
      return false
    }
    return this.parsedBlocks.length > this.visibleBlockCount
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
