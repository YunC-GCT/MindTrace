/**
 * FormulaSplitRenderer.ets — 按 $$ 分块渲染公式 + 文本
 *
 * 路径: entry/src/main/ets/shared/molecules/FormulaSplitRenderer.ets
 * 职责: 将含 $$...$$ 的 markdown 文本按公式边界拆分为 Block[],
 *       合并相邻文本块减少 WebView 数量, 每个 Block 用独立的
 *       MathTextRenderer 渲染 (公式块 forceDisplay=true 无上限,
 *       文本块 forceDisplay=false 上限 1800vp)。
 * 依赖: MathTextRenderer, common (TEXT, TEXT_2, F_SM)
 *
 * 数据流:
 *   ChatBubble.text → splitByFormulas() → FormulaBlock[]
 *     → FormulaBlockDataSource → LazyForEach → MathTextRenderer
 *
 * 设计要点:
 *   - 合并 $$ 之间的连续文本段, 减少 ~40% WebView 数量
 *   - block 硬上限 30, 超出截断
 *   - LazyForEach 实现按需创建/销毁, 仅可见 block 持有 WebView
 *   - 公式块无高度上限, 文本块 ≤1800vp
 *
 * ArkTS 1.1 strict 适配:
 *   - splitByFormulas 用 while 循环 (禁 C 风格 for)
 *   - struct 内方法均为箭头函数 (除 @Watch 回调)
 */

import { TEXT, TEXT_2, F_SM, ContentProtocol } from 'common'
import type { ContentValidationResult } from 'common'
import { MathTextRenderer } from '../atoms/MathTextRenderer'

const MAX_TOTAL_BLOCKS: number = 30
const TEXT_BLOCK_CHAR_LIMIT: number = 1500

// ============================================================================
//  FormulaBlock & splitByFormulas
// ============================================================================

/**
 * 一个渲染块 — 要么是纯文本 (含行内 $...$), 要么是 display 公式.
 * key 供 LazyForEach 做稳定标识.
 */
interface FormulaBlock {
  key: string
  type: 'text' | 'formula'
  content: string
}

/**
 * 按 $$ 拆分 markdown, 合并相邻文本块.
 *
 * 算法: split('$$') → 偶数索引=文本(累积), 奇数索引=公式(flush 文本后产出)
 * 每个 block 分配稳定的 key (基于产出顺序递增 id).
 */
function splitByFormulas(markdown: string): FormulaBlock[] {
  const parts: string[] = markdown.split('$$')
  const blocks: FormulaBlock[] = []
  let pendingTexts: string[] = []
  let i: number = 0
  let blockId: number = 0

  while (i < parts.length) {
    const trimmed: string = parts[i].trim()
    if (trimmed.length > 0) {
      if (i % 2 === 0) {
        pendingTexts.push(trimmed)
      } else {
        if (pendingTexts.length > 0) {
          blocks.push({
            key: (blockId++).toString(),
            type: 'text',
            content: pendingTexts.join('\n\n')
          })
          pendingTexts = []
        }
        blocks.push({
          key: (blockId++).toString(),
          type: 'formula',
          content: '$$\n' + trimmed + '\n$$'
        })
      }
    }
    i += 1
  }

  if (pendingTexts.length > 0) {
    blocks.push({
      key: (blockId++).toString(),
      type: 'text',
      content: pendingTexts.join('\n\n')
    })
  }

  if (blocks.length > MAX_TOTAL_BLOCKS) {
    blocks.splice(MAX_TOTAL_BLOCKS)
  }

  return blocks
}

/**
 * 对超长文本块按段落 (\n\n) 二次拆分, 防止单个文本块 >1800vp 被截断.
 * 1500 字符 ≈ chat profile 下约 60-70 视觉行, 对应 ~1700vp, 留 100vp 余量.
 */
function splitLongTextBlocks(blocks: FormulaBlock[]): FormulaBlock[] {
  const result: FormulaBlock[] = []
  let keyId: number = 0
  let index: number = 0

  while (index < blocks.length) {
    const block: FormulaBlock = blocks[index]
    if (block.type === 'formula') {
      block.key = (keyId++).toString()
      result.push(block)
    } else if (block.content.length <= TEXT_BLOCK_CHAR_LIMIT) {
      block.key = (keyId++).toString()
      result.push(block)
    } else {
      // 超长文本: 按段落边界拆分
      const paragraphs: string[] = block.content.split('\n\n')
      let chunk: string = ''
      let paraIndex: number = 0
      while (paraIndex < paragraphs.length) {
        const para: string = paragraphs[paraIndex]
        if (chunk.length + para.length > TEXT_BLOCK_CHAR_LIMIT && chunk.length > 0) {
          result.push({ key: (keyId++).toString(), type: 'text', content: chunk.trim() })
          chunk = ''
          if (result.length >= MAX_TOTAL_BLOCKS) {
            break
          }
        }
        chunk += (chunk.length > 0 ? '\n\n' : '') + para
        paraIndex += 1
      }
      if (chunk.trim().length > 0 && result.length < MAX_TOTAL_BLOCKS) {
        result.push({ key: (keyId++).toString(), type: 'text', content: chunk.trim() })
      }
    }
    if (result.length >= MAX_TOTAL_BLOCKS) {
      break
    }
    index += 1
  }

  return result
}

// ============================================================================
//  FormulaBlockDataSource — LazyForEach 数据源
// ============================================================================

class FormulaBlockDataSource implements IDataSource {
  private blocks: FormulaBlock[] = []
  private listeners: DataChangeListener[] = []
  private fallback: FormulaBlock = { key: '0', type: 'text', content: '' }

  totalCount(): number {
    return this.blocks.length
  }

  getData(index: number): FormulaBlock {
    const block: FormulaBlock | undefined = this.blocks[index]
    return block === undefined ? this.fallback : block
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener)
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((item: DataChangeListener): boolean => item !== listener)
  }

  setBlocks(newBlocks: FormulaBlock[]): void {
    this.blocks = newBlocks
    for (const listener of this.listeners) {
      listener.onDataReloaded()
    }
  }
}

// ============================================================================
//  FormulaSplitRenderer
// ============================================================================

@Component
export struct FormulaSplitRenderer {
  @Prop @Watch('onTextChanged') text: string = ''
  @Prop profile: 'chat' | 'chatUser' = 'chat'
  private dataSource: FormulaBlockDataSource = new FormulaBlockDataSource()
  private contentProtocol: ContentProtocol = new ContentProtocol()

  aboutToAppear(): void {
    this.rebuildBlocks()
  }

  // @Watch 回调 — struct 唯一允许的普通方法
  onTextChanged(): void {
    this.rebuildBlocks()
  }

  private rebuildBlocks = (): void => {
    const normalizedText: string = this.normalizedTextForSplit()
    const rawBlocks: FormulaBlock[] = splitByFormulas(normalizedText)
    const blocks: FormulaBlock[] = splitLongTextBlocks(rawBlocks)
    this.dataSource.setBlocks(blocks)
  }

  private normalizedTextForSplit = (): string => {
    const result: ContentValidationResult = this.contentProtocol.normalizeNoteMarkdown(this.text)
    if (!result.fallbackRequired && result.normalizedText.length > 0) {
      return result.normalizedText
    }
    return this.text
  }

  private textColorForProfile = (): ResourceColor => {
    return this.profile === 'chatUser' ? TEXT : TEXT_2
  }

  private formulaBgForProfile = (): ResourceColor => {
    return this.profile === 'chatUser'
      ? 'rgba(10,12,16,0.18)'
      : 'rgba(255,255,255,0.06)'
  }

  private formulaBorderForProfile = (): ResourceColor => {
    return this.profile === 'chatUser'
      ? 'rgba(255,255,255,0.18)'
      : 'rgba(255,255,255,0.12)'
  }

  build() {
    Column() {
      LazyForEach(this.dataSource,
        (block: FormulaBlock, _index: number | undefined): void => {
          if (block.type === 'formula') {
            MathTextRenderer({
              text: block.content,
              profile: this.profile,
              forceDisplay: true,
              minHeight: 42,
              textColor: this.textColorForProfile(),
              formulaColor: this.textColorForProfile(),
              formulaBackground: this.formulaBgForProfile(),
              formulaBorder: this.formulaBorderForProfile(),
              fontSize: F_SM,
              lineHeight: 20,
              formulaFontSize: F_SM,
              formulaLineHeight: 20,
            })
              .width('100%')
          } else {
            MathTextRenderer({
              text: block.content,
              profile: this.profile,
              forceDisplay: false,
              minHeight: 42,
              textColor: this.textColorForProfile(),
              formulaColor: this.textColorForProfile(),
              formulaBackground: this.formulaBgForProfile(),
              formulaBorder: this.formulaBorderForProfile(),
              fontSize: F_SM,
              lineHeight: 20,
              formulaFontSize: F_SM,
              formulaLineHeight: 20,
            })
              .width('100%')
          }
        },
        (block: FormulaBlock): string => block.key
      )
    }
    .width('100%')
  }
}
