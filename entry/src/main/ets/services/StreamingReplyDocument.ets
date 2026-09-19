/**
 * StreamingReplyDocument.ets — Chat 流式 Reply Body 增量渲染文档
 *
 * 路径: entry/src/main/ets/services/StreamingReplyDocument.ets
 * 职责: 从 append-only Reply Body 构建稳定 ReplyBlock、公式 slot 与几何状态。
 * 依赖: common ContentProtocol、CustomSpanPlaceholderSeam、ArkUI MutableStyledString。
 * 数据流: applyDelta/finalize → raw parser → ReplyBlockSnapshot / NativeMarkdownProjection / DocumentGeometryState
 * ArkTS 1.1 strict 适配: 使用显式接口、类状态和 Map，避免 any/unknown、解构与结构化类型。
 */
import { ContentProtocol, ContentValidationResult } from 'common';
import { FORMULA_PLACEHOLDER_MAX_CHARS, estimatePlaceholderWidthVp } from './CustomSpanPlaceholderSeam';

export type ReplyBlockKind = 'paragraph' | 'heading' | 'list' | 'quote' | 'formula' | 'code' | 'fallback';
export type ReplyBlockPhase = 'open' | 'sealed';
export type ReplyRenderBackend = 'styled_string' | 'custom_span' | 'arkweb_slot';
export type BlockPatchType = 'upsert' | 'seal' | 'finalize';

export interface InlineFormulaSlotSnapshot {
  slotId: string;
  rawStartOffset: number;
  rawText: string;
  placeholderText: string;
  widthVp: number;
  widthStable: boolean;
  closed: boolean;
  updateCount: number;
  renderBackend: ReplyRenderBackend;
}

export interface ReplyBlockSnapshot {
  blockId: string;
  messageId: string;
  startOffset: number;
  endOffset: number;
  rawText: string;
  renderText: string;
  kind: ReplyBlockKind;
  phase: ReplyBlockPhase;
  stablePrefixLen: number;
  parseCount: number;
  renderBackend: ReplyRenderBackend;
  formulaSlotId: string;
  inlineFormulaSlotIds: string[];
  inlineFormulaSlots: InlineFormulaSlotSnapshot[];
  placeholderText: string;
  pendingRenderWork: boolean;
  estimatedHeight: number;
  renderedHeight: number;
}

export interface BlockPatch {
  patchType: BlockPatchType;
  reason: string;
  block: ReplyBlockSnapshot;
  dirtyStart: number;
  dirtyEnd: number;
}

export interface DocumentGeometryState {
  finalized: boolean;
  allBlocksSettled: boolean;
  totalHeight: number;
  geometryEvents: number;
  lastHeightDelta: number;
  schedulerQueueEmpty: boolean;
}

export interface StyledTextSegment {
  kind: string;
  text: string;
}

export class NativeMarkdownProjection {
  readonly backend: ReplyRenderBackend = 'styled_string';
  readonly text: string;
  readonly segments: StyledTextSegment[];
  readonly inlineFormulaSlots: InlineFormulaSlotSnapshot[];
  readonly inlineFormulaBackend: ReplyRenderBackend = 'custom_span';
  readonly customSpanSlotIds: string[];
  readonly styledString: MutableStyledString;

  constructor(text: string, segments: StyledTextSegment[], slots: InlineFormulaSlotSnapshot[]) {
    this.text = text;
    this.segments = segments.slice();
    this.inlineFormulaSlots = slots.slice();
    this.customSpanSlotIds = [];
    for (const slot of slots) {
      this.customSpanSlotIds.push(slot.slotId);
    }
    this.styledString = new MutableStyledString(text);
  }
}

const FORMULA_PLACEHOLDER_PREFIX: string = '公式生成中: ';
const FORMULA_FONT_SIZE_VP: number = 16;
const FORMULA_ESTIMATED_HEIGHT: number = 58;

class SourceLine {
  readonly text: string;
  readonly startOffset: number;
  readonly endOffset: number;
  readonly complete: boolean;

  constructor(text: string, startOffset: number, endOffset: number, complete: boolean) {
    this.text = text;
    this.startOffset = startOffset;
    this.endOffset = endOffset;
    this.complete = complete;
  }
}

class ParsedReplyBlock {
  kind: ReplyBlockKind;
  startOffset: number;
  endOffset: number;
  rawText: string;
  renderText: string;
  phase: ReplyBlockPhase;
  stablePrefixLen: number;
  formulaSlotId: string;
  inlineFormulaSlots: InlineFormulaSlotSnapshot[];
  placeholderText: string;
  pendingRenderWork: boolean;
  estimatedHeight: number;
  renderedHeight: number;
  formulaClosed: boolean;

  constructor(kind: ReplyBlockKind, startOffset: number, endOffset: number, rawText: string) {
    this.kind = kind;
    this.startOffset = startOffset;
    this.endOffset = endOffset;
    this.rawText = rawText;
    this.renderText = rawText;
    this.phase = 'open';
    this.stablePrefixLen = 0;
    this.formulaSlotId = '';
    this.inlineFormulaSlots = [];
    this.placeholderText = '';
    this.pendingRenderWork = false;
    this.estimatedHeight = 20;
    this.renderedHeight = 20;
    this.formulaClosed = false;
  }
}

class InternalReplyBlock {
  readonly blockId: string;
  readonly messageId: string;
  startOffset: number;
  endOffset: number;
  rawText: string;
  renderText: string;
  kind: ReplyBlockKind;
  phase: ReplyBlockPhase;
  stablePrefixLen: number;
  parseCount: number;
  renderBackend: ReplyRenderBackend;
  formulaSlotId: string;
  inlineFormulaSlots: InlineFormulaSlotSnapshot[];
  placeholderText: string;
  pendingRenderWork: boolean;
  estimatedHeight: number;
  renderedHeight: number;
  formulaClosed: boolean;

  constructor(messageId: string, parsed: ParsedReplyBlock, blockId: string, parseCount: number) {
    this.messageId = messageId;
    this.blockId = blockId;
    this.startOffset = parsed.startOffset;
    this.endOffset = parsed.endOffset;
    this.rawText = parsed.rawText;
    this.renderText = parsed.renderText;
    this.kind = parsed.kind;
    this.phase = parsed.phase;
    this.stablePrefixLen = parsed.stablePrefixLen;
    this.parseCount = parseCount;
    this.renderBackend = backendFor(parsed);
    this.formulaSlotId = parsed.formulaSlotId;
    this.inlineFormulaSlots = copyInlineFormulaSlots(parsed.inlineFormulaSlots);
    this.placeholderText = parsed.placeholderText;
    this.pendingRenderWork = parsed.pendingRenderWork;
    this.estimatedHeight = parsed.estimatedHeight;
    this.renderedHeight = parsed.renderedHeight;
    this.formulaClosed = parsed.formulaClosed;
  }
}

function backendFor(parsed: ParsedReplyBlock): ReplyRenderBackend {
  if (parsed.kind === 'formula') {
    return 'arkweb_slot';
  }
  return 'styled_string';
}

function copyInlineFormulaSlot(slot: InlineFormulaSlotSnapshot): InlineFormulaSlotSnapshot {
  const copy: InlineFormulaSlotSnapshot = {
    slotId: slot.slotId,
    rawStartOffset: slot.rawStartOffset,
    rawText: slot.rawText,
    placeholderText: slot.placeholderText,
    widthVp: slot.widthVp,
    widthStable: slot.widthStable,
    closed: slot.closed,
    updateCount: slot.updateCount,
    renderBackend: slot.renderBackend,
  };
  return copy;
}

function copyInlineFormulaSlots(slots: InlineFormulaSlotSnapshot[]): InlineFormulaSlotSnapshot[] {
  const copies: InlineFormulaSlotSnapshot[] = [];
  for (const slot of slots) {
    copies.push(copyInlineFormulaSlot(slot));
  }
  return copies;
}

function isEscaped(text: string, index: number): boolean {
  let slashCount: number = 0;
  let cursor: number = index - 1;
  while (cursor >= 0 && text.charAt(cursor) === '\\') {
    slashCount += 1;
    cursor -= 1;
  }
  return slashCount % 2 === 1;
}

function trimLine(text: string): string {
  return text.endsWith('\r') ? text.substring(0, text.length - 1).trim() : text.trim();
}

function stripTrailingLineBreaks(text: string): string {
  let result: string = text;
  while (result.endsWith('\n') || result.endsWith('\r')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}

function isBlankLine(line: SourceLine): boolean {
  return trimLine(line.text).length === 0;
}

function headingLevel(text: string): number {
  const line: string = trimLine(text);
  let count: number = 0;
  while (count < line.length && line.charAt(count) === '#') {
    count += 1;
  }
  if (count < 1 || count > 3 || line.charAt(count) !== ' ') {
    return 0;
  }
  return count;
}

function isCodeFence(text: string): boolean {
  return trimLine(text).indexOf('```') === 0;
}

function isFormulaFence(text: string): boolean {
  const line: string = trimLine(text);
  return line === '$$' || line === '\\[';
}

function isFormulaClose(text: string, opener: string): boolean {
  const line: string = trimLine(text);
  return opener === '$$' ? line === '$$' : line === '\\]';
}

function isRule(text: string): boolean {
  const line: string = trimLine(text);
  return line === '---' || line === '***' || line === '___';
}

function listItemText(text: string): string {
  const line: string = trimLine(text);
  if (line.length > 2 && (line.charAt(0) === '-' || line.charAt(0) === '*' || line.charAt(0) === '+')
    && line.charAt(1) === ' ') {
    return line.substring(2).trim();
  }
  let cursor: number = 0;
  while (cursor < line.length && line.charAt(cursor) >= '0' && line.charAt(cursor) <= '9') {
    cursor += 1;
  }
  if (cursor > 0 && cursor + 1 < line.length && line.charAt(cursor) === '.' && line.charAt(cursor + 1) === ' ') {
    return line.substring(cursor + 2).trim();
  }
  return '';
}

function listIsOrdered(text: string): boolean {
  const line: string = trimLine(text);
  let cursor: number = 0;
  while (cursor < line.length && line.charAt(cursor) >= '0' && line.charAt(cursor) <= '9') {
    cursor += 1;
  }
  return cursor > 0 && cursor + 1 < line.length && line.charAt(cursor) === '.' && line.charAt(cursor + 1) === ' ';
}

function isQuote(text: string): boolean {
  return trimLine(text).indexOf('> ') === 0;
}

function stripQuote(text: string): string {
  const line: string = trimLine(text);
  return line.indexOf('> ') === 0 ? line.substring(2).trim() : line;
}

function stripInlineDecorators(text: string): string {
  let result: string = text;
  result = result.split('**').join('');
  result = result.split('`').join('');
  return result;
}

function hasUnclosedInlineMarker(text: string): boolean {
  let boldCount: number = 0;
  let codeOpen: boolean = false;
  let dollarCount: number = 0;
  let index: number = 0;
  while (index < text.length) {
    const current: string = text.charAt(index);
    if (current === '\\' && index + 1 < text.length) {
      index += 2;
      continue;
    }
    if (current === '`') {
      codeOpen = !codeOpen;
      index += 1;
      continue;
    }
    if (!codeOpen && current === '*' && index + 1 < text.length && text.charAt(index + 1) === '*') {
      boldCount += 1;
      index += 2;
      continue;
    }
    if (!codeOpen && current === '$' && (index + 1 >= text.length || text.charAt(index + 1) !== '$')
      && !isEscaped(text, index)) {
      dollarCount += 1;
    }
    index += 1;
  }
  return codeOpen || boldCount % 2 === 1 || dollarCount % 2 === 1;
}

function firstUnclosedMarker(text: string): number {
  let boldIndex: number = -1;
  let codeIndex: number = -1;
  let dollarIndex: number = -1;
  let boldCount: number = 0;
  let codeOpen: boolean = false;
  let dollarCount: number = 0;
  let index: number = 0;
  while (index < text.length) {
    const current: string = text.charAt(index);
    if (current === '\\' && index + 1 < text.length) {
      index += 2;
      continue;
    }
    if (current === '`') {
      if (!codeOpen) {
        codeIndex = index;
      }
      codeOpen = !codeOpen;
      index += 1;
      continue;
    }
    if (!codeOpen && current === '*' && index + 1 < text.length && text.charAt(index + 1) === '*') {
      boldCount += 1;
      if (boldCount % 2 === 1) {
        boldIndex = index;
      }
      index += 2;
      continue;
    }
    if (!codeOpen && current === '$' && (index + 1 >= text.length || text.charAt(index + 1) !== '$')
      && !isEscaped(text, index)) {
      dollarCount += 1;
      if (dollarCount % 2 === 1) {
        dollarIndex = index;
      }
    }
    index += 1;
  }
  if (codeOpen) {
    return codeIndex;
  }
  if (boldCount % 2 === 1) {
    return boldIndex;
  }
  if (dollarCount % 2 === 1) {
    return dollarIndex;
  }
  return -1;
}

function capFormulaText(text: string): string {
  const normalized: string = text.trim();
  if (normalized.length <= FORMULA_PLACEHOLDER_MAX_CHARS) {
    return normalized;
  }
  return normalized.substring(0, FORMULA_PLACEHOLDER_MAX_CHARS);
}

function estimateInlineFormulaWidth(text: string): number {
  return estimatePlaceholderWidthVp(text, FORMULA_FONT_SIZE_VP);
}

function escapePlainText(text: string): string {
  let result: string = text;
  result = result.split('&').join('&amp;');
  result = result.split('<').join('&lt;');
  result = result.split('>').join('&gt;');
  result = result.split('"').join('&quot;');
  result = result.split("'").join('&#39;');
  return result;
}

function isUnsupportedSyntax(text: string): boolean {
  const line: string = trimLine(text);
  if (line.indexOf('~~') >= 0 || line.indexOf('|---') >= 0 || line.indexOf('---|') >= 0) {
    return true;
  }
  if (line.indexOf('](') >= 0 || line.indexOf('![') >= 0) {
    return true;
  }
  if (line.indexOf('<') >= 0 && line.indexOf('>') > line.indexOf('<')) {
    return true;
  }
  if (line.charAt(0) === '#' && headingLevel(line) === 0) {
    return true;
  }
  return false;
}

function splitSourceLines(text: string, baseOffset: number): SourceLine[] {
  const lines: SourceLine[] = [];
  let cursor: number = 0;
  while (cursor < text.length) {
    const newlineIndex: number = text.indexOf('\n', cursor);
    if (newlineIndex < 0) {
      lines.push(new SourceLine(text.substring(cursor), baseOffset + cursor, baseOffset + text.length, false));
      cursor = text.length;
    } else {
      lines.push(new SourceLine(text.substring(cursor, newlineIndex), baseOffset + cursor,
        baseOffset + newlineIndex + 1, true));
      cursor = newlineIndex + 1;
    }
  }
  return lines;
}

function copyStyledSegments(segments: StyledTextSegment[]): StyledTextSegment[] {
  const copies: StyledTextSegment[] = [];
  for (const segment of segments) {
    const copy: StyledTextSegment = { kind: segment.kind, text: segment.text };
    copies.push(copy);
  }
  return copies;
}

function parseStyledSegments(text: string): StyledTextSegment[] {
  const segments: StyledTextSegment[] = [];
  let cursor: number = 0;
  let buffer: string = '';
  while (cursor < text.length) {
    if (text.substring(cursor).indexOf('**') === 0) {
      const close: number = text.indexOf('**', cursor + 2);
      if (close > cursor + 2) {
        if (buffer.length > 0) {
          segments.push({ kind: 'text', text: buffer });
          buffer = '';
        }
        segments.push({ kind: 'bold', text: text.substring(cursor + 2, close) });
        cursor = close + 2;
        continue;
      }
    }
    if (text.charAt(cursor) === '`') {
      const closeCode: number = text.indexOf('`', cursor + 1);
      if (closeCode > cursor + 1) {
        if (buffer.length > 0) {
          segments.push({ kind: 'text', text: buffer });
          buffer = '';
        }
        segments.push({ kind: 'code', text: text.substring(cursor + 1, closeCode) });
        cursor = closeCode + 1;
        continue;
      }
    }
    buffer += text.charAt(cursor);
    cursor += 1;
  }
  if (buffer.length > 0) {
    segments.push({ kind: 'text', text: buffer });
  }
  if (segments.length === 0) {
    segments.push({ kind: 'text', text: text });
  }
  return segments;
}

function sameInlineSlots(left: InlineFormulaSlotSnapshot[], right: InlineFormulaSlotSnapshot[]): boolean {
  if (left.length !== right.length) {
    return false;
  }
  let index: number = 0;
  while (index < left.length) {
    if (left[index].slotId !== right[index].slotId || left[index].rawText !== right[index].rawText
      || left[index].closed !== right[index].closed || left[index].widthVp !== right[index].widthVp) {
      return false;
    }
    index += 1;
  }
  return true;
}

function sameParsedBlock(left: InternalReplyBlock, right: InternalReplyBlock): boolean {
  return left.blockId === right.blockId && left.rawText === right.rawText && left.phase === right.phase
    && left.kind === right.kind && left.renderText === right.renderText
    && left.pendingRenderWork === right.pendingRenderWork
    && sameInlineSlots(left.inlineFormulaSlots, right.inlineFormulaSlots);
}

function blockIdFor(messageId: string, startOffset: number): string {
  return messageId + '#' + startOffset.toString();
}

export function buildNativeMarkdownProjection(block: ReplyBlockSnapshot): NativeMarkdownProjection {
  const segments: StyledTextSegment[] = parseStyledSegments(block.renderText);
  return new NativeMarkdownProjection(block.renderText, copyStyledSegments(segments), block.inlineFormulaSlots);
}

export class StreamingReplyDocument {
  private readonly messageId_: string;
  private readonly contentProtocol_: ContentProtocol = new ContentProtocol();
  private rawBody_: string = '';
  private sealedBlocks_: InternalReplyBlock[] = [];
  private openTail_: InternalReplyBlock | undefined = undefined;
  private sealedRawEnd_: number = 0;
  private finalized_: boolean = false;
  private geometryEvents_: number = 0;
  private lastHeightDelta_: number = 0;
  private schedulerQueueEmpty_: boolean = true;
  private lastScanStartOffset_: number = 0;
  private readonly inlineSlotWidths_: Map<string, number> = new Map<string, number>();
  private readonly inlineSlotUpdates_: Map<string, number> = new Map<string, number>();
  private readonly inlineSlotClosed_: Map<string, boolean> = new Map<string, boolean>();

  constructor(messageId: string | number) {
    this.messageId_ = messageId.toString();
  }

  applyDelta(delta: string): BlockPatch[] {
    if (this.finalized_) {
      throw new Error('cannot append delta after finalized message');
    }
    if (delta.length === 0) {
      return [];
    }
    this.rawBody_ += delta;
    return this.rebuildOpenTail(false);
  }

  finalize(): BlockPatch[] {
    if (this.finalized_) {
      return [];
    }
    const patches: BlockPatch[] = this.rebuildOpenTail(true);
    this.finalized_ = true;
    if (patches.length > 0) {
      return patches;
    }
    return [];
  }

  rawBody(): string {
    return this.rawBody_;
  }

  blocks(): ReplyBlockSnapshot[] {
    const snapshots: ReplyBlockSnapshot[] = [];
    for (const block of this.sealedBlocks_) {
      snapshots.push(this.snapshotOf(block));
    }
    if (this.openTail_ !== undefined) {
      snapshots.push(this.snapshotOf(this.openTail_));
    }
    return snapshots;
  }

  openTailStablePrefixLen(): number {
    if (this.openTail_ === undefined) {
      return 0;
    }
    return this.openTail_.stablePrefixLen;
  }

  geometryState(): DocumentGeometryState {
    const state: DocumentGeometryState = {
      finalized: this.finalized_,
      allBlocksSettled: this.isAllBlocksSettled(),
      totalHeight: this.totalHeight(),
      geometryEvents: this.geometryEvents_,
      lastHeightDelta: this.lastHeightDelta_,
      schedulerQueueEmpty: this.schedulerQueueEmpty_,
    };
    return state;
  }

  setSchedulerQueueEmpty(isEmpty: boolean): void {
    this.schedulerQueueEmpty_ = isEmpty;
  }

  lastScanStartOffset(): number {
    return this.lastScanStartOffset_;
  }

  applyBlockHeight(blockId: string, height: number): void {
    const block: InternalReplyBlock | undefined = this.findInternalBlock(blockId);
    if (block === undefined || height <= 0) {
      return;
    }
    const previousHeight: number = this.effectiveHeight(block);
    block.renderedHeight = height;
    block.pendingRenderWork = false;
    this.lastHeightDelta_ = height - previousHeight;
    if (this.lastHeightDelta_ !== 0) {
      this.geometryEvents_ += 1;
    }
  }

  nativeProjection(blockId: string): NativeMarkdownProjection | undefined {
    const block: InternalReplyBlock | undefined = this.findInternalBlock(blockId);
    if (block === undefined) {
      return undefined;
    }
    return buildNativeMarkdownProjection(this.snapshotOf(block));
  }

  private rebuildOpenTail(forceFinalize: boolean): BlockPatch[] {
    const previousOpen: InternalReplyBlock | undefined = this.openTail_;
    const scanStartOffset: number = previousOpen === undefined
      ? this.sealedRawEnd_
      : previousOpen.startOffset + Math.min(previousOpen.stablePrefixLen, previousOpen.rawText.length);
    this.lastScanStartOffset_ = scanStartOffset;
    const active: ParsedReplyBlock[] = this.parseActive(this.sealedRawEnd_, forceFinalize, scanStartOffset);
    const nextSealed: InternalReplyBlock[] = this.sealedBlocks_.slice();
    const patches: BlockPatch[] = [];
    let nextOpen: InternalReplyBlock | undefined = undefined;
    let lastSealedEnd: number = this.sealedRawEnd_;
    let previousOpenUsed: boolean = false;

    for (const parsed of active) {
      const parsedId: string = blockIdFor(this.messageId_, parsed.startOffset);
      const canReuseOpen: boolean = previousOpen !== undefined && previousOpen.blockId === parsedId;
      const previousForBlock: InternalReplyBlock | undefined = canReuseOpen ? previousOpen : undefined;
      if (canReuseOpen) {
        previousOpenUsed = true;
      }
      const parseCount: number = previousForBlock === undefined ? 1 : previousForBlock.parseCount + 1;
      const nextBlock: InternalReplyBlock = this.internalFromParsed(parsed, parsedId, parseCount, previousForBlock);
      if (parsed.phase === 'sealed') {
        this.removeBlockById(nextSealed, nextBlock.blockId);
        nextSealed.push(nextBlock);
        lastSealedEnd = parsed.endOffset;
        const patchType: BlockPatchType = previousForBlock === undefined ? 'upsert' : 'seal';
        const reason: string = previousForBlock === undefined ? 'new_block' : 'open_tail_sealed';
        patches.push(this.makePatch(nextBlock, patchType, reason));
      } else {
        nextOpen = nextBlock;
        const changed: boolean = previousForBlock === undefined || !sameParsedBlock(previousForBlock, nextBlock);
        if (changed) {
          patches.push(this.makePatch(nextBlock, 'upsert', previousForBlock === undefined ? 'new_tail' : 'dirty_range'));
        }
      }
    }

    if (active.length === 0 && this.rawBody_.substring(this.sealedRawEnd_).trim().length === 0) {
      lastSealedEnd = this.rawBody_.length;
    }
    if (previousOpen !== undefined && !previousOpenUsed && nextOpen === undefined) {
      nextOpen = undefined;
    }
    this.sealedBlocks_ = nextSealed;
    this.openTail_ = nextOpen;
    this.sealedRawEnd_ = lastSealedEnd;

    if (forceFinalize && this.openTail_ !== undefined) {
      this.openTail_.phase = 'sealed';
      this.openTail_.pendingRenderWork = this.openTail_.kind === 'formula' && this.openTail_.formulaClosed;
      this.sealedBlocks_.push(this.openTail_);
      patches.push(this.makePatch(this.openTail_, 'seal', 'finalize_tail'));
      this.sealedRawEnd_ = this.openTail_.endOffset;
      this.openTail_ = undefined;
    }
    if (this.hasPendingRenderWork()) {
      this.schedulerQueueEmpty_ = false;
    }
    return patches;
  }

  private parseActive(baseOffset: number, forceFinalize: boolean, scanStartOffset: number): ParsedReplyBlock[] {
    const source: string = this.rawBody_.substring(baseOffset);
    const lines: SourceLine[] = splitSourceLines(source, baseOffset);
    const parsed: ParsedReplyBlock[] = [];
    let index: number = 0;
    while (index < lines.length) {
      if (isBlankLine(lines[index])) {
        index += 1;
        continue;
      }
      const line: SourceLine = lines[index];
      if (isCodeFence(line.text)) {
        const codeResult: ParsedReplyBlock = this.parseCodeBlock(lines, index, forceFinalize, scanStartOffset);
        parsed.push(codeResult);
        index = this.nextIndexAfterBlock(lines, index, codeResult);
        if (codeResult.phase === 'open') {
          break;
        }
        continue;
      }
      if (isFormulaFence(line.text)) {
        const formulaResult: ParsedReplyBlock = this.parseFormulaBlock(lines, index, forceFinalize, scanStartOffset);
        parsed.push(formulaResult);
        index = this.nextIndexAfterBlock(lines, index, formulaResult);
        if (formulaResult.phase === 'open') {
          break;
        }
        continue;
      }
      const level: number = headingLevel(line.text);
      if (level > 0) {
        const headingResult: ParsedReplyBlock = this.parseHeadingBlock(line, level, forceFinalize);
        parsed.push(headingResult);
        index += 1;
        if (headingResult.phase === 'open') {
          break;
        }
        continue;
      }
      if (isQuote(line.text)) {
        const quoteResult: ParsedReplyBlock = this.parseQuoteBlock(lines, index, forceFinalize);
        parsed.push(quoteResult);
        index = this.nextIndexAfterBlock(lines, index, quoteResult);
        if (quoteResult.phase === 'open') {
          break;
        }
        continue;
      }
      if (listItemText(line.text).length > 0) {
        const listResult: ParsedReplyBlock = this.parseListBlock(lines, index, forceFinalize);
        parsed.push(listResult);
        index = this.nextIndexAfterBlock(lines, index, listResult);
        if (listResult.phase === 'open') {
          break;
        }
        continue;
      }
      const paragraphResult: ParsedReplyBlock = this.parseParagraphOrFallback(lines, index, forceFinalize);
      parsed.push(paragraphResult);
      index = this.nextIndexAfterBlock(lines, index, paragraphResult);
      if (paragraphResult.phase === 'open') {
        break;
      }
    }
    return parsed;
  }

  private parseCodeBlock(lines: SourceLine[], startIndex: number, forceFinalize: boolean,
    scanStartOffset: number): ParsedReplyBlock {
    const first: SourceLine = lines[startIndex];
    let closeIndex: number = -1;
    let cursor: number = startIndex + 1;
    if (scanStartOffset > first.startOffset) {
      cursor = Math.max(cursor, this.lineIndexAtOrAfter(lines, scanStartOffset));
    }
    while (cursor < lines.length) {
      if (isCodeFence(lines[cursor].text)) {
        closeIndex = cursor;
        break;
      }
      cursor += 1;
    }
    const lastIndex: number = closeIndex >= 0 ? closeIndex : lines.length - 1;
    const endOffset: number = lines[lastIndex].endOffset;
    const raw: string = this.rawBody_.substring(first.startOffset, endOffset);
    const result: ParsedReplyBlock = new ParsedReplyBlock('code', first.startOffset, endOffset, raw);
    result.phase = closeIndex >= 0 || forceFinalize ? 'sealed' : 'open';
    result.renderText = this.codeBody(raw, closeIndex >= 0);
    result.stablePrefixLen = raw.length;
    result.estimatedHeight = this.estimateHeight(result.renderText, 18);
    result.renderedHeight = result.estimatedHeight;
    return result;
  }

  private parseFormulaBlock(lines: SourceLine[], startIndex: number, forceFinalize: boolean,
    scanStartOffset: number): ParsedReplyBlock {
    const first: SourceLine = lines[startIndex];
    const opener: string = trimLine(first.text);
    let closeIndex: number = -1;
    let cursor: number = startIndex + 1;
    if (scanStartOffset > first.startOffset) {
      cursor = Math.max(cursor, this.lineIndexAtOrAfter(lines, scanStartOffset));
    }
    while (cursor < lines.length) {
      if (isFormulaClose(lines[cursor].text, opener)) {
        closeIndex = cursor;
        break;
      }
      cursor += 1;
    }
    const lastIndex: number = closeIndex >= 0 ? closeIndex : lines.length - 1;
    const endOffset: number = lines[lastIndex].endOffset;
    const raw: string = this.rawBody_.substring(first.startOffset, endOffset);
    const result: ParsedReplyBlock = new ParsedReplyBlock('formula', first.startOffset, endOffset, raw);
    result.formulaClosed = closeIndex >= 0;
    result.phase = closeIndex >= 0 || forceFinalize ? 'sealed' : 'open';
    result.renderText = this.formulaBody(raw, opener, result.formulaClosed);
    result.formulaSlotId = blockIdFor(this.messageId_, first.startOffset) + ':formula';
    result.placeholderText = FORMULA_PLACEHOLDER_PREFIX + capFormulaText(result.renderText);
    result.pendingRenderWork = result.formulaClosed;
    result.estimatedHeight = FORMULA_ESTIMATED_HEIGHT;
    result.renderedHeight = result.formulaClosed ? 0 : result.estimatedHeight;
    result.stablePrefixLen = raw.length;
    return result;
  }

  private parseHeadingBlock(line: SourceLine, level: number, forceFinalize: boolean): ParsedReplyBlock {
    const raw: string = this.rawBody_.substring(line.startOffset, line.endOffset);
    const trimmed: string = trimLine(line.text);
    const title: string = trimmed.substring(level + 1).trim();
    const result: ParsedReplyBlock = new ParsedReplyBlock('heading', line.startOffset, line.endOffset, raw);
    result.renderText = title;
    result.phase = (line.complete || forceFinalize) && !hasUnclosedInlineMarker(title) ? 'sealed' : 'open';
    if (forceFinalize && hasUnclosedInlineMarker(title)) {
      result.kind = 'fallback';
      result.renderText = escapePlainText(title);
      result.phase = 'sealed';
    }
    result.stablePrefixLen = result.phase === 'open' ? this.stablePrefixForRaw(raw) : raw.length;
    result.estimatedHeight = this.estimateHeight(result.renderText, 24);
    result.renderedHeight = result.estimatedHeight;
    result.inlineFormulaSlots = this.extractInlineFormulaSlots(result.rawText, result.startOffset,
      blockIdFor(this.messageId_, result.startOffset));
    return result;
  }

  private parseQuoteBlock(lines: SourceLine[], startIndex: number, forceFinalize: boolean): ParsedReplyBlock {
    const first: SourceLine = lines[startIndex];
    const values: string[] = [];
    let cursor: number = startIndex;
    let endOffset: number = first.endOffset;
    let sealed: boolean = false;
    while (cursor < lines.length && isQuote(lines[cursor].text)) {
      values.push(stripQuote(lines[cursor].text));
      endOffset = lines[cursor].endOffset;
      if (!lines[cursor].complete) {
        break;
      }
      cursor += 1;
    }
    if (cursor < lines.length && isBlankLine(lines[cursor])) {
      endOffset = lines[cursor].endOffset;
      sealed = true;
    } else if (cursor < lines.length && !isQuote(lines[cursor].text)) {
      sealed = true;
    } else if (forceFinalize) {
      sealed = true;
    }
    const raw: string = this.rawBody_.substring(first.startOffset, endOffset);
    const result: ParsedReplyBlock = new ParsedReplyBlock('quote', first.startOffset, endOffset, raw);
    result.renderText = values.join('\n');
    const hasOpenMarker: boolean = hasUnclosedInlineMarker(result.renderText);
    result.phase = sealed && !hasOpenMarker ? 'sealed' : 'open';
    if (forceFinalize && hasOpenMarker) {
      result.kind = 'fallback';
      result.renderText = escapePlainText(result.renderText);
      result.phase = 'sealed';
    }
    result.stablePrefixLen = result.phase === 'open' ? this.stablePrefixForRaw(raw) : raw.length;
    result.estimatedHeight = this.estimateHeight(result.renderText, 20);
    result.renderedHeight = result.estimatedHeight;
    result.inlineFormulaSlots = this.extractInlineFormulaSlots(result.rawText, result.startOffset,
      blockIdFor(this.messageId_, result.startOffset));
    return result;
  }

  private parseListBlock(lines: SourceLine[], startIndex: number, forceFinalize: boolean): ParsedReplyBlock {
    const first: SourceLine = lines[startIndex];
    const values: string[] = [];
    const ordered: boolean = listIsOrdered(first.text);
    let cursor: number = startIndex;
    let endOffset: number = first.endOffset;
    let sealed: boolean = false;
    while (cursor < lines.length && listItemText(lines[cursor].text).length > 0
      && listIsOrdered(lines[cursor].text) === ordered) {
      values.push(listItemText(lines[cursor].text));
      endOffset = lines[cursor].endOffset;
      if (!lines[cursor].complete) {
        break;
      }
      cursor += 1;
    }
    if (cursor < lines.length && isBlankLine(lines[cursor])) {
      endOffset = lines[cursor].endOffset;
      sealed = true;
    } else if (cursor < lines.length && listItemText(lines[cursor].text).length === 0) {
      sealed = true;
    } else if (forceFinalize) {
      sealed = true;
    }
    const raw: string = this.rawBody_.substring(first.startOffset, endOffset);
    const result: ParsedReplyBlock = new ParsedReplyBlock('list', first.startOffset, endOffset, raw);
    result.renderText = values.join('\n');
    const hasOpenMarker: boolean = hasUnclosedInlineMarker(result.renderText);
    result.phase = sealed && !hasOpenMarker ? 'sealed' : 'open';
    if (forceFinalize && hasOpenMarker) {
      result.kind = 'fallback';
      result.renderText = escapePlainText(result.renderText);
      result.phase = 'sealed';
    }
    result.stablePrefixLen = result.phase === 'open' ? this.stablePrefixForRaw(raw) : raw.length;
    result.estimatedHeight = this.estimateHeight(result.renderText, 20);
    result.renderedHeight = result.estimatedHeight;
    result.inlineFormulaSlots = this.extractInlineFormulaSlots(result.rawText, result.startOffset,
      blockIdFor(this.messageId_, result.startOffset));
    return result;
  }

  private parseParagraphOrFallback(lines: SourceLine[], startIndex: number, forceFinalize: boolean): ParsedReplyBlock {
    const first: SourceLine = lines[startIndex];
    const fallback: boolean = isUnsupportedSyntax(first.text);
    if (fallback) {
      const raw: string = this.rawBody_.substring(first.startOffset, first.endOffset);
      const result: ParsedReplyBlock = new ParsedReplyBlock('fallback', first.startOffset, first.endOffset, raw);
      result.renderText = escapePlainText(stripTrailingLineBreaks(raw).trim());
      result.phase = first.complete || forceFinalize ? 'sealed' : 'open';
      result.stablePrefixLen = result.phase === 'open' ? this.stablePrefixForRaw(raw) : raw.length;
      result.estimatedHeight = this.estimateHeight(result.renderText, 20);
      result.renderedHeight = result.estimatedHeight;
      return result;
    }

    const values: string[] = [];
    let cursor: number = startIndex;
    let endOffset: number = first.endOffset;
    let sealed: boolean = false;
    while (cursor < lines.length) {
      const current: SourceLine = lines[cursor];
      if (isBlankLine(current)) {
        endOffset = current.endOffset;
        const hasOpenMarker: boolean = hasUnclosedInlineMarker(values.join('\n'));
        values.push('');
        if (!hasOpenMarker || forceFinalize) {
          sealed = true;
          if (forceFinalize && hasUnclosedInlineMarker(values.join('\n'))) {
            break;
          }
          break;
        }
        cursor += 1;
        continue;
      }
      if (cursor > startIndex && (isCodeFence(current.text) || isFormulaFence(current.text)
        || headingLevel(current.text) > 0 || isQuote(current.text) || listItemText(current.text).length > 0
        || isRule(current.text) || isUnsupportedSyntax(current.text))) {
        if (!hasUnclosedInlineMarker(values.join('\n')) || forceFinalize) {
          sealed = true;
        }
        break;
      }
      values.push(current.text);
      endOffset = current.endOffset;
      if (!current.complete) {
        break;
      }
      cursor += 1;
    }
    if (forceFinalize) {
      sealed = true;
    }
    const raw: string = this.rawBody_.substring(first.startOffset, endOffset);
    const result: ParsedReplyBlock = new ParsedReplyBlock('paragraph', first.startOffset, endOffset, raw);
    result.renderText = stripTrailingLineBreaks(values.join('\n')).trim();
    result.phase = sealed ? 'sealed' : 'open';
    if (forceFinalize && hasUnclosedInlineMarker(result.renderText)) {
      result.kind = 'fallback';
      result.renderText = escapePlainText(result.renderText);
    }
    result.stablePrefixLen = result.phase === 'open' ? this.stablePrefixForRaw(raw) : raw.length;
    result.estimatedHeight = this.estimateHeight(result.renderText, 20);
    result.renderedHeight = result.estimatedHeight;
    result.inlineFormulaSlots = this.extractInlineFormulaSlots(result.rawText, result.startOffset,
      blockIdFor(this.messageId_, result.startOffset));
    return result;
  }

  private nextIndexAfterBlock(lines: SourceLine[], startIndex: number, block: ParsedReplyBlock): number {
    let index: number = startIndex;
    while (index < lines.length && lines[index].endOffset <= block.endOffset) {
      index += 1;
    }
    return index;
  }

  private codeBody(raw: string, closed: boolean): string {
    const firstNewline: number = raw.indexOf('\n');
    if (firstNewline < 0) {
      return '';
    }
    const bodyStart: number = firstNewline + 1;
    if (!closed) {
      return raw.substring(bodyStart);
    }
    let closeLineEnd: number = raw.length;
    if (closeLineEnd > bodyStart && raw.charAt(closeLineEnd - 1) === '\n') {
      closeLineEnd -= 1;
    }
    if (closeLineEnd > bodyStart && raw.charAt(closeLineEnd - 1) === '\r') {
      closeLineEnd -= 1;
    }
    const closeLineStart: number = raw.lastIndexOf('\n', closeLineEnd - 1) + 1;
    return closeLineStart > bodyStart ? raw.substring(bodyStart, closeLineStart) : '';
  }

  private formulaBody(raw: string, opener: string, closed: boolean): string {
    let body: string = raw.substring(opener.length);
    if (closed) {
      const closeMarker: string = opener === '$$' ? '$$' : '\\]';
      const closeIndex: number = body.lastIndexOf(closeMarker);
      if (closeIndex >= 0) {
        body = body.substring(0, closeIndex);
      }
    }
    return this.normalizeDisplayFormulaBody(body);
  }

  private normalizeDisplayFormulaBody(body: string): string {
    const validation: ContentValidationResult = this.contentProtocol_.normalizeDisplayFormula(body);
    const normalized: string = validation.normalizedText;
    const lines: string[] = normalized.split('\n');
    if (lines.length >= 2 && lines[0].trim() === '$$' && lines[lines.length - 1].trim() === '$$') {
      const bodyLines: string[] = [];
      let index: number = 1;
      while (index < lines.length - 1) {
        bodyLines.push(lines[index]);
        index += 1;
      }
      return bodyLines.join('\n').trim();
    }
    return normalized.trim();
  }

  private normalizeInlineFormulaBody(body: string): string {
    const validation: ContentValidationResult = this.contentProtocol_.normalizeNoteMarkdown('$' + body + '$');
    const normalized: string = validation.normalizedText;
    if (normalized.length >= 2 && normalized.charAt(0) === '$' && normalized.charAt(normalized.length - 1) === '$') {
      return normalized.substring(1, normalized.length - 1);
    }
    return body.trim();
  }

  private estimateHeight(text: string, lineHeight: number): number {
    const lines: string[] = text.length === 0 ? [''] : text.split('\n');
    let total: number = 0;
    for (const line of lines) {
      total += Math.max(1, Math.ceil(line.length / 36)) * lineHeight;
    }
    return Math.max(lineHeight, total);
  }

  private extractInlineFormulaSlots(text: string, rawStartOffset: number, blockId: string): InlineFormulaSlotSnapshot[] {
    const slots: InlineFormulaSlotSnapshot[] = [];
    let cursor: number = 0;
    let codeOpen: boolean = false;
    while (cursor < text.length) {
      const current: string = text.charAt(cursor);
      if (current === '`' && !isEscaped(text, cursor)) {
        codeOpen = !codeOpen;
        cursor += 1;
        continue;
      }
      if (codeOpen || current !== '$' || isEscaped(text, cursor)
        || (cursor + 1 < text.length && text.charAt(cursor + 1) === '$')) {
        cursor += 1;
        continue;
      }
      const close: number = this.nextInlineDollar(text, cursor + 1);
      const closed: boolean = close >= 0;
      const bodyEnd: number = closed ? close : text.length;
      const body: string = text.substring(cursor + 1, bodyEnd);
      const renderBody: string = this.normalizeInlineFormulaBody(body);
      const slotId: string = blockId + ':inline-' + (rawStartOffset + cursor).toString();
      const existingWidth: number | undefined = this.inlineSlotWidths_.get(slotId);
      const width: number = existingWidth === undefined ? estimateInlineFormulaWidth(renderBody) : existingWidth;
      if (existingWidth === undefined) {
        this.inlineSlotWidths_.set(slotId, width);
      }
      const wasClosed: boolean = this.inlineSlotClosed_.get(slotId) ?? false;
      let finalWidth: number = width;
      if (closed && !wasClosed) {
        finalWidth = estimateInlineFormulaWidth(renderBody);
        this.inlineSlotWidths_.set(slotId, finalWidth);
        this.inlineSlotClosed_.set(slotId, true);
      }
      const previousUpdates: number = this.inlineSlotUpdates_.get(slotId) ?? 0;
      const updateCount: number = previousUpdates + 1;
      this.inlineSlotUpdates_.set(slotId, updateCount);
      const slot: InlineFormulaSlotSnapshot = {
        slotId: slotId,
        rawStartOffset: rawStartOffset + cursor,
        rawText: body,
        placeholderText: closed ? renderBody : FORMULA_PLACEHOLDER_PREFIX + capFormulaText(renderBody),
        widthVp: finalWidth,
        widthStable: !closed || wasClosed,
        closed: closed,
        updateCount: updateCount,
        renderBackend: 'custom_span',
      };
      slots.push(slot);
      cursor = closed ? close + 1 : text.length;
    }
    return slots;
  }

  private nextInlineDollar(text: string, start: number): number {
    let index: number = text.indexOf('$', start);
    while (index >= 0) {
      if (!isEscaped(text, index) && (index + 1 >= text.length || text.charAt(index + 1) !== '$')) {
        return index;
      }
      index = text.indexOf('$', index + 1);
    }
    return -1;
  }

  private internalFromParsed(parsed: ParsedReplyBlock, blockId: string, parseCount: number,
    previous: InternalReplyBlock | undefined): InternalReplyBlock {
    if (previous !== undefined && parsed.kind === 'formula' && parsed.formulaSlotId.length === 0) {
      parsed.formulaSlotId = previous.formulaSlotId;
    }
    return new InternalReplyBlock(this.messageId_, parsed, blockId, parseCount);
  }

  private makePatch(block: InternalReplyBlock, patchType: BlockPatchType, reason: string): BlockPatch {
    const patch: BlockPatch = {
      patchType: patchType,
      reason: reason,
      block: this.snapshotOf(block),
      dirtyStart: block.startOffset + block.stablePrefixLen,
      dirtyEnd: block.endOffset,
    };
    return patch;
  }

  private snapshotOf(block: InternalReplyBlock): ReplyBlockSnapshot {
    const ids: string[] = [];
    for (const slot of block.inlineFormulaSlots) {
      ids.push(slot.slotId);
    }
    const snapshot: ReplyBlockSnapshot = {
      blockId: block.blockId,
      messageId: block.messageId,
      startOffset: block.startOffset,
      endOffset: block.endOffset,
      rawText: block.rawText,
      renderText: block.renderText,
      kind: block.kind,
      phase: block.phase,
      stablePrefixLen: block.stablePrefixLen,
      parseCount: block.parseCount,
      renderBackend: block.renderBackend,
      formulaSlotId: block.formulaSlotId,
      inlineFormulaSlotIds: ids,
      inlineFormulaSlots: copyInlineFormulaSlots(block.inlineFormulaSlots),
      placeholderText: block.placeholderText,
      pendingRenderWork: block.pendingRenderWork,
      estimatedHeight: block.estimatedHeight,
      renderedHeight: block.renderedHeight,
    };
    return snapshot;
  }

  private findInternalBlock(blockId: string): InternalReplyBlock | undefined {
    for (const block of this.sealedBlocks_) {
      if (block.blockId === blockId) {
        return block;
      }
    }
    if (this.openTail_ !== undefined && this.openTail_.blockId === blockId) {
      return this.openTail_;
    }
    return undefined;
  }

  private removeBlockById(blocks: InternalReplyBlock[], blockId: string): void {
    let index: number = blocks.length - 1;
    while (index >= 0) {
      if (blocks[index].blockId === blockId) {
        blocks.splice(index, 1);
      }
      index -= 1;
    }
  }

  private totalHeight(): number {
    let total: number = 0;
    for (const block of this.sealedBlocks_) {
      total += this.effectiveHeight(block);
    }
    if (this.openTail_ !== undefined) {
      total += this.effectiveHeight(this.openTail_);
    }
    return total;
  }

  private effectiveHeight(block: InternalReplyBlock): number {
    if (block.renderedHeight > 0) {
      return block.renderedHeight;
    }
    if (block.pendingRenderWork || (block.kind === 'formula' && block.phase === 'open')) {
      return block.estimatedHeight;
    }
    return 0;
  }

  private isAllBlocksSettled(): boolean {
    if (!this.finalized_) {
      return false;
    }
    if (!this.schedulerQueueEmpty_) {
      return false;
    }
    const blocks: InternalReplyBlock[] = this.sealedBlocks_.slice();
    if (this.openTail_ !== undefined) {
      blocks.push(this.openTail_);
    }
    for (const block of blocks) {
      if (block.pendingRenderWork) {
        return false;
      }
      if (this.effectiveHeight(block) <= 0) {
        return false;
      }
    }
    return true;
  }

  private stablePrefixForRaw(raw: string): number {
    const markerIndex: number = firstUnclosedMarker(raw);
    return markerIndex >= 0 ? markerIndex : raw.length;
  }

  private lineIndexAtOrAfter(lines: SourceLine[], offset: number): number {
    let index: number = 0;
    while (index < lines.length && lines[index].endOffset <= offset) {
      index += 1;
    }
    return index;
  }

  private hasPendingRenderWork(): boolean {
    for (const block of this.sealedBlocks_) {
      if (block.pendingRenderWork) {
        return true;
      }
    }
    if (this.openTail_ !== undefined && this.openTail_.pendingRenderWork) {
      return true;
    }
    return false;
  }
}
