import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';
import ts from 'typescript';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, '..', '..', '..');
const classifierPath = path.join(
  repoRoot,
  'agents',
  'src',
  'main',
  'ets',
  'agents',
  'TypeClassifier.ets',
);

const uglyCapture = [
  '@题目、4/对于一般的椭圆型方程 2Ou h Ou',
  '"i OO; + 壹伪赢 + cu = 0, 假设矩阵 (ay) 是正定的，即置==QiJiAiAy=肛置=d?',
  '(a>0), 设 1 j=i 又设 c<0。试证明它的解也成立着霍普夫极值原理。',
  'LaTeX formulas:',
  '\\frac{\\partial^2 u}{\\partial x_i\\partial x_j}+\\sum_{i=1}^{n}b_i\\frac{\\partial u}{\\partial x_i}+cu=0',
  'User note:',
  '什么内容',
].join('\n');

const refinedCapture = [
  '题目：对于一般的椭圆型方程，证明其解满足霍普夫极值原理。',
  '',
  '$$\\frac{\\partial^2 u}{\\partial x_i\\partial x_j}+\\sum_{i=1}^{n}b_i\\frac{\\partial u}{\\partial x_i}+cu=0$$',
  '',
  '用户补充：什么内容',
].join('\n');

async function loadClassifier() {
  const source = fs.readFileSync(classifierPath, 'utf8');
  const withoutImports = source.replace(
    /import\s+(?:type\s+)?\{[\s\S]*?\}\s+from\s+'[^']+';\s*/g,
    '',
  );
  const stubs = `
const NOTE_TYPE_KEYS = ['概念', '公式', '定理', '证明题', '计算题'];
const JSON_ONLY_RULES = '';
const normalizeNoteType = (value) => String(value);
const isKnownNoteType = (value) => NOTE_TYPE_KEYS.includes(String(value));
class OcrTool {}
class LlmGuard {
  async callJsonWithRetry(_messages, _options, validate) {
    const json = {
      category: '证明题',
      subject: '偏微分方程',
      chapter: '霍普夫极值原理',
      confidence: 0.95,
      cleaned_text: globalThis.__captureRefinedText,
    };
    const verdict = validate(json);
    if (!verdict.ok) throw new Error(verdict.issues.join('; '));
    return { json, raw: JSON.stringify(json), attempts: 1 };
  }
}
`;
  const output = ts.transpileModule(stubs + withoutImports, {
    compilerOptions: {
      module: ts.ModuleKind.ES2022,
      target: ts.ScriptTarget.ES2022,
    },
  }).outputText;
  globalThis.__captureRefinedText = refinedCapture;
  const url = 'data:text/javascript;base64,' + Buffer.from(output).toString('base64');
  return await import(url);
}

test('LLM classification returns refined OCR material for Capture State', async () => {
  const module = await loadClassifier();
  const classifier = new module.TypeClassifier();
  const result = await classifier.classifyText(uglyCapture);

  assert.equal(result.ocrText, refinedCapture);
  assert.equal(result.ocrTextQuality, 'refined');
  assert.doesNotMatch(result.ocrText, /QiJiAiAy|User note:|壹伪赢/);
  assert.match(result.ocrText, /霍普夫极值原理/);
  assert.match(result.ocrText, /\\frac\{\\partial\^2 u\}/);
});

test('ClassifyNode promotes refined OCR material into Capture State', () => {
  const nodePath = path.join(
    repoRoot,
    'agents',
    'src',
    'main',
    'ets',
    'graph',
    'nodes',
    'ClassifyNode.ets',
  );
  const source = fs.readFileSync(nodePath, 'utf8');
  assert.match(source, /next\.captureText\s*=\s*classification\.ocrText/);
  assert.match(source, /classification\.ocrTextQuality\s*!==\s*'refined'/);
  assert.match(source, /CAPTURE_TEXT_REFINEMENT_FAILED/);
});
