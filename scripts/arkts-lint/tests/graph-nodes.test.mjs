import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const ocr = readFileSync(resolve(root, 'agents/src/main/ets/graph/nodes/OcrNode.ets'), 'utf8');
const classify = readFileSync(resolve(root, 'agents/src/main/ets/graph/nodes/ClassifyNode.ets'), 'utf8');
const structure = readFileSync(resolve(root, 'agents/src/main/ets/graph/nodes/StructureNode.ets'), 'utf8');
const truthCheck = readFileSync(resolve(root, 'agents/src/main/ets/graph/nodes/TruthCheckNode.ets'), 'utf8');
const persist = readFileSync(resolve(root, 'agents/src/main/ets/graph/nodes/PersistNode.ets'), 'utf8');
const knowledgeModel = readFileSync(resolve(root, 'agents/src/main/ets/agents/KnowledgeModel.ets'), 'utf8');

test('CaptureGraph nodes are exposed via factory pattern', () => {
  assert.match(ocr, /class OcrNodeFactory/);
  assert.match(classify, /class ClassifyNodeFactory/);
  assert.match(structure, /class StructureNodeFactory/);
  assert.match(truthCheck, /class TruthCheckNodeFactory/);
  assert.match(persist, /class PersistNodeFactory/);
});

test('PersistNode honors persist flag and uses NoteDaoInterface', () => {
  assert.match(persist, /if \(!input\.persist\)/);
  assert.match(persist, /NoteDaoInterface/);
  assert.match(persist, /dao\.insert\(input\.knowledgeUnit\)/);
  assert.doesNotMatch(persist, /createUnitExt|['"]概念['"]|difficulty\s*=\s*3/);
});

test('StructureNode returns structured error on failure', () => {
  assert.match(structure, /STRUCTURE_ERROR/);
  assert.match(structure, /next\.error = error/);
});

test('TruthCheckNode preserves the structured KnowledgeUnit for PersistNode', () => {
  assert.match(truthCheck, /copyAgentState\(input\)/);
  assert.match(truthCheck, /next\.truthCheck = truthCheck/);
});

test('Capture nodes preserve state channels through one copy function', () => {
  for (const source of [ocr, classify, structure, truthCheck, persist]) {
    assert.match(source, /copyAgentState\(input\)/);
  }
});

test('TruthCheckNode uses truthFlag directly and short-circuits failed checks', () => {
  assert.match(truthCheck, /passed: result\.truthFlag/);
  assert.doesNotMatch(truthCheck, /passed: result\.truthFlag === false/);
  assert.match(truthCheck, /TRUTH_CHECK_ERROR/);
  assert.match(truthCheck, /next\.error = error/);
});

test('TruthCheck has one production owner in the Capture workflow', () => {
  assert.match(truthCheck, /service\.check\(truthInput\)/);
  assert.match(truthCheck, /input\.captureText \+ '\\n' \+ input\.knowledgeUnit\.content/);
  assert.doesNotMatch(knowledgeModel, /TruthCheckService|truthCheckService\.check/);
});
