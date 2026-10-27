import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createRequire } from 'node:module';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');
// a2a-smoke 自己不带 node_modules：复用 arkts-lint 里已安装的 typescript 做 transpile。
const requireFromLint = createRequire(resolve(root, 'scripts/arkts-lint/package.json'));
const ts = requireFromLint('typescript');

const source = read('entry/src/main/ets/services/ReplyStyleRules.ets');

async function loadRules() {
  const js = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ES2022 },
  }).outputText;
  return await import('data:text/javascript;base64,' + Buffer.from(js).toString('base64'));
}

const rules = await loadRules();

test('plain_text_math bans dollar delimiters and LaTeX, and teaches Unicode math instead', () => {
  const plain = rules.buildMathStyleRules('plain_text_math');
  // 不能把 UI 的「用单个美元符定界」要求搬进 A2A 通道
  assert.doesNotMatch(plain, /用单个美元符定界/);
  assert.doesNotMatch(plain, /\$\.\.\.\$/);
  assert.match(plain, /禁止/);
  assert.match(plain, /纯文本/);
  // 必须给出可直接显示的 Unicode 示例
  assert.match(plain, /√a/);
  assert.match(plain, /≥/);
  assert.match(plain, /x²/);
  assert.match(plain, /a\/b/);
  assert.match(plain, /×/);
  assert.match(plain, /÷/);
  assert.match(plain, /π/);
  // 不允许以「无法显示」为由省略数学含义
  assert.match(plain, /无法显示/);
  // 不要 Mermaid / HTML / 表格；分步推导用文字段落
  assert.match(plain, /Mermaid/);
  assert.match(plain, /HTML/);
  assert.match(plain, /表格/);
  assert.match(plain, /第 1 步：/);
});

test('markdown keeps the existing UI dollar / LaTeX rules', () => {
  const markdown = rules.buildMathStyleRules('markdown');
  assert.match(markdown, /\$\$/);
  assert.match(markdown, /单个美元符定界/);
  assert.match(markdown, /\\begin\{aligned\}/);
  assert.match(markdown, /不要使用 align 或 align\* 环境/);
  assert.match(markdown, /只输出最终答案/);
});

test('ReplyStyleRules stays a Kit-free pure module', () => {
  assert.doesNotMatch(source, /@kit\./);
  assert.doesNotMatch(source, /\bfrom\s+['"][^'"]+['"]/);
});
