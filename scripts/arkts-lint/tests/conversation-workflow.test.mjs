import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');
const facade = read('entry/src/main/ets/services/AgentChatService.ets');
const workflow = read('entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets');
const state = read('entry/src/main/ets/workflows/conversation/ConversationState.ets');
const workflowTypes = read('entry/src/main/ets/workflows/conversation/ConversationTypes.ets');
const replyService = read('entry/src/main/ets/services/ReplyService.ets');
const aiService = read('entry/src/main/ets/services/AiService.ets');
const dispatcher = read('agents/src/main/ets/core/Dispatcher.ets');

test('Conversation workflow has independent typed state and shared graph runtime', () => {
  assert.match(state, /interface ConversationState/);
  assert.match(state, /type ConversationRequest/);
  assert.match(state, /type ConversationStep/);
  assert.match(state, /memoryContext\?: string/);
  assert.match(state, /learnerProfileContext\?: string/);
  assert.match(workflow, /StateGraph<ConversationState, ConversationStep>/);
  assert.match(workflow, /addConditionalEdge\('START'/);
  assert.match(workflow, /state\.request\.kind === 'image'/);
  assert.match(workflow, /state\.intent === 'note_generation'/);
  assert.match(workflow, /addNode\('load_reply_context'/);
  assert.match(workflow, /addNode\('save_reply_input'/);
  assert.match(workflow, /addEdge\('load_reply_context', 'save_reply_input'\)/);
  assert.doesNotMatch(workflowTypes, /overlays|ChatStatusMeta|setBusy|setStatusMeta/);
  assert.match(workflow, /replyService\.complete\(/);
  assert.match(workflow, /replyService\.stream\(/);
  assert.match(workflow, /generateNoteDraft\(/);
  assert.match(state, /runRef: ConversationRunRef/);
  assert.doesNotMatch(state, /\n\s*sessionId: string;/);
  assert.doesNotMatch(state, /\n\s*runId: string;/);
  assert.match(workflowTypes, /isCurrentRun\(ref: ConversationRunRef\): boolean/);
  assert.match(workflow, /if \(!this\.cbs\.isCurrentRun\(ref\)\) \{ return; \}/);
  assert.doesNotMatch(workflowTypes, /getSessionId/);
  assert.doesNotMatch(workflow, /new LlmClient|new LlmGuard|new ContentProtocol/);
  assert.equal((workflow.match(/this\.cbs\.onFinish\(runRef\)/g) || []).length, 1);
  assert.match(replyService, /class ReplyService/);
});

test('AgentChatService exposes only the active image and streaming text run entries', () => {
  assert.match(facade, /class AgentChatService/);
  assert.match(facade, /async captureReply/);
  assert.match(facade, /async realReplyStream/);
  assert.doesNotMatch(facade, /async realReply\(/);
  // LOC is not a stable contract: callback adapters and public draft
  // lifecycle methods may grow without moving orchestration into the facade.
  // Assert the ownership boundary directly instead of enforcing a line cap.
  assert.match(facade, /this\.workflow = new ConversationWorkflow\(this\.adapter\)/);
  assert.doesNotMatch(facade, /new LlmClient|new AiService|new AgentMemoryService/);
  assert.match(facade, /private readonly coordinator: ConversationRunCoordinator/);
  assert.match(facade, /private async executeAcceptedOperation<T>/);
  assert.match(facade, /return this\.coordinator\.start\(sessionId, request\)/);
  assert.equal((facade.match(/catch \(error\)/g) || []).length, 1);
  assert.doesNotMatch(facade, /JSON\.stringify\(error\)/);
});

test('Conversation note generation delegates to the canonical Capture entry', () => {
  assert.match(workflow, /generateNoteDraft\(/);
  assert.doesNotMatch(workflow, /new CaptureGraph|dispatcher\.buildGraph\(/);
});

test('Issue 99 note intent produces a typed preview and confirms the exact checkpoint candidate', () => {
  assert.match(workflowTypes, /onDraftReady/);
  assert.match(state, /draftStatus\?: 'ready-preview'/);
  assert.match(workflow, /onDraftReady/);
  assert.match(aiService, /result: generation/);
  assert.doesNotMatch(workflow, /summarizeNoteMaterial/);
  assert.doesNotMatch(workflow, /captureText\(/);
  assert.match(aiService, /generation:/);
  assert.match(aiService, /persist: false/);
  assert.match(dispatcher, /preparedCandidate/);
  assert.match(dispatcher, /checkpointId/);
  assert.match(dispatcher, /candidateHash/);
  assert.match(dispatcher, /buildPreparedGraph/);
});

test('Conversation workflow owns typed intent classification and routes from its state', () => {
  assert.match(workflow, /addNode\('classify_intent'/);
  assert.match(workflow, /intentClassifier\.classify\(/);
  assert.match(workflow, /addConditionalEdge\('classify_intent'/);
  assert.match(workflow, /state\.intent === 'note_generation'/);
});

test('ReplyService falls back when a successful stream produces no displayable content', () => {
  assert.match(replyService, /private shouldUseFallback\(content: string\): boolean/);
  assert.match(replyService, /return content\.trim\(\)\.length === 0/);
  assert.match(replyService, /stream empty, using fallback/);
});

test('ReplyService retries a pre-response transport failure once and does not duplicate fallback requests', () => {
  assert.match(replyService, /while \(streamAttempts < 2\)/);
  assert.match(replyService, /!receivedEvent && ReplyService\.isNetworkError\(e\)/);
  assert.match(replyService, /stream transport failed before first event, retrying once/);
  // Transport errors are rethrown with their typed LlmError kind. Keep the
  // retry boundary observable without coupling this test to an old helper
  // name or catch-branch ordering.
  assert.match(replyService, /if \(e instanceof LlmError\) \{[\s\S]*?throw new LlmError\(e\.message, e\.kind\)/);
  assert.match(replyService, /e\.kind === 'NETWORK_ERROR' \|\| e\.kind === 'TIMEOUT' \|\| e\.kind === 'STREAM_FAILED'/);
});

test('Conversation workflow hides DNS and timeout details behind a stable network message', () => {
  assert.match(workflow, /private static isNetworkError\(e: Object\): boolean/);
  assert.match(workflow, /e\.kind === 'NETWORK_ERROR' \|\| e\.kind === 'TIMEOUT'/);
  assert.match(workflow, /'failed to resolve'/);
  assert.match(workflow, /'couldn\\'t connect to server'/);
  assert.match(workflow, /'connection timed out'/);
  assert.match(workflow, /ConversationWorkflow\.isNetworkError\(e\)/);
  assert.doesNotMatch(workflow, /errMsg\.indexOf\('NETWORK_ERROR'\)/);
});

test('Conversation workflow finishes the streaming placeholder when the request fails', () => {
  assert.match(workflow, /let streamMsgId: number \| undefined = undefined/);
  assert.match(workflow, /streamMsgId = msgId/);
  assert.match(workflow, /if \(streamMsgId !== undefined\) \{\s*await this\.appendAssistantReply\(ref, displayError, streamMsgId\)/);
  assert.match(workflow, /\} else \{\s*await this\.addAiMessage\(ref, displayError\)/);
});
