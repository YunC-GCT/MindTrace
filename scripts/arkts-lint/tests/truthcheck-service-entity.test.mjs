import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');

const km = read('agents/src/main/ets/agents/KnowledgeModel.ets');
const tcs = read('agents/src/main/ets/agents/TruthCheckService.ets');
const tcsTestPath = resolve(root, 'agents/src/test/TruthCheckService.test.ets');

// spec 015 PR1: 真值检查实现实体化到 TruthCheckService, KnowledgeModel 仅保留转发。
test('TruthCheckService holds the real truth-check implementation', () => {
  assert.match(tcs, /truthCheck\(ocrText: string\): MvpTruthCheckResult/, 'truthCheck impl must live in TruthCheckService');
  assert.match(tcs, /checkBracePairing\(text: string\)/, 'brace pairing impl must live in TruthCheckService');
  assert.match(tcs, /checkDivisionByZero\(text: string\)/);
  assert.match(tcs, /checkEquation\(text: string\)/);
  assert.match(tcs, /checkLatexInternal\(body: string\)/);
  assert.match(tcs, /patchIntegralDx\(text: string, issues: string\[\]\)/);
  assert.doesNotMatch(tcs, /from '\.\/KnowledgeModel'/, 'TruthCheckService must not depend on KnowledgeModel');
});

test('the 4 internal result interfaces moved with the logic', () => {
  for (const name of ['BracePairingResult', 'LatexCheckDetail', 'DivisionByZeroCheck', 'EquationCheckResult']) {
    assert.match(tcs, new RegExp(`interface ${name}`), `${name} must be defined in TruthCheckService`);
    assert.doesNotMatch(km, new RegExp(`interface ${name}`), `${name} must be removed from KnowledgeModel`);
  }
});

test('KnowledgeModel keeps only a delegating truthCheck', () => {
  assert.match(km, /import \{ TruthCheckService \} from '\.\/TruthCheckService';/);
  assert.match(km, /truthCheckService\.check\(ocrText\)/, 'KnowledgeModel.truthCheck must delegate');
  assert.doesNotMatch(km, /checkBracePairing\(/, 'KnowledgeModel must no longer implement checks');
  assert.doesNotMatch(km, /checkLatexInternal\(/);
  assert.doesNotMatch(km, /patchIntegralDx\(/);
  assert.doesNotMatch(km, /checkDivisionByZero\(/);
  assert.doesNotMatch(km, /checkEquation\(/);
  // structure() 内部调用点保持不变 (行为零变化)
  assert.match(km, /this\.truthCheck\(ocrText\)/);
});

test('service-level Hypium coverage exists (4 checks)', () => {
  assert.equal(existsSync(tcsTestPath), true, 'agents/src/test/TruthCheckService.test.ets must exist');
  const t = read('agents/src/test/TruthCheckService.test.ets');
  const itCount = (t.match(/\bit\(/g) ?? []).length;
  assert.ok(itCount >= 4, `expected >=4 Hypium cases, found ${itCount}`);
  for (const marker of ['checkBracePairing', 'checkDivisionByZero', 'checkEquation', 'checkLatexInternal']) {
    assert.match(t, new RegExp(marker), `service test must cover ${marker}`);
  }
});
