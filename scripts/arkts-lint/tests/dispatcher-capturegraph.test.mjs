import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const dispatcher = readFileSync(resolve(root, 'agents/src/main/ets/core/Dispatcher.ets'), 'utf8');
const captureBranch = readFileSync(resolve(root, 'agents/src/main/ets/core/dispatch/CaptureBranch.ets'), 'utf8');
const noteAgent = readFileSync(resolve(root, 'agents/src/main/ets/agents/NoteAgent.ets'), 'utf8');
const aiService = readFileSync(resolve(root, 'entry/src/main/ets/services/AiService.ets'), 'utf8');
const agentsIndex = readFileSync(resolve(root, 'agents/src/main/ets/Index.ets'), 'utf8');
const captureTypes = readFileSync(resolve(root, 'common/src/main/ets/models/CaptureChain.ets'), 'utf8');

test('Dispatcher exposes single dispatch entry only', () => {
  assert.equal((dispatcher.match(/async dispatch\(/g) || []).length, 1);
  assert.match(dispatcher, /async dispatch\(req: DispatchRequest, options: DispatchOptions = \{\}\)/);
  assert.equal((dispatcher.match(/async analyze\(/g) || []).length, 0);
  assert.equal((dispatcher.match(/async routeDispatch\(/g) || []).length, 0);
});

test('NoteAgent owns CaptureGraph construction and DAO injection internally', () => {
  assert.match(noteAgent, /private buildGraph\(\): CaptureGraph/);
  assert.match(noteAgent, /PersistNodeFactory\.create\(dao\)/);
  assert.match(noteAgent, /addConditionalEdge\('classify'/);
  assert.match(noteAgent, /input\.analysisOnly \? 'END' : 'structure'/);
  assert.match(noteAgent, /addConditionalEdge\('truth_check', .*persist \? 'persist' : 'END'\)/);
  assert.match(noteAgent, /addEdge\('persist', 'END'\)/);
  assert.match(noteAgent, /PERSIST_DAO_REQUIRED/);
  assert.doesNotMatch(noteAgent, /addNode\('persist', async \(input: AgentState\) => \(\{ state: input \}\)\)/);
});

test('Dispatcher delegates capture to CaptureBranch which runs NoteAgent (2026-10-31 拆分)', () => {
  assert.match(dispatcher, /CaptureBranch\.dispatchCapture\(req, options, this\.resolveRunContext\(options\), t0\)/);
  assert.match(captureBranch, /new NoteAgent\(/);
  assert.match(captureBranch, /noteAgent\.run\(initial, runContext\)/);
  assert.doesNotMatch(dispatcher, /private buildGraph\(/);
  assert.doesNotMatch(dispatcher, /new TypeClassifier\(/);
  assert.doesNotMatch(captureBranch, /private buildGraph\(/);
});

test('NoteAgent instantiates one shared TypeClassifier inside buildGraph', () => {
  assert.equal((noteAgent.match(/new TypeClassifier\(/g) || []).length, 1);
});

test('AiService consumes Capture workflow only through Dispatcher.dispatch', () => {
  assert.doesNotMatch(aiService, /import \{[^}]*\bCaptureGraph\b/);
  assert.doesNotMatch(aiService, /import \{[^}]*\bAgentState\b/);
  assert.doesNotMatch(aiService, /\.buildGraph\(/);
  assert.match(aiService, /dispatchCommand\(command/);
  assert.match(aiService, /kind: 'analysisOnly'/);
});

test('Capture graph and state stay internal to agents module', () => {
  assert.doesNotMatch(agentsIndex, /export \{ CaptureGraph \}/);
  assert.doesNotMatch(agentsIndex, /AgentState/);
  assert.doesNotMatch(agentsIndex, /CaptureNode/);
});

test('DispatchResult carries analysis channels for persist false callers', () => {
  assert.match(captureTypes, /interface DispatchResult \{[^}]*classification\?: ClassificationResult/);
  assert.match(captureTypes, /interface DispatchResult \{[^}]*recognizedText\?: string/);
});
