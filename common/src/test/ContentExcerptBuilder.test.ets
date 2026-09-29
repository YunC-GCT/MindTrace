/**
 * ContentExcerptBuilder.test.ets - protocol-safe note excerpt regression tests
 *
 * Path: common/src/test/ContentExcerptBuilder.test.ets
 * Responsibility: Verify compact previews never cut formula delimiters.
 * Dependencies: Hypium, ContentExcerptBuilder, ContentProtocol
 *
 * ArkTS 1.1 strict adaptation:
 *   - Uses explicit result types and no any/unknown values.
 */

import { describe, it, expect } from '@ohos/hypium';
import { ContentExcerptBuilder, ContentProtocol } from '../main/ets/Index';
import type { ContentValidationResult } from '../main/ets/Index';

export default function contentExcerptBuilderTest(): void {
  describe('ContentExcerptBuilder.note_preview', () => {
    it('builds_summary_with_short_formula_under_60_chars', 0, () => {
      const source: string = '当 $a>0$ 时，函数在该区间单调递增并且连续。';
      const summary: string = new ContentExcerptBuilder().buildSummary(source, 60);
      const validation: ContentValidationResult = new ContentProtocol().normalizeNoteMarkdown(summary);
      expect(summary.length <= 60).assertTrue();
      expect(summary).assertContain('$a>0$');
      expect(validation.fallbackRequired).assertFalse();
    });

    it('drops_oversized_formula_without_placeholder_in_summary', 0, () => {
      const source: string = '正态密度为 '
        + '$f(x)=\\frac{1}{\\sigma\\sqrt{2\\pi}}e^{-\\frac{(x-\\mu)^2}{2\\sigma^2}}$，'
        + '用于描述连续型随机变量。';
      const summary: string = new ContentExcerptBuilder().buildSummary(source, 60);
      const validation: ContentValidationResult = new ContentProtocol().normalizeNoteMarkdown(summary);
      expect(summary.length <= 60).assertTrue();
      expect(summary.indexOf('相应公式') < 0).assertTrue();
      expect(summary.indexOf('对应公式') < 0).assertTrue();
      expect(validation.fallbackRequired).assertFalse();
    });

    it('skips_display_formula_in_summary', 0, () => {
      const source: string = '正态分布的密度函数如下：\n$$\n'
        + 'f(x)=\\frac{1}{\\sigma\\sqrt{2\\pi}}e^{-\\frac{(x-\\mu)^2}{2\\sigma^2}}\n'
        + '$$\n该函数关于均值对称。';
      const summary: string = new ContentExcerptBuilder().buildSummary(source, 60);
      const validation: ContentValidationResult = new ContentProtocol().normalizeNoteMarkdown(summary);
      expect(summary.length <= 60).assertTrue();
      expect(summary.indexOf('$$') < 0).assertTrue();
      expect(summary.indexOf('\\frac') < 0).assertTrue();
      expect(summary).assertContain('正态分布');
      expect(validation.fallbackRequired).assertFalse();
    });

    it('replaces_long_inline_formula_instead_of_cutting_it', 0, () => {
      const source: string = '正态分布的概率密度函数为 '
        + '$f(x)=\\frac{1}{\\sigma\\sqrt{2\\pi}}e^{-\\frac{(x-\\mu)^2}{2\\sigma^2}}$，'
        + '并且关于均值对称。';
      const preview: string = new ContentExcerptBuilder().buildListPreview(source, 46);
      const validation: ContentValidationResult = new ContentProtocol().normalizeNoteMarkdown(preview);
      expect(preview).assertContain('相应公式');
      expect(preview.indexOf('\\frac') < 0).assertTrue();
      expect(validation.fallbackRequired).assertFalse();
    });

    it('keeps_complete_short_inline_formula', 0, () => {
      const source: string = '当 $a>0$ 时，抛物线开口向上。';
      const preview: string = new ContentExcerptBuilder().buildListPreview(source, 46);
      expect(preview).assertEqual(source);
      expect(new ContentProtocol().normalizeNoteMarkdown(preview).fallbackRequired).assertFalse();
    });

    it('keeps_short_display_formula_renderable', 0, () => {
      const source: string = '$$\na+b=c\n$$';
      const preview: string = new ContentExcerptBuilder().buildListPreview(source, 46);
      expect(preview).assertEqual(source);
      expect(new ContentProtocol().normalizeNoteMarkdown(preview).fallbackRequired).assertFalse();
    });

    it('collapses_oversized_display_formula', 0, () => {
      const source: string = '$$\nf(x)=\\frac{1}{\\sigma\\sqrt{2\\pi}}'
        + '\\exp\\left(-\\frac{(x-\\mu)^2}{2\\sigma^2}\\right)\n$$';
      const preview: string = new ContentExcerptBuilder().buildListPreview(source, 46);
      expect(preview).assertEqual('核心公式');
    });

    it('builds_short_plain_summary_without_broken_math', 0, () => {
      const source: string = '若随机变量的密度函数为 '
        + '$f(x)=\\frac{1}{\\sigma\\sqrt{2\\pi}}e^{-\\frac{(x-\\mu)^2}{2\\sigma^2}}$，'
        + '则称其服从正态分布。\n$$\nP(a<X<b)=\\int_a^b f(x)\\,dx\n$$';
      const summary: string = new ContentExcerptBuilder().buildPlainSummary(source, 80);
      const validation: ContentValidationResult = new ContentProtocol().normalizeNoteMarkdown(summary);
      expect(summary).assertContain('相应公式');
      expect(summary).assertContain('正态分布');
      expect(summary.indexOf('$') < 0).assertTrue();
      expect(summary.length <= 109).assertTrue();
      expect(validation.fallbackRequired).assertFalse();
    });

    it('is_idempotent_for_already_compact_preview', 0, () => {
      const builder: ContentExcerptBuilder = new ContentExcerptBuilder();
      const first: string = builder.buildListPreview('当 $a>0$ 时，抛物线开口向上。', 46);
      const second: string = builder.buildListPreview(first, 46);
      expect(second).assertEqual(first);
    });
  });
}
