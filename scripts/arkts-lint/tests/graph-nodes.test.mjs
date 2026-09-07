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
  assert.match(persist, /dao\.insert\(/);
});

test('StructureNode returns structured error on failure', () => {
  assert.match(structure, /STRUCTURE_ERROR/);
  assert.match(structure, /error: error/);
});
