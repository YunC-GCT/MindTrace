import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const dispatcher = readFileSync(resolve(root, 'agents/src/main/ets/core/CommandExecutor.ets'), 'utf8');
const workflow = readFileSync(resolve(root, 'agents/src/main/ets/workflows/NoteCaptureWorkflow.ets'), 'utf8');
const aiService = readFileSync(resolve(root, 'entry/src/main/ets/services/AiService.ets'), 'utf8');
const agentsIndex = readFileSync(resolve(root, 'agents/src/main/ets/Index.ets'), 'utf8');
const captureTypes = readFileSync(resolve(root, 'common/src/main/ets/models/CaptureChain.ets'), 'utf8');

test('Dispatcher exposes only the command entry (A4 4c Step2)', () => {
  assert.equal((dispatcher.match(/async dispatch\(/g) || []).length, 0);
  assert.match(dispatcher, /async dispatchCommand\(/);
  assert.equal((dispatcher.match(/async analyze\(/g) || []).length, 0);
  assert.equal((dispatcher.match(/async routeDispatch\(/g) || []).length, 0);
});

test('NoteCaptureWorkflow owns CaptureGraph construction and DAO/port injection internally', () => {
  assert.match(workflow, /private buildGraph\(options: DispatchOptions\): CaptureGraph/);
  assert.match(workflow, /PersistNodeFactory\.create\(dao\)/);
  assert.match(workflow, /addConditionalEdge\('classify'/);
  assert.match(workflow, /input\.analysisOnly \? 'END' : 'structure'/);
  assert.match(workflow, /addConditionalEdge\('truth_check', .*persist \? 'persist' : 'END'\)/);
  assert.match(workflow, /addEdge\('persist', 'END'\)/);
  assert.match(workflow, /PERSIST_DAO_REQUIRED/);
  assert.doesNotMatch(workflow, /addNode\('persist', async \(input: AgentState\) => \(\{ state: input \}\)\)/);
});

test('CommandExecutor delegates capture to NoteCaptureWorkflow (spec 039 S2)', () => {
  assert.match(dispatcher, /NoteCaptureWorkflow/);
  assert.match(workflow, /this\.buildGraph\(options\)\.run\(initial, runContext\)/);
  assert.doesNotMatch(dispatcher, /private buildGraph\(/);
  assert.doesNotMatch(dispatcher, /new TypeClassifier\(/);
  assert.doesNotMatch(workflow, /new NoteAgent\(/);
  assert.doesNotMatch(workflow, /CaptureBranch\.dispatchCapture/);
});

test('NoteCaptureWorkflow instantiates one shared TypeClassifier inside buildGraph', () => {
  assert.equal((workflow.match(/new TypeClassifier\(/g) || []).length, 1);
});

test('AiService consumes Capture workflow only through Dispatcher.dispatch', () => {
  assert.doesNotMatch(aiService, /import \{[^}]*\bCaptureGraph\b/);
  assert.doesNotMatch(aiService, /import \{[^}]*\bAgentState\b/);
  assert.doesNotMatch(aiService, /\.buildGraph\(/);
  const capture = readFileSync(resolve(root, 'entry/src/main/ets/services/ai/CapturePipeline.ets'), 'utf8');
  assert.match(capture, /dispatchCommand\(command/);
  assert.match(capture, /kind: 'analysisOnly'/);
});

test('Capture graph and state stay internal to agents module', () => {
  assert.doesNotMatch(agentsIndex, /export \{ CaptureGraph \}/);
  assert.doesNotMatch(agentsIndex, /AgentState/);
  assert.doesNotMatch(agentsIndex, /CaptureNode/);
});

;
