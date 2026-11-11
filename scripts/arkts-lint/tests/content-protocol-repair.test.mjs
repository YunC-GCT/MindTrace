// 路径: scripts/arkts-lint/tests/content-protocol-repair.test.mjs
// 职责: ContentProtocol 对裸公式行/截断公式的修复——补齐括号与 \left/\right，
//       避免整段降级成纯文本把原始 LaTeX 暴露给用户。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const mod = loadNoteReviewEtsModule('common/src/main/ets/render/ContentProtocol.ets');
const protocol = new mod.ContentProtocol();

function braceBalance(text) {
  let depth = 0;
  for (let i = 0; i < text.length; i += 1) {
    const ch = text.charAt(i);
    if (ch === '{' && (i === 0 || text.charAt(i - 1) !== '\\')) {
      depth += 1;
    } else if (ch === '}' && (i === 0 || text.charAt(i - 1) !== '\\')) {
      depth -= 1;
    }
  }
  return depth;
}

test('裸公式行被包进 $$ 且不触发降级', () => {
  const raw = '泰勒展开为\n\nf(x)=\\sum_{k=0}^{n}\\frac{f^{(k)}(x_0)}{k!}(x-x_0)^k\n\n这就是公式。';
  const result = protocol.normalizeNoteMarkdown(raw);
  assert.equal(result.fallbackRequired, false);
  assert.ok(result.normalizedText.includes('$$\nf(x)=\\sum'));
});

test('截断公式的未闭合括号被补齐，而不是整段降级', () => {
  const raw = '设函数满足\n\nf\'(\\xi) = \\frac{f(b)-f(a)}{…';
  const result = protocol.normalizeNoteMarkdown(raw);
  assert.equal(result.fallbackRequired, false);
  assert.ok(result.fixes.includes('balance_formula_brace'));
  assert.equal(braceBalance(result.normalizedText), 0);
});

test('\\left 未配对时补 \\right.', () => {
  const raw = '$$\\left( x + 1$$';
  const result = protocol.normalizeNoteMarkdown(raw);
  assert.equal(result.fallbackRequired, false);
  assert.ok(result.fixes.includes('balance_left_right'));
  assert.ok(result.normalizedText.includes('\\right.'));
});

test('正常公式不产生修复标记', () => {
  const raw = '$$\\frac{a}{b}$$';
  const result = protocol.normalizeNoteMarkdown(raw);
  assert.equal(result.fallbackRequired, false);
  assert.equal(result.fixes.includes('balance_formula_brace'), false);
  assert.equal(result.fixes.includes('balance_left_right'), false);
});

test('裸行内命令补 $...$，普通路径不误伤', () => {
  const raw = '则至少存在一点 \\xi \\in (a,b)，使得结论成立。';
  const result = protocol.normalizeNoteMarkdown(raw);
  assert.equal(result.fallbackRequired, false);
  assert.ok(result.normalizedText.includes('$\\xi$'));
  assert.ok(result.normalizedText.includes('$\\in$'));
  const pathResult = protocol.normalizeNoteMarkdown('路径是 C:\\Users\\demo 下');
  assert.equal(pathResult.normalizedText.includes('$\\Users$'), false);
});
