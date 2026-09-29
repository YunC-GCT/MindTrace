import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const dispatcher = readFileSync(resolve(root, 'agents/src/main/ets/core/Dispatcher.ets'), 'utf8');
const aiService = readFileSync(resolve(root, 'entry/src/main/ets/services/AiService.ets'), 'utf8');
const agentsIndex = readFileSync(resolve(root, 'agents/src/main/ets/Index.ets'), 'utf8');
const captureTypes = readFileSync(resolve(root, 'common/src/main/ets/models/CaptureChain.ets'), 'utf8');

test('Dispatcher exposes single dispatch entry only', () => {
  assert.equal((dispatcher.match(/async dispatch\(/g) || []).length, 1);
  assert.match(dispatcher, /async dispatch\(req: DispatchRequest, options: DispatchOptions = \{\}\)/);
  assert.equal((dispatcher.match(/async analyze\(/g) || []).length, 0);
  assert.equal((dispatcher.match(/async routeDispatch\(/g) || []).length, 0);
});

test('Dispatcher owns CaptureGraph construction and DAO injection internally', () => {
  assert.match(dispatcher, /private buildGraph\(options: DispatchOptions = \{\}\): CaptureGraph/);
  assert.match(dispatcher, /PersistNodeFactory\.create\(options\.dao\)/);
  assert.match(dispatcher, /addConditionalEdge\('classify'/);
  assert.match(dispatcher, /input\.analysisOnly \? 'END' : 'structure'/);
  assert.match(dispatcher, /addConditionalEdge\('truth_check', .*persist \? 'persist' : 'END'\)/);
  assert.match(dispatcher, /addEdge\('persist', 'END'\)/);
  assert.match(dispatcher, /PERSIST_DAO_REQUIRED/);
  assert.doesNotMatch(dispatcher, /addNode\('persist', async \(input: AgentState\) => \(\{ state: input \}\)\)/);
});

test('Dispatcher instantiates one shared TypeClassifier inside buildGraph', () => {
  assert.equal((dispatcher.match(/new TypeClassifier\(/g) || []).length, 1);
});

test('AiService consumes Capture workflow only through Dispatcher.dispatch', () => {
  assert.doesNotMatch(aiService, /import \{[^}]*\bCaptureGraph\b/);
  assert.doesNotMatch(aiService, /import \{[^}]*\bAgentState\b/);
  assert.doesNotMatch(aiService, /\.buildGraph\(/);
  assert.match(aiService, /dispatcher\.dispatch\(/);
  assert.match(aiService, /analysisOnly: true/);
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
