import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const stateFile = readFileSync(resolve(root, 'agents/src/main/ets/graph/AgentState.ets'), 'utf8');
const graphFile = readFileSync(resolve(root, 'agents/src/main/ets/graph/CaptureGraph.ets'), 'utf8');
const testFile = readFileSync(resolve(root, 'agents/src/test/CaptureGraph.test.ets'), 'utf8');

test('CaptureGraph defines typed graph state and error fields', () => {
  assert.match(stateFile, /interface AgentState/);
  assert.match(stateFile, /captureText/);
  assert.match(stateFile, /classification\?/);
  assert.match(stateFile, /knowledgeUnit\?/);
  assert.match(stateFile, /truthCheck\?/);
  assert.match(stateFile, /error\?/);
  assert.match(stateFile, /currentStep/);
  assert.match(stateFile, /persist/);
  assert.match(stateFile, /interface CaptureGraphError/);
  assert.match(stateFile, /retriable/);
});

test('CaptureGraph exposes nodes, edges, conditional routing, and run', () => {
  assert.match(graphFile, /class CaptureGraph/);
  assert.match(graphFile, /addNode/);
  assert.match(graphFile, /addEdge/);
  assert.match(graphFile, /addConditionalEdge/);
  assert.match(graphFile, /async run/);
  assert.match(graphFile, /while \(current !== 'END'\)/);
});

test('CaptureGraph tests cover persist false, default persist, and error short circuit', () => {
  assert.match(testFile, /persist_false_skips_persist_node/);
  assert.match(testFile, /default_path_runs_persist_node/);
  assert.match(testFile, /node_error_short_circuits_to_end/);
  assert.match(testFile, /input\.persist \? 'persist' : 'END'/);
});
