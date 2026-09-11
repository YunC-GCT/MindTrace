import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import test from 'node:test';

const root = resolve(import.meta.dirname, '../../..');
const read = (file) => readFileSync(resolve(root, file), 'utf8');

const dispatcher = read('agents/src/main/ets/core/Dispatcher.ets');
const knowledgeModel = read('agents/src/main/ets/agents/KnowledgeModel.ets');
const truthCheckNode = read('agents/src/main/ets/graph/nodes/TruthCheckNode.ets');
const persistNode = read('agents/src/main/ets/graph/nodes/PersistNode.ets');
const llmClient = read('common/src/main/ets/llm/LlmClient.ets');
const repository = read('entry/src/main/ets/database/NoteGenerationRepository.ets');
const memoryDao = read('entry/src/main/ets/database/AgentMemoryDao.ets');
const memoryService = read('entry/src/main/ets/services/AgentMemoryService.ets');
const workflow = read('entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets');
const aiService = read('entry/src/main/ets/services/AiService.ets');
const agentTool = read('common/src/main/ets/tools/ToolCatalog.ets');
const generationTests = read('entry/src/test/DispatcherNoteGeneration.test.ets');
const repositoryTests = read('entry/src/test/NoteGenerationRepository.test.ets');
const incrementalTests = read('entry/src/test/IncrementalRegeneration.test.ets');

const withoutComments = (text) => text
  .replace(/\/\/.*$/gm, '')
  .replace(/\/\*[\s\S]*?\*\//g, '');

test('Issue 105 removes the old summarize-then-persist route and duplicate source gate', () => {
  assert.doesNotMatch(workflow, /summarizeNoteMaterial|material_summary/);
  assert.doesNotMatch(aiService, /summarizeNoteMaterial|material_summary/);
  assert.doesNotMatch(dispatcher, /inputSourceIssues/);
  assert.equal((dispatcher.match(/validateSourceBundle\(/g) || []).length, 1);
});

test('Issue 105 consumes only explicitly referenced pending source ids', () => {
  assert.doesNotMatch(memoryDao, /markPendingUsed\(sessionId/);
  assert.doesNotMatch(memoryService, /markPendingMaterialUsed\(sessionId/);
  assert.doesNotMatch(repository, /consumePendingSources/);
  assert.match(memoryService, /markPendingMaterialsUsed\(sourceIds: string\[\]/);
});

test('Issue 105 keeps workflow ownership and topology single-sourced', () => {
  const workflowSource = withoutComments(workflow);
  const aiServiceSource = withoutComments(aiService);
  assert.doesNotMatch(workflowSource, /CaptureGraph|AgentState|NoteDao/);
  assert.doesNotMatch(aiServiceSource, /import[\s\S]*CaptureGraph|import[\s\S]*AgentState/);
  assert.doesNotMatch(knowledgeModel, /TruthCheckService|truthCheckService\.check/);
  assert.match(truthCheckNode, /service\.check\(/);
  assert.match(persistNode, /dao\.insert\(input\.knowledgeUnit\)/);
  assert.equal((llmClient.match(/public async call\(/g) || []).length, 1);
  assert.doesNotMatch(agentTool, /createWrite|writeNote|insert\(|update\(|delete/);
});

test('Issue 105 production logs contain metadata only, never generated content', () => {
  assert.doesNotMatch(knowledgeModel, /console\.(info|log).*title=|console\.(info|log).*summary=|console\.(info|log).*content/);
  assert.doesNotMatch(aiService, /KnowledgeUnit dump|console\.(info|log).*content|console\.(info|log).*summary/);
  assert.doesNotMatch(dispatcher, /console\.(info|log).*candidate|console\.(info|log).*document|console\.(info|log).*evidence/);
});

test('Issue 105 acceptance scenarios have executable Hypium coverage', () => {
  for (const scenario of [
    'runId: \'light-98\'', 'runId: \'standard-101\'', 'runId: \'deep-103\'',
    'runId: \'needs-input-101\'', 'runId: \'repair-102\'',
    'diminishing_returns', 'rollback', 'ready-preview', 'cancelRun', 'restore',
    'duplicate', 'regenerate', 'VERSION_CONFLICT',
  ]) {
    assert.match(generationTests + repositoryTests + incrementalTests, new RegExp(scenario.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
      'missing acceptance scenario coverage: ' + scenario);
  }
  assert.match(generationTests, /persist=false|persist: false/);
  assert.match(generationTests, /checkpointSaves/);
  assert.match(repositoryTests, /same id|repeated confirmation/);
  assert.match(incrementalTests, /preserves locked and untargeted/);
});
