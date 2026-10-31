// 路径: scripts/arkts-lint/tests/v7-capture-set-plan.test.mjs
// 职责: 036 阶段 2/3 编排契约测试——逐图切题 + 跨图合并的纯函数计划（装载真实 .ets）。
// Why: 一图多题 / 多图多题必须由「题」决定笔记条数；空图与退化整页要显式标注，供确认页默认不勾选。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const mod = loadNoteReviewEtsModule('agents/src/main/ets/graph/captureSetPlanner.ets');
const planCaptureSet = mod.planCaptureSet;
const arr = (value) => Array.from(value);

test('single image with three anchored problems yields three planned problems', () => {
  const plan = planCaptureSet([
    { imageIndex: 0, text: '1. 求 f(1)\n2. 求 f(2)\n3. 求 f(3)' },
  ]);
  assert.equal(plan.problems.length, 3);
  assert.equal(plan.totalSegments, 3);
  assert.deepEqual(arr(plan.problems.map((p) => p.text)), ['1. 求 f(1)\n', '2. 求 f(2)\n', '3. 求 f(3)']);
  assert.deepEqual(arr(plan.problems[0].sourceImageIndexes), [0]);
  assert.deepEqual(arr(plan.problems[0].anchors), ['1.']);
  assert.equal(plan.degradedImageIndexes.length, 0);
  assert.equal(plan.emptyImageIndexes.length, 0);
  assert.equal(plan.problems[0].needsReview, false);
});

test('two pages of the same problem are merged into one planned problem', () => {
  const plan = planCaptureSet([
    { imageIndex: 0, text: '1. 已知函数 f(x)=x^2' },
    { imageIndex: 1, text: '求 f(1) 的值。' },
  ]);
  assert.equal(plan.problems.length, 1);
  assert.deepEqual(arr(plan.problems[0].sourceImageIndexes), [0, 1]);
  assert.ok(plan.problems[0].text.includes('f(x)=x^2'));
  assert.ok(plan.problems[0].text.includes('求 f(1)'));
});

test('un-anchored mixed pages produce M = problem count, not image count', () => {
  const plan = planCaptureSet([
    { imageIndex: 0, text: '1. 第一题\n2. 第二题' },
    { imageIndex: 1, text: '3. 第三题' },
    { imageIndex: 2, text: '4. 第四题' },
  ]);
  assert.equal(plan.problems.length, 4, '题目数量由题决定，而不是图片张数');
  assert.deepEqual(arr(plan.problems.map((p) => p.index)), [0, 1, 2, 3]);
});

test('empty OCR page is reported separately and produces no problem', () => {
  const plan = planCaptureSet([
    { imageIndex: 0, text: '   \n\t' },
    { imageIndex: 1, text: '1. 求极限。' },
  ]);
  assert.deepEqual(arr(plan.emptyImageIndexes), [0]);
  assert.equal(plan.problems.length, 1);
  assert.deepEqual(arr(plan.problems[0].sourceImageIndexes), [1]);
});

test('over-limit page degrades to one problem and is flagged needsReview', () => {
  let text = '';
  for (let i = 1; i <= 21; i += 1) {
    text += i + '. 题目 ' + i + '\n';
  }
  const plan = planCaptureSet([{ imageIndex: 0, text: text }]);
  assert.equal(plan.degradedImageIndexes.length, 1);
  assert.equal(plan.problems.length, 1);
  assert.equal(plan.problems[0].needsReview, true, '退化题必须进确认页待复核');
});

test('single-problem page keeps its anchor and stays standalone', () => {
  const plan = planCaptureSet([
    { imageIndex: 0, text: '1. 第一题' },
    { imageIndex: 1, text: '2. 第二题' },
  ]);
  assert.equal(plan.problems.length, 2, '单题页面不能因缺少多锚点被当成续页');
  assert.deepEqual(arr(plan.problems[0].anchors), ['1.']);
  assert.deepEqual(arr(plan.problems[1].anchors), ['2.']);
});

test('duplicate reshoot of the same problem collapses to one problem', () => {
  const same = '1. 已知函数 f(x)=x^2+1，求 f(1) 的值。';
  const plan = planCaptureSet([
    { imageIndex: 0, text: same },
    { imageIndex: 1, text: same },
  ]);
  assert.equal(plan.problems.length, 1);
  assert.equal(plan.problems[0].sourceImageIndexes.length, 2);
});
