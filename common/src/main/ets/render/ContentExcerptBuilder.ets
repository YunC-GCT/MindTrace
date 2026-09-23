/**
 * ContentExcerptBuilder.ets - protocol-aware note summary and list preview builder
 *
 * Path: common/src/main/ets/render/ContentExcerptBuilder.ets
 * Responsibility: Build compact excerpts without cutting Markdown or LaTeX boundaries.
 * Dependencies: ContentProtocol
 *
 * Data flow:
 *   persisted/AI Markdown -> ContentProtocol -> compact safe excerpt -> ArkUI/KaTeX preview
 *
 * ArkTS 1.1 strict adaptation:
 *   - Uses explicit state and while/for...of traversal.
 *   - Does not use any/unknown values or C-style for loops.
 */

import { ContentProtocol } from './ContentProtocol';
import type { ContentValidationResult } from './ContentProtocol';

const LIST_INLINE_MATH_LIMIT: number = 34;
const LIST_FORMULA_EXTENSION: number = 28;
export const NOTE_SUMMARY_MAX_LENGTH: number = 60;

export class ContentExcerptBuilder {
  private contentProtocol: ContentProtocol = new ContentProtocol();

  buildSummary(rawText: string, maxChars: number = NOTE_SUMMARY_MAX_LENGTH): string {
    if (maxChars <= 0) {
      return '';
    }
    const normalized: string = this.canonicalText(rawText);
    const parts: string[] = [];
    let inCode: boolean = false;
    let inDisplay: boolean = false;
    for (const rawLine of normalized.split('\n')) {
      const trimmed: string = rawLine.trim();
      if (trimmed.indexOf('```') === 0) {
        inCode = !inCode;
        continue;
      }
      if (inCode) {
        continue;
      }
      if (trimmed === '$$') {
        inDisplay = !inDisplay;
        continue;
      }
      if (inDisplay || trimmed.length === 0 || this.isHeading(trimmed) || this.isRule(trimmed)) {
        continue;
      }
      const cleaned: string = this.cleanMarkdownLine(trimmed);
      if (cleaned.length > 0) {
        this.appendUniquePart(parts, cleaned);
        if (parts.join('；').length >= maxChars) {
          break;
        }
      }
    }
    return this.clipSummaryInlineAware(parts.join('；'), maxChars);
  }

  buildListPreview(rawText: string, maxChars: number = 46): string {
    if (maxChars <= 0) {
      return '';
    }
    const normalized: string = this.canonicalText(rawText);
    const formulaLines: string[] = [];
    let inCode: boolean = false;
    let inDisplay: boolean = false;
    let displayPreview: string = '';
    for (const rawLine of normalized.split('\n')) {
      const trimmed: string = rawLine.trim();
      if (trimmed.indexOf('```') === 0) {
        inCode = !inCode;
        continue;
      }
      if (inCode) {
        continue;
      }
      if (inDisplay) {
        if (trimmed === '$$') {
          if (displayPreview.length === 0) {
            displayPreview = this.displayPreview(formulaLines.join('\n'), maxChars);
          }
          formulaLines.splice(0, formulaLines.length);
          inDisplay = false;
        } else {
          formulaLines.push(rawLine);
        }
        continue;
      }
      if (trimmed === '$$') {
        inDisplay = true;
        continue;
      }
      if (trimmed.length === 0 || this.isHeading(trimmed) || this.isRule(trimmed)) {
        continue;
      }
      const cleaned: string = this.cleanMarkdownLine(trimmed);
      if (cleaned.length > 0) {
        const compact: string = this.replaceLongInlineMath(cleaned, LIST_INLINE_MATH_LIMIT);
        const preview: string = this.clipInlineAware(compact, maxChars, maxChars + LIST_FORMULA_EXTENSION);
        if (preview.length > 0) {
          return preview;
        }
      }
    }
    return displayPreview;
  }

  buildPlainSummary(rawText: string, maxChars: number = 220): string {
    if (maxChars <= 0) {
      return '';
    }
    const normalized: string = this.canonicalText(rawText);
    const parts: string[] = [];
    let inCode: boolean = false;
    let inDisplay: boolean = false;
    for (const rawLine of normalized.split('\n')) {
      const trimmed: string = rawLine.trim();
      if (trimmed.indexOf('```') === 0) {
        inCode = !inCode;
        continue;
      }
      if (inCode) {
        continue;
      }
      if (trimmed === '$$') {
        if (inDisplay) {
          this.appendUniquePart(parts, '核心公式');
        }
        inDisplay = !inDisplay;
        continue;
      }
      if (inDisplay || trimmed.length === 0 || this.isHeading(trimmed) || this.isRule(trimmed)) {
        continue;
      }
      const cleaned: string = this.cleanMarkdownLine(trimmed);
      if (cleaned.length > 0) {
        this.appendUniquePart(parts, this.replaceLongInlineMath(cleaned, 0));
      }
      if (parts.join('；').length >= maxChars + LIST_FORMULA_EXTENSION) {
        break;
      }
    }
    const summary: string = parts.join('；');
    return this.clipInlineAware(summary, maxChars, maxChars + LIST_FORMULA_EXTENSION);
  }

  private canonicalText(rawText: string): string {
    const result: ContentValidationResult = this.contentProtocol.normalizeNoteMarkdown(rawText);
    if (result.normalizedText.length > 0) {
      return result.normalizedText;
    }
    return rawText.replace(/\r\n/g, '\n').replace(/\r/g, '\n').trim();
  }

  private displayPreview(formulaBody: string, maxChars: number): string {
    const formula: string = formulaBody.trim();
    if (formula.length === 0) {
      return '';
    }
    const display: string = '$$\n' + formula + '\n$$';
    if (display.length <= maxChars + LIST_FORMULA_EXTENSION) {
      return display;
    }
    return '核心公式';
  }

  private cleanMarkdownLine(line: string): string {
    let result: string = line.trim();
    result = result.replace(/^>\s*/, '');
    result = result.replace(/^[-*+]\s+/, '');
    result = result.replace(/^\d+[.)、]\s*/, '');
    result = result.replace(/\*\*/g, '');
    result = result.replace(/__/g, '');
    result = result.replace(/`/g, '');
    return result.replace(/\s+/g, ' ').trim();
  }

  private replaceLongInlineMath(text: string, mathLimit: number): string {
    let output: string = '';
    let cursor: number = 0;
    let openIndex: number = this.nextUnescapedDollar(text, cursor);
    while (openIndex >= 0) {
      const closeIndex: number = this.nextUnescapedDollar(text, openIndex + 1);
      output += text.substring(cursor, openIndex);
      if (closeIndex < 0) {
        return output.trim();
      }
      const formula: string = text.substring(openIndex, closeIndex + 1);
      output += formula.length <= mathLimit ? formula : '相应公式';
      cursor = closeIndex + 1;
      openIndex = this.nextUnescapedDollar(text, cursor);
    }
    output += text.substring(cursor);
    return output.replace(/\s+/g, ' ').trim();
  }

  private clipInlineAware(text: string, maxChars: number, formulaLimit: number): string {
    const normalized: string = text.trim();
    if (normalized.length <= maxChars) {
      return normalized;
    }
    let openIndex: number = this.nextUnescapedDollar(normalized, 0);
    while (openIndex >= 0) {
      const closeIndex: number = this.nextUnescapedDollar(normalized, openIndex + 1);
      if (closeIndex < 0) {
        return this.withEllipsis(this.clipPlain(normalized.substring(0, openIndex), maxChars));
      }
      if (openIndex < maxChars && closeIndex >= maxChars) {
        if (closeIndex + 1 <= formulaLimit) {
          return this.withEllipsis(normalized.substring(0, closeIndex + 1));
        }
        return this.withEllipsis(this.clipPlain(normalized.substring(0, openIndex), maxChars));
      }
      openIndex = this.nextUnescapedDollar(normalized, closeIndex + 1);
    }
    return this.withEllipsis(this.clipPlain(normalized, maxChars));
  }

  private clipSummaryInlineAware(text: string, maxChars: number): string {
    const normalized: string = text.trim();
    if (normalized.length <= maxChars) {
      return normalized;
    }
    const contentLimit: number = Math.max(0, maxChars - 1);
    let openIndex: number = this.nextUnescapedDollar(normalized, 0);
    while (openIndex >= 0) {
      const closeIndex: number = this.nextUnescapedDollar(normalized, openIndex + 1);
      if (closeIndex < 0) {
        return this.withSummaryEllipsis(this.clipPlain(normalized.substring(0, openIndex), contentLimit), maxChars);
      }
      if (openIndex < contentLimit && closeIndex + 1 > contentLimit) {
        return this.withSummaryEllipsis(this.clipPlain(normalized.substring(0, openIndex), contentLimit), maxChars);
      }
      openIndex = this.nextUnescapedDollar(normalized, closeIndex + 1);
    }
    return this.withSummaryEllipsis(this.clipPlain(normalized, contentLimit), maxChars);
  }

  private clipPlain(text: string, maxChars: number): string {
    if (text.length <= maxChars) {
      return text.trim();
    }
    const minimum: number = Math.max(1, Math.floor(maxChars * 0.58));
    let endIndex: number = maxChars;
    while (endIndex > minimum && !this.isTextBoundary(text.charAt(endIndex - 1))) {
      endIndex -= 1;
    }
    if (endIndex <= minimum) {
      endIndex = maxChars;
    }
    return text.substring(0, endIndex).replace(/[\s，、：；,:;-]+$/g, '').trim();
  }

  private withEllipsis(text: string): string {
    const trimmed: string = text.trim();
    if (trimmed.length === 0 || trimmed.endsWith('…')) {
      return trimmed;
    }
    return trimmed + '…';
  }

  private withSummaryEllipsis(text: string, maxChars: number): string {
    const trimmed: string = text.trim();
    if (trimmed.length === 0 || maxChars <= 0) {
      return trimmed;
    }
    if (trimmed.length >= maxChars) {
      return trimmed.substring(0, maxChars - 1).trim() + '…';
    }
    return trimmed + '…';
  }

  private isTextBoundary(char: string): boolean {
    return char === ' ' || char === '，' || char === '。' || char === '；'
      || char === '：' || char === ',' || char === ';' || char === ':';
  }

  private isHeading(text: string): boolean {
    return /^#{1,6}\s+/.test(text);
  }

  private isRule(text: string): boolean {
    return text === '---' || text === '***' || text === '___';
  }

  private nextUnescapedDollar(text: string, start: number): number {
    let index: number = text.indexOf('$', start);
    while (index >= 0) {
      if (!this.isEscapedAt(text, index)) {
        return index;
      }
      index = text.indexOf('$', index + 1);
    }
    return -1;
  }

  private isEscapedAt(text: string, index: number): boolean {
    let slashCount: number = 0;
    let slashIndex: number = index - 1;
    while (slashIndex >= 0 && text.charAt(slashIndex) === '\\') {
      slashCount += 1;
      slashIndex -= 1;
    }
    return slashCount % 2 !== 0;
  }

  private appendUniquePart(parts: string[], value: string): void {
    const text: string = value.trim();
    if (text.length > 0 && parts.indexOf(text) < 0) {
      parts.push(text);
    }
  }
}
