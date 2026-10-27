/**
 * #233 Note detail formula fence splitting.
 *
 * `splitReadableLines` must keep a `$$...$$` (or `\[...\]`) fence block as one
 * readable step, so DetailStepList numbers the whole formula once instead of
 * numbering the opening fence, the body and the closing fence separately.
 */

import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import ts from 'typescript';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, '..', '..', '..');
const modelPath = path.join(
  repoRoot,
  'entry',
  'src',
  'main',
  'ets',
  'overlays',
  'NoteDetailOverlay',
  'model',
  'DetailRenderModel.ets',
);
const galaxyPath = path.join(
  repoRoot,
  'entry',
  'src',
  'main',
  'ets',
  'services',
  'GalaxyPreviewData.ets',
);

const renderModelStubs = `
class ContentExcerptBuilder {
  buildSummary(text, maxLength) {
    const value = String(text === null || text === undefined ? '' : text);
    return value.length > maxLength ? value.substring(0, maxLength) : value;
  }
}
const NOTE_SUMMARY_MAX_LENGTH = 120;
const DifficultyLevel = { EASY: 0, MEDIUM: 1, HARD: 2 };
const ReviewStatus = { LEARNING: 0, REVIEW: 1, GRADUATED: 2, LAPSED: 3 };
const normalizeDraftSectionLabel = (title, index) => String(title).trim().length > 0 ? String(title) : '内容';
const normalizeNoteType = (value) => String(value);
`;

const galaxyStubs = `
const DifficultyLevel = { EASY: 0, MEDIUM: 1, HARD: 2 };
const ReviewStatus = { LEARNING: 0, REVIEW: 1, GRADUATED: 2, LAPSED: 3 };
`;

function stripImports(source) {
  return source.replace(/import\s*\{[\s\S]*?\}\s*from\s*'[^']+'\s*;?/g, '');
}

async function loadArktsModule(sourcePath, stubs) {
  const source = fs.readFileSync(sourcePath, 'utf8');
  const output = ts.transpileModule(stubs + '\n' + stripImports(source), {
    compilerOptions: {
      module: ts.ModuleKind.ES2022,
      target: ts.ScriptTarget.ES2022,
    },
  }).outputText;
  const url = 'data:text/javascript;base64,' + Buffer.from(output).toString('base64');
  return await import(url);
}

const modelModule = await loadArktsModule(modelPath, renderModelStubs);
const splitReadableLines = modelModule.splitReadableLines;

test('multi-line $$ fence stays one step and keeps its body lines intact', () => {
  const content = [
    '开头说明',
    '  $$',
    '  \\frac{a}{b}',
    '',
    '  + c',
    '  $$',
    '结尾说明',
  ].join('\n');

  assert.deepEqual(splitReadableLines(content), [
    '开头说明',
    '  $$\n  \\frac{a}{b}\n\n  + c\n  $$',
    '结尾说明',
  ]);
});

test('same-line $$x$$ stays one step', () => {
  assert.deepEqual(splitReadableLines('前\n$$x^2+1$$\n后'), [
    '前',
    '$$x^2+1$$',
    '后',
  ]);
  assert.deepEqual(splitReadableLines('$$a$$$$b$$'), ['$$a$$$$b$$']);
});

test('unclosed fence keeps the rest of the content instead of dropping it', () => {
  assert.deepEqual(splitReadableLines('开头\n$$\na+b\nc'), [
    '开头',
    '$$\na+b\nc',
  ]);
  assert.deepEqual(splitReadableLines('$$\na'), ['$$\na']);
});

test('formula fences and ordinary text keep their original order', () => {
  const content = [
    '第一步：整理',
    '$$',
    'x + 1 = 2',
    '$$',
    '第二步：求解 $x=1$',
    '$$',
    'x = 1',
    '$$',
    '结论',
  ].join('\n');

  assert.deepEqual(splitReadableLines(content), [
    '第一步：整理',
    '$$\nx + 1 = 2\n$$',
    '第二步：求解 $x=1$',
    '$$\nx = 1\n$$',
    '结论',
  ]);
});

test('inline $...$ formulas do not trigger fence splitting', () => {
  assert.deepEqual(splitReadableLines('已知 $x+1$ 的值\n$y$'), [
    '已知 $x+1$ 的值',
    '$y$',
  ]);
  assert.deepEqual(splitReadableLines('函数 $f(x)=x^2$ 在 $x=0$ 处连续'), [
    '函数 $f(x)=x^2$ 在 $x=0$ 处连续',
  ]);
});

test('list-prefixed fence is recognized by cleanListPrefix without cleaning its body', () => {
  const content = [
    '1. $$',
    '2. \\frac{a}{b}',
    '2. $$',
    '3. 收尾',
  ].join('\n');

  const items = splitReadableLines(content);
  assert.deepEqual(items, [
    '$$\n2. \\frac{a}{b}\n$$',
    '收尾',
  ]);
  assert.match(items[0], /2\. \\frac\{a\}\{b\}/);
  assert.equal(items.some((item) => item.trim() === '$$'), false);
  assert.equal(splitReadableLines('2. 普通行')[0], '普通行');
});

test('bracket display fences are paired by \\[ and \\]', () => {
  assert.deepEqual(splitReadableLines('前\n\\[\na\n\\]\n后'), [
    '前',
    '\\[\na\n\\]',
    '后',
  ]);
  assert.deepEqual(splitReadableLines('\\]\n普通'), ['\\]', '普通']);
});

test('GalaxyPreviewData preview formulas split into whole blocks, never bare $$', async () => {
  const galaxyModule = await loadArktsModule(galaxyPath, galaxyStubs);
  const units = new galaxyModule.GalaxyPreviewData().units();
  const unit = units.find((item) => item.id === 'galaxy_preview_limit_definition');

  assert.ok(unit, 'limit_definition preview unit should exist');
  const items = splitReadableLines(unit.content);
  const formulaBlocks = items.filter((item) => item.indexOf('$$') >= 0);

  assert.equal(items.length, 6);
  assert.equal(formulaBlocks.length, 2);
  for (const block of formulaBlocks) {
    assert.ok(block.startsWith('$$'), 'formula block must include its opening fence');
    assert.ok(block.endsWith('$$'), 'formula block must include its closing fence');
    assert.equal((block.match(/\$\$/g) || []).length, 2);
  }
  assert.equal(items.some((item) => item.trim() === '$$'), false);
  assert.deepEqual(items.slice(0, 2), [
    '极限用 epsilon-delta 语言精确描述函数的趋近过程，是连续、导数和级数判别的基础。',
    '函数极限的定义为：',
  ]);
  assert.equal(
    items[items.length - 1],
    '若两个函数的极限分别存在，则可进一步讨论复合函数、四则运算以及夹逼定理。',
  );
});
