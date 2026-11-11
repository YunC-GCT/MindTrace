// 路径: scripts/arkts-lint/tests/math-signature.test.mjs
// 职责: 数学题面签名——同一道题的算术表述归一成同一种结构。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const mod = loadNoteReviewEtsModule('common/src/main/ets/utils/MathSignature.ets');
const { extractMathSignature, normalizeMathText } = mod;

test('加法短语与算式得到同一签名', () => {
  assert.equal(extractMathSignature('计算 21 加 21 的结果并写出运算步骤'), 'add(21,21)');
  assert.equal(extractMathSignature('两个 21 的和是多少'), 'add(21,21)');
  assert.equal(extractMathSignature('21+21'), 'add(21,21)');
});

test('中文数字与全角符号归一', () => {
  assert.equal(normalizeMathText('二十一加二十一'), '21加21');
  assert.equal(extractMathSignature('计算 八十 加 八十'), 'add(80,80)');
  assert.equal(extractMathSignature('12 × 3'), 'mul(12,3)');
});

test('优先级结构：12-4×2 先乘后减', () => {
  assert.equal(extractMathSignature('计算 12 - 4 × 2 的值'), 'sub(12,mul(4,2))');
});

test('除法与平方', () => {
  assert.equal(extractMathSignature('求 21 除以 3 的商'), 'div(21,3)');
  assert.equal(extractMathSignature('9 的平方是多少'), 'sq(9)');
});

test('没有算式时返回空串', () => {
  assert.equal(extractMathSignature('今天天气怎么样'), '');
  assert.equal(extractMathSignature('拉格朗日中值定理的条件'), '');
});
