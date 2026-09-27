import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

const facade = read('entry/src/main/ets/services/AgentChatService.ets');
const contracts = read('entry/src/main/ets/services/AgentChatContracts.ets');
const adapter = read('entry/src/main/ets/services/ConversationWorkflowAdapter.ets');
const ports = read('entry/src/main/ets/workflows/conversation/ConversationWorkflowPorts.ets');
const types = read('entry/src/main/ets/workflows/conversation/ConversationTypes.ets');
const workflow = read('entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets');
const reducer = read('entry/src/main/ets/services/ConversationSessionReducer.ets');
const models = read('entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatModels.ets');
const runModels = read('entry/src/main/ets/overlays/AgentFloatWindow/chat/AgentRunModels.ets');
const windowSource = read('entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets');
const aiService = read('entry/src/main/ets/services/AiService.ets');

test('workflow status and errors use the typed ordered run event sink', () => {
  assert.match(types, /kind: 'status'/);
  assert.match(types, /kind: 'error'/);
  assert.match(types, /onError\(ref: ConversationRunRef, message: string\): void/);
  assert.match(adapter, /this\.callbacks\.updateRunEvent\(ref, event\)/);
  assert.match(workflow, /this\.reportRunError\(runRef, error\)/);
  assert.match(workflow, /this\.cbs\.onError\(ref, ConversationWorkflow\.userFacingWorkflowError\(error\)\)/);
  const handledFailureReports = workflow.match(/this\.finishRunFailure\([^;]+\);/g) ?? [];
  assert.ok(handledFailureReports.length >= 4);
  assert.doesNotMatch(adapter, /setStatusMeta/);
});

test('status and error events update run parts without changing answer content', () => {
  assert.match(reducer, /appendChatMsgStatus\(message, event\.content, event\.status, event\.progressKey\)/);
  assert.match(reducer, /appendChatMsgError\(message, event\.content\)/);
  assert.match(
    models,
    /appendAgentRunStatus\(chatMessageRunParts\(message\), message\.id, content, status, progressKey\)/,
  );
  assert.match(models, /appendAgentRunError\(chatMessageRunParts\(message\), message\.id, content\)/);
  assert.match(windowSource, /message\.role === 'ai' && message\.runId === ref\.runId/);
});

test('note progress updates one stable card per phase', () => {
  assert.match(types, /progressKey\?: string/);
  assert.match(reducer, /event\.progressKey/);
  assert.match(runModels, /progressKey\?: string/);
  assert.match(runModels, /part\.progressKey === progressKey/);
  assert.match(runModels, /existing\.content = content/);
  assert.match(runModels, /existing\.status = status/);
});

test('conversation forwards real note progress without legacy note status steps', () => {
  assert.match(ports, /NoteGenerationProgressSink/);
  assert.match(ports, /progressSink\?: NoteGenerationProgressSink/);
  assert.match(aiService, /progressSink: progressSink/);
  assert.match(types, /onNoteGenerationProgress\(ref: ConversationRunRef, event: NoteGenerationProgressEvent\): void/);
  assert.match(workflow, /this\.cbs\.onNoteGenerationProgress\(ref, event\)/);
  assert.match(adapter, /progressKey: 'note-generation:' \+ progress\.phase/);
  assert.doesNotMatch(workflow, /this\.setStep\(ref, 'note_(intent_check|context_load|source_prepare|structure_save|finalize)'\)/);
});

test('ordinary chat request types cannot carry note-generation route state', () => {
  const state = read('entry/src/main/ets/workflows/conversation/ConversationState.ets');
  assert.doesNotMatch(state, /route\?: NoteGenerationRoute/);
  assert.doesNotMatch(facade, /realReplyStream\([^)]*NoteGenerationRoute/);
  assert.doesNotMatch(contracts, /getNoteGenerationRoute/);
  assert.doesNotMatch(adapter, /getNoteGenerationRoute/);
  assert.match(ports, /interface IConversationNoteRoutePort/);
  assert.match(workflow, /this\.noteRoute\.select\(input\.runRef\)/);
});
