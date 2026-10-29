// 路径: scripts/arkts-lint/tests/v7-problem-merger.test.mjs
// 职责: 036 阶段 2 problemMerger 契约测试（装载真实 .ets，不复制实现）。
// Why: 续页 / 重识别 / 重拍去重必须确定性合并；灰区必须保留两条并显式标记复核。

// 用 note-review-ets-loader 装载真实 .ets（TypeScript 转译 + 独立 vm realm）。
// loader 的 modulePathForRequest 已能把 './problemSegmenter' 解析到同目录 .ets，
// 且 problemMerger 只引用 ProblemSegment 类型（转译后 import 被擦除），故无需 mocks。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const mod = loadNoteReviewEtsModule('agents/src/main/ets/graph/problemMerger.ets');
const mergeProblems = mod.mergeProblems;
const similarity = mod.similarity;
const normalizeForFingerprint = mod.normalizeForFingerprint;

test('an adjacent page with no anchor continues the previous problem', () => {
  const inputs = [
    { imageIndex: 0, segmentIndex: 0, anchor: '', text: '已知函数 f(x)=x^2', needsReview: false },
    { imageIndex: 1, segmentIndex: 0, anchor: '', text: '求 f(1) 的值。', needsReview: false },
  ];
  const merged = mergeProblems(inputs);
  assert.equal(merged.length, 1);
  assert.equal(merged[0].index, 0);
  assert.equal(merged[0].text, '已知函数 f(x)=x^2\n求 f(1) 的值。');
  assert.equal(merged[0].sources.length, 2);
  assert.equal(merged[0].sources[0].imageIndex, 0);
  assert.equal(merged[0].sources[1].imageIndex, 1);
  assert.equal(merged[0].sources[1].segmentIndex, 0);
  assert.equal(merged[0].sources[1].text, '求 f(1) 的值。');
  assert.equal(merged[0].needsReview, false);
  inputs[0].text = '被调用方事后改写';
  assert.equal(merged[0].sources[0].text, '已知函数 f(x)=x^2', 'sources must be copies, not shared references');
});

test('the same anchor with similarity >= 0.6 merges and keeps the longer text', () => {
  const shortText = '1. 求函数 f(x)=x^2 在 x=1 处的导数。';
  const longText = '1. 求函数 f(x)=x^2 在 x=1 处的导数，并写出步骤。';
  const merged = mergeProblems([
    { imageIndex: 0, segmentIndex: 0, anchor: '1.', text: shortText, needsReview: false },
    { imageIndex: 0, segmentIndex: 1, anchor: '1.', text: longText, needsReview: false },
  ]);
  assert.equal(similarity(shortText, longText), 20 / 28);
  assert.equal(merged.length, 1);
  assert.equal(merged[0].index, 0);
  assert.equal(merged[0].text, longText);
  assert.equal(merged[0].sources.length, 2);
  assert.equal(merged[0].fingerprint, normalizeForFingerprint(longText));
  assert.equal(merged[0].needsReview, false);
});

test('the 0.4-0.6 grey zone keeps both problems and marks both for review', () => {
  const firstText = '1. 已知函数 f(x)=x^2 求导数。';
  const secondText = '1. 已知函数 f(x)=x^3 求积分。';
  const merged = mergeProblems([
    { imageIndex: 0, segmentIndex: 0, anchor: '1.', text: firstText, needsReview: false },
    { imageIndex: 1, segmentIndex: 0, anchor: '1.', text: secondText, needsReview: false },
  ]);
  assert.equal(similarity(firstText, secondText), 12 / 22);
  assert.equal(merged.length, 2, 'grey-zone similarity must not merge');
  assert.equal(merged[0].index, 0);
  assert.equal(merged[1].index, 1);
  assert.equal(merged[0].text, firstText);
  assert.equal(merged[1].text, secondText);
  assert.equal(merged[0].sources.length, 1);
  assert.equal(merged[1].sources.length, 1);
  assert.equal(merged[0].needsReview, true);
  assert.equal(merged[1].needsReview, true);
});

test('two different anchors with near-identical wording stay two problems', () => {
  const merged = mergeProblems([
    { imageIndex: 0, segmentIndex: 0, anchor: '1.', text: '证明函数 f(x)=x^2 在 x=0 处连续。', needsReview: false },
    { imageIndex: 1, segmentIndex: 0, anchor: '2.', text: '证明函数 g(x)=x^2 在 x=0 处连续。', needsReview: false },
  ]);
  assert.equal(similarity('证明函数 f(x)=x^2 在 x=0 处连续。', '证明函数 g(x)=x^2 在 x=0 处连续。') >= 0.8, true,
    'the fixture must be similar enough to trip the old unconditional 0.8 dedupe');
  assert.equal(merged.length, 2, 'different anchors mean different problems even when wording is close');
  assert.equal(merged[0].sources.length, 1);
  assert.equal(merged[1].sources.length, 1);
});

test('a re-photographed identical problem dedupes by fingerprint', () => {
  const firstText = '1. 求函数 f(x)=x^2 的导数。';
  const secondText = '1) 求函数 f(x)=x^2 的导数。';
  const merged = mergeProblems([
    { imageIndex: 0, segmentIndex: 0, anchor: '1.', text: firstText, needsReview: false },
    { imageIndex: 1, segmentIndex: 0, anchor: '1)', text: secondText, needsReview: false },
  ]);
  assert.equal(normalizeForFingerprint(firstText), normalizeForFingerprint(secondText));
  assert.equal(merged.length, 1);
  assert.equal(merged[0].sources.length, 2);
  assert.equal(merged[0].sources[0].imageIndex, 0);
  assert.equal(merged[0].sources[1].imageIndex, 1);
  assert.equal(merged[0].fingerprint, normalizeForFingerprint(firstText));
  assert.equal(merged[0].needsReview, false);
});

test('three unrelated images produce three problems with continuous indexes', () => {
  const merged = mergeProblems([
    { imageIndex: 0, segmentIndex: 0, anchor: '1.', text: '1. 求函数 f(x)=x^2 的导数。', needsReview: false },
    { imageIndex: 1, segmentIndex: 0, anchor: '2.', text: '2. 计算半径为 2 的圆面积。', needsReview: false },
    { imageIndex: 2, segmentIndex: 0, anchor: '3.', text: '3. 证明勾股定理。', needsReview: false },
  ]);
  assert.equal(merged.length, 3);
  assert.equal(merged[0].index, 0);
  assert.equal(merged[1].index, 1);
  assert.equal(merged[2].index, 2);
  assert.equal(merged[0].sources.length, 1);
  assert.equal(merged[1].sources.length, 1);
  assert.equal(merged[2].sources.length, 1);
  assert.equal(merged[0].sources[0].imageIndex, 0);
  assert.equal(merged[1].sources[0].imageIndex, 1);
  assert.equal(merged[2].sources[0].imageIndex, 2);
});

test('similarity is 1 for identical non-empty text and for two empty strings', () => {
  assert.equal(similarity('函数在一点连续', '函数在一点连续'), 1);
  assert.equal(similarity('', ''), 1);
  assert.equal(similarity('函数 在一点连续', '函数在一点连续'), 1);
  assert.equal(similarity('函数', '连续'), 0);
});
