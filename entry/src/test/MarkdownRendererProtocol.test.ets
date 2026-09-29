/**
 * MarkdownRendererProtocol.test.ets - chat Markdown parser regression tests
 *
 * Path: entry/src/test/MarkdownRendererProtocol.test.ets
 * Responsibility: Verify the native chat path preserves supported block and inline Markdown.
 * Dependencies: Hypium, MarkdownParser, MarkdownInlineParser
 *
 * Data flow:
 *   MM-MD-v1 fixture -> parser -> renderable native block and inline segments
 *
 * ArkTS 1.1 strict adaptation:
 *   - Uses explicit parser result types and no any/unknown values.
 */

import { describe, it, expect } from '@ohos/hypium';
import { parseMarkdown } from '../main/ets/utils/MarkdownParser';
import type { MarkdownBlock } from '../main/ets/utils/MarkdownParser';
import { parseMarkdownInline } from '../main/ets/utils/MarkdownInlineParser';
import type { MarkdownInlineSegment } from '../main/ets/utils/MarkdownInlineParser';

function repeatText(value: string, count: number): string {
  let result: string = '';
  let index: number = 0;
  while (index < count) {
    result += value;
    index += 1;
  }
  return result;
}

function dollarCount(value: string): number {
  let count: number = 0;
  let index: number = 0;
  while (index < value.length) {
    if (value.charAt(index) === '$') {
      count += 1;
    }
    index += 1;
  }
  return count;
}

export default function markdownRendererProtocolTest(): void {
  describe('MarkdownRenderer.chat_protocol', () => {
    it('parses_heading_emphasis_code_and_flat_lists', 0, () => {
      const source: string = '# Core result\n\n'
        + 'This is **important** and calls `solve()`.\n\n'
        + '- Condition A\n'
        + '- Condition B\n\n'
        + '1. First step\n'
        + '2. Second step';
      const blocks: MarkdownBlock[] = parseMarkdown(source);
      expect(blocks.length).assertEqual(4);
      expect(blocks[0].kind).assertEqual('heading');
      expect(blocks[1].kind).assertEqual('paragraph');
      expect(blocks[2].kind).assertEqual('list');
      expect(blocks[2].ordered).assertFalse();
      expect(blocks[3].kind).assertEqual('list');
      expect(blocks[3].ordered).assertTrue();

      const inline: MarkdownInlineSegment[] = parseMarkdownInline(blocks[1].text);
      expect(inline.length).assertEqual(5);
      expect(inline[1].kind).assertEqual('bold');
      expect(inline[1].text).assertEqual('important');
      expect(inline[3].kind).assertEqual('code');
      expect(inline[3].text).assertEqual('solve()');
    });

    it('chunks_long_paragraph_without_splitting_inline_formula', 0, () => {
      const source: string = repeatText('前置说明。', 100)
        + '公式 $' + repeatText('x+', 180) + 'y$ 推导完成。'
        + repeatText('后续结论。', 100);
      const blocks: MarkdownBlock[] = parseMarkdown(source);
      let formulaBlockCount: number = 0;
      for (const block of blocks) {
        const markers: number = dollarCount(block.text);
        if (markers > 0) {
          formulaBlockCount += 1;
        }
        expect(markers === 0 || markers === 2).assertTrue();
      }
      expect(blocks.length > 1).assertTrue();
      expect(formulaBlockCount).assertEqual(1);
    });

    it('keeps_inline_code_dollars_out_of_formula_chunks', 0, () => {
      const source: string = repeatText('说明。', 180)
        + ' 示例 `price=$5` 仍是代码，公式 $x+1$ 在正文中。'
        + repeatText('结论。', 180);
      const blocks: MarkdownBlock[] = parseMarkdown(source);
      let formulaBlockCount: number = 0;
      let codeLiteralFound: boolean = false;
      for (const block of blocks) {
        if (block.text.indexOf('price=$5') >= 0) {
          codeLiteralFound = true;
        }
        if (block.text.indexOf('$x+1$') >= 0) {
          formulaBlockCount += 1;
        }
      }
      expect(codeLiteralFound).assertTrue();
      expect(formulaBlockCount).assertEqual(1);
    });

    it('does_not_split_a_formula_after_inline_code_dollar_at_chunk_boundary', 0, () => {
      const source: string = repeatText('前置说明。', 105)
        + ' 示例 `price=$5` 后接长公式 $'
        + repeatText('x + ', 180) + 'y$。'
        + repeatText('结论。', 105);
      const blocks: MarkdownBlock[] = parseMarkdown(source);
      let formulaBlockCount: number = 0;
      let formulaBlock: string = '';
      for (const block of blocks) {
        if (block.text.indexOf('$x + ') >= 0 || block.text.indexOf('x + x') >= 0) {
          formulaBlockCount += 1;
          formulaBlock += block.text;
        }
      }
      expect(formulaBlockCount).assertEqual(1);
      expect(formulaBlock.endsWith('y$。')).assertTrue();
    });

    it('parses_consecutive_display_formulas_as_complete_blocks', 0, () => {
      const blocks: MarkdownBlock[] = parseMarkdown('$$a=b$$$$c=d$$');
      let formulaCount: number = 0;
      for (const block of blocks) {
        if (block.kind === 'formula') {
          formulaCount += 1;
        }
      }
      expect(formulaCount).assertEqual(2);
      expect(blocks[0].text).assertEqual('a=b');
      expect(blocks[1].text).assertEqual('c=d');
    });
  });
}
