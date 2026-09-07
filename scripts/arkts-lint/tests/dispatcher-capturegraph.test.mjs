import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const dispatcher = readFileSync(resolve(root, 'agents/src/main/ets/core/Dispatcher.ets'), 'utf8');

test('Dispatcher exposes single dispatch entry only', () => {
  assert.equal((dispatcher.match(/async dispatch\(/g) || []).length, 1);
  assert.equal((dispatcher.match(/async analyze\(/g) || []).length, 0);
  assert.equal((dispatcher.match(/async routeDispatch\(/g) || []).length, 0);
});

test('Dispatcher injects NoteDaoInterface into CaptureGraph via buildGraph', () => {
  assert.match(dispatcher, /buildGraph\(req: DispatchRequest, options: DispatchOptions = \{\}\): CaptureGraph/);
  assert.match(dispatcher, /PersistNodeFactory\.create\(options\.dao\)/);
  assert.match(dispatcher, /addConditionalEdge\('truth_check', .*persist \? 'persist' : 'END'\)/);
});

test('Dispatcher instantiates one shared TypeClassifier inside buildGraph', () => {
  assert.equal((dispatcher.match(/new TypeClassifier\(/g) || []).length, 1);
});