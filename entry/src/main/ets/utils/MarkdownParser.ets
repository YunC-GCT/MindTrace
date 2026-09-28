// ============================================================================
//  utils/MarkdownParser.ets - lightweight markdown block parser
// ============================================================================

import { ContentProtocol } from 'common'

const MARKDOWN_TEXT_BLOCK_LIMIT: number = 700

export interface MarkdownBlock {
  kind: string
  text: string
  level: number
  items: string[]
  ordered: boolean
  lang: string
}

function emptyBlock(kind: string): MarkdownBlock {
  return {
    kind: kind,
    text: '',
    level: 0,
    items: [],
    ordered: false,
    lang: '',
  }
}

function isEscaped(text: string, index: number): boolean {
  let slashCount: number = 0
  let cursor: number = index - 1
  while (cursor >= 0 && text.charAt(cursor) === '\\') {
    slashCount += 1
    cursor -= 1
  }
  return slashCount % 2 === 1
}

function isReadableBreak(ch: string): boolean {
  return ch === '\n' || ch === ' ' || ch === '\t'
    || ch === '。' || ch === '！' || ch === '？' || ch === '；'
    || ch === '.' || ch === '!' || ch === '?' || ch === ';'
}

function splitLongReadableText(text: string): string[] {
  if (text.length <= MARKDOWN_TEXT_BLOCK_LIMIT) {
    return [text]
  }
  const chunks: string[] = []
  let start: number = 0
  let index: number = 0
  let safeBreak: number = -1
  let inDollarFormula: boolean = false
  let inParenFormula: boolean = false
  let inBracketFormula: boolean = false
  let inInlineCode: boolean = false
  while (index < text.length) {
    const ch: string = text.charAt(index)
    const next: string = index + 1 < text.length ? text.charAt(index + 1) : ''
    if (ch === '`' && !isEscaped(text, index)) {
      inInlineCode = !inInlineCode
    } else if (!inInlineCode && ch === '$' && next === '$' && !isEscaped(text, index)) {
      inDollarFormula = !inDollarFormula
      index += 1
    } else if (!inInlineCode && ch === '$' && !isEscaped(text, index)) {
      inDollarFormula = !inDollarFormula
    } else if (!inInlineCode && ch === '\\' && next === '(' && !isEscaped(text, index)) {
      inParenFormula = true
      index += 1
    } else if (!inInlineCode && ch === '\\' && next === ')' && !isEscaped(text, index)) {
      inParenFormula = false
      index += 1
    } else if (!inInlineCode && ch === '\\' && next === '[' && !isEscaped(text, index)) {
      inBracketFormula = true
      index += 1
    } else if (!inInlineCode && ch === '\\' && next === ']' && !isEscaped(text, index)) {
      inBracketFormula = false
      index += 1
    }
    const outsideFormula: boolean = !inInlineCode
      && !inDollarFormula && !inParenFormula && !inBracketFormula
    if (outsideFormula && isReadableBreak(ch)) {
      safeBreak = index + 1
    }
    if (outsideFormula && index - start + 1 >= MARKDOWN_TEXT_BLOCK_LIMIT && safeBreak > start) {
      const chunk: string = text.substring(start, safeBreak).trim()
      if (chunk.length > 0) {
        chunks.push(chunk)
      }
      start = safeBreak
      safeBreak = -1
    }
    index += 1
  }
  const tail: string = text.substring(start).trim()
  if (tail.length > 0) {
    chunks.push(tail)
  }
  return chunks.length > 0 ? chunks : [text]
}

function pushTextBlocks(blocks: MarkdownBlock[], kind: string, text: string): void {
  for (const chunk of splitLongReadableText(text)) {
    const block: MarkdownBlock = emptyBlock(kind)
    block.text = chunk
    blocks.push(block)
  }
}

function pushParagraph(blocks: MarkdownBlock[], lines: string[]): void {
  const text: string = lines.join('\n').trim()
  if (text.length > 0) {
    pushTextBlocks(blocks, 'paragraph', text)
  }
  lines.splice(0, lines.length)
}

function pushQuote(blocks: MarkdownBlock[], lines: string[]): void {
  const text: string = lines.join('\n').trim()
  if (text.length > 0) {
    pushTextBlocks(blocks, 'quote', text)
  }
  lines.splice(0, lines.length)
}

function pushList(blocks: MarkdownBlock[], items: string[], ordered: boolean): void {
  if (items.length > 0) {
    const block: MarkdownBlock = emptyBlock('list')
    block.items = items.slice()
    block.ordered = ordered
    blocks.push(block)
  }
  items.splice(0, items.length)
}

function pushCode(blocks: MarkdownBlock[], lines: string[], lang: string): void {
  const block: MarkdownBlock = emptyBlock('code')
  block.text = lines.join('\n')
  block.lang = lang
  blocks.push(block)
  lines.splice(0, lines.length)
}

function headingLevel(line: string): number {
  let count: number = 0
  while (count < line.length && line.charAt(count) === '#') {
    count += 1
  }
  if (count < 1 || count > 3 || line.charAt(count) !== ' ') {
    return 0
  }
  return count
}

function unorderedItemText(line: string): string {
  if (line.length > 2) {
    const marker: string = line.charAt(0)
    if ((marker === '-' || marker === '*' || marker === '+') && line.charAt(1) === ' ') {
      return line.substring(2).trim()
    }
  }
  return ''
}

function orderedItemText(line: string): string {
  let index: number = 0
  while (index < line.length && line.charAt(index) >= '0' && line.charAt(index) <= '9') {
    index += 1
  }
  if (index > 0 && index + 1 < line.length && line.charAt(index) === '.' && line.charAt(index + 1) === ' ') {
    return line.substring(index + 2).trim()
  }
  return ''
}

function isRule(line: string): boolean {
  return line === '---' || line === '***' || line === '___'
}

function isFormulaFence(line: string): boolean {
  return line === '$$' || line === '\\['
}

function isFormulaClose(line: string, fence: string): boolean {
  return fence === '$$' && line === '$$' || fence === '\\[' && line === '\\]'
}

function flushOpenBlocks(
  blocks: MarkdownBlock[],
  paragraphLines: string[],
  quoteLines: string[],
  listItems: string[],
  listOrdered: boolean,
): void {
  pushParagraph(blocks, paragraphLines)
  pushQuote(blocks, quoteLines)
  pushList(blocks, listItems, listOrdered)
}

export function parseMarkdown(text: string): MarkdownBlock[] {
  const normalized: string = new ContentProtocol().normalizeNoteMarkdown(text).normalizedText
  if (normalized.length === 0) {
    return []
  }

  const blocks: MarkdownBlock[] = []
  const lines: string[] = normalized.split('\n')
  const paragraphLines: string[] = []
  const quoteLines: string[] = []
  const listItems: string[] = []
  const codeLines: string[] = []
  const formulaLines: string[] = []
  let listOrdered: boolean = false
  let inCode: boolean = false
  let inFormula: boolean = false
  let codeLang: string = ''
  let formulaFence: string = ''

  for (const rawLine of lines) {
    const line: string = rawLine
    const trimmed: string = rawLine.trim()

    if (inCode) {
      if (trimmed.indexOf('```') === 0) {
        pushCode(blocks, codeLines, codeLang)
        inCode = false
        codeLang = ''
      } else {
        codeLines.push(line)
      }
      continue
    }

    if (inFormula) {
      if (isFormulaClose(trimmed, formulaFence)) {
        const block: MarkdownBlock = emptyBlock('formula')
        block.text = formulaLines.join('\n').trim()
        blocks.push(block)
        formulaLines.splice(0, formulaLines.length)
        inFormula = false
        formulaFence = ''
      } else {
        formulaLines.push(line)
      }
      continue
    }

    if (trimmed.length === 0) {
      // 空行: flush 段落和引用, 但不 flush 列表
      // (Markdown 中空行不应打断列表; 列表项之间常有空行, 打断会导致每项变成独立列表, 序号全部从 1 开始)
      pushParagraph(blocks, paragraphLines)
      pushQuote(blocks, quoteLines)
      continue
    }

    if (trimmed.indexOf('```') === 0) {
      flushOpenBlocks(blocks, paragraphLines, quoteLines, listItems, listOrdered)
      inCode = true
      codeLang = trimmed.length > 3 ? trimmed.substring(3).trim() : ''
      continue
    }

    if (isFormulaFence(trimmed)) {
      flushOpenBlocks(blocks, paragraphLines, quoteLines, listItems, listOrdered)
      inFormula = true
      formulaFence = trimmed
      continue
    }

    if (isRule(trimmed)) {
      flushOpenBlocks(blocks, paragraphLines, quoteLines, listItems, listOrdered)
      blocks.push(emptyBlock('rule'))
      continue
    }

    const level: number = headingLevel(trimmed)
    if (level > 0) {
      flushOpenBlocks(blocks, paragraphLines, quoteLines, listItems, listOrdered)
      const block: MarkdownBlock = emptyBlock('heading')
      block.level = level
      block.text = trimmed.substring(level + 1).trim()
      blocks.push(block)
      continue
    }

    if (trimmed.indexOf('> ') === 0) {
      pushParagraph(blocks, paragraphLines)
      pushList(blocks, listItems, listOrdered)
      quoteLines.push(trimmed.substring(2).trim())
      continue
    }

    const unorderedText: string = unorderedItemText(trimmed)
    if (unorderedText.length > 0) {
      pushParagraph(blocks, paragraphLines)
      pushQuote(blocks, quoteLines)
      if (listItems.length > 0 && listOrdered) {
        pushList(blocks, listItems, listOrdered)
      }
      listOrdered = false
      listItems.push(unorderedText)
      continue
    }

    const orderedText: string = orderedItemText(trimmed)
    if (orderedText.length > 0) {
      pushParagraph(blocks, paragraphLines)
      pushQuote(blocks, quoteLines)
      if (listItems.length > 0 && !listOrdered) {
        pushList(blocks, listItems, listOrdered)
      }
      listOrdered = true
      listItems.push(orderedText)
      continue
    }

    pushQuote(blocks, quoteLines)
    pushList(blocks, listItems, listOrdered)
    paragraphLines.push(line)
  }

  if (inCode) {
    pushCode(blocks, codeLines, codeLang)
  }
  if (inFormula) {
    const block: MarkdownBlock = emptyBlock('paragraph')
    block.text = formulaFence + '\n' + formulaLines.join('\n').trim()
    blocks.push(block)
  }
  flushOpenBlocks(blocks, paragraphLines, quoteLines, listItems, listOrdered)

  return blocks
}
