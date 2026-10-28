// 路径: scripts/arkts-lint/tests/v7-problem-segmenter.test.mjs
// 职责: 036 阶段 2 problemSegmenter 契约测试（装载真实 .ets，不复制实现）。
// Why: 切题失败必须显式退化；测试锁住「原文可回查 + 宁可粗不可错」。

// 用 note-review-ets-loader 装载真实 .ets（TypeScript 转译 + 独立 vm realm）。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const mod = loadNoteReviewEtsModule('agents/src/main/ets/graph/problemSegmenter.ets');
const segmentProblems = mod.segmentProblems;

function joinRaw(segments) {
  let joined = '';
  for (let i = 0; i < segments.length; i += 1) {
    joined += segments[i].rawText;
  }
  return joined;
}

test('blank input yields no segments and is not degraded', () => {
  const result = segmentProblems('  \n\t \n');
  assert.equal(result.segments.length, 0, 'blank OCR text has nothing to cut');
  assert.equal(result.degraded, false, 'blank is an empty page, not a failed cut');
});

test('a page without anchors stays one segment and is not degraded', () => {
  const text = '求函数 y = x^2 在 x = 1 处的导数。';
  const result = segmentProblems(text);
  assert.equal(result.segments.length, 1);
  assert.equal(result.degraded, false);
  assert.equal(result.segments[0].index, 0);
  assert.equal(result.segments[0].anchor, '');
  assert.equal(result.segments[0].rawText, text);
  assert.equal(result.segments[0].needsReview, false);
});

test('three numbered problems split into three anchored segments', () => {
  const text = '1. 求导。\n2. 求积分。\n3. 求极限。';
  const result = segmentProblems(text);
  assert.equal(result.segments.length, 3);
  assert.equal(result.degraded, false);
  assert.equal(result.segments[0].anchor, '1.');
  assert.equal(result.segments[1].anchor, '2.');
  assert.equal(result.segments[2].anchor, '3.');
  assert.equal(result.segments[0].index, 0);
  assert.equal(result.segments[1].index, 1);
  assert.equal(result.segments[2].index, 2);
  assert.equal(result.segments[0].rawText, '1. 求导。\n');
  assert.equal(result.segments[1].rawText, '2. 求积分。\n');
  assert.equal(result.segments[2].rawText, '3. 求极限。');
  assert.equal(result.segments[0].needsReview, false);
  assert.equal(joinRaw(result.segments), text, 'raw slices must reconstruct the input exactly');
});

test('a title before the first anchor becomes segment 0', () => {
  const text = '2026 年高三数学试卷\n1. 求导。\n2. 求积分。\n3. 求极限。';
  const result = segmentProblems(text);
  assert.equal(result.segments.length, 4);
  assert.equal(result.degraded, false);
  assert.equal(result.segments[0].index, 0);
  assert.equal(result.segments[0].anchor, '');
  assert.equal(result.segments[0].rawText, '2026 年高三数学试卷\n');
  assert.equal(result.segments[0].needsReview, false);
  assert.equal(result.segments[1].index, 1);
  assert.equal(result.segments[1].anchor, '1.');
  assert.equal(result.segments[2].anchor, '2.');
  assert.equal(result.segments[3].anchor, '3.');
  assert.equal(joinRaw(result.segments), text, 'preamble plus anchors must reconstruct the input exactly');
});

test('non-increasing anchors degrade the whole page to one reviewed segment', () => {
  const text = '2. 求导。\n1. 求积分。\n3. 求极限。';
  const result = segmentProblems(text);
  assert.equal(result.segments.length, 1);
  assert.equal(result.degraded, true);
  assert.equal(result.segments[0].index, 0);
  assert.equal(result.segments[0].anchor, '');
  assert.equal(result.segments[0].rawText, text);
  assert.equal(result.segments[0].needsReview, true);
});

test('textbook section decimals are not problem anchors', () => {
  const text = '1.5 函数的连续性\n1.6 导数与微分\n1.7 不定积分';
  const result = segmentProblems(text);
  assert.equal(result.segments.length, 1, '1.5 / 1.6 / 1.7 are section numbers, not problem numbers');
  assert.equal(result.degraded, false);
  assert.equal(result.segments[0].rawText, text);
});

test('parenthesized sub-numbers alone do not create a main boundary', () => {
  const text = '1. 已知函数 f(x)。\n（1）求 f(0)；\n（2）求 f(x) 的极值。';
  const result = segmentProblems(text);
  assert.equal(result.segments.length, 1, 'only one main anchor exists, so nothing is cut');
  assert.equal(result.degraded, false);
  assert.equal(result.segments[0].index, 0);
  assert.equal(result.segments[0].anchor, '');
  assert.equal(result.segments[0].rawText, text);
  assert.equal(result.segments[0].needsReview, false);
});
