import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import ts from 'typescript';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');
const facade = read('entry/src/main/ets/services/AgentChatService.ets');
const runtime = read('entry/src/main/ets/services/ConversationRuntime.ets');
const workflow = read('entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets');
const memoryProjection = read('entry/src/main/ets/workflows/conversation/ConversationMemoryProjection.ets');
const state = read('entry/src/main/ets/workflows/conversation/ConversationState.ets');
const workflowTypes = read('entry/src/main/ets/workflows/conversation/ConversationTypes.ets');
const replyService = read('entry/src/main/ets/services/ReplyService.ets');
const aiService = read('entry/src/main/ets/services/AiService.ets');
const dispatcher = read('agents/src/main/ets/core/Dispatcher.ets');

// Execute the real error delivery boundary, with only platform imports removed.
const withoutImports = (source) => source.replace(/import\s+(?:type\s+)?\{[\s\S]*?\}\s+from\s+'[^']+';\s*/g, '');
const errorHarness = ts.transpileModule(
  'class Logger {}\nclass LlmError extends Error {}\n'
    + withoutImports(read('common/src/main/ets/llm/LlmErrorBodyFormatter.ets'))
    + withoutImports(read('entry/src/main/ets/services/NoteRetrievalQuery.ets'))
    + withoutImports(read('entry/src/main/ets/services/NoteEvidenceService.ets'))
    + withoutImports(workflow),
  { compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 } },
).outputText;
const { ConversationWorkflow, NoteEvidenceService } = await import('data:text/javascript;base64,' + Buffer.from(errorHarness).toString('base64'));

test('ordinary reply visibly distinguishes a retrieval miss from an unavailable database', () => {
  const instance = Object.create(ConversationWorkflow.prototype);
  instance.evidenceService = new NoteEvidenceService();
  const evidence = { query: '极限', topK: 5, citations: [], relations: [], contextText: '', degraded: false, reason: 'no-match' };
  assert.match(instance.applyEvidenceToAnswer(evidence, '普通回答'), /笔记检索：未命中/);
  assert.match(instance.applyEvidenceToAnswer({ ...evidence, degraded: true, reason: 'search-failed' }, '普通回答'), /笔记检索：失败/);
  assert.equal(instance.applyEvidenceToAnswer(undefined, '图片回答'), '图片回答');
});

test('stream, complete and stream fallback render and persist exactly one retrieval result', async () => {
  const base = { query: '极限', topK: 5, citations: [], relations: [], contextText: '', degraded: false, reason: 'no-match' };
  const hit = { noteId: 'limit', version: 1, title: '极限定义', excerpt: '极限定义', role: 'hit', score: 4, matchedFields: ['title'] };
  for (const mode of ['stream', 'complete', 'fallback']) {
    for (const evidence of [base, { ...base, citations: [hit], reason: '' }, { ...base, degraded: true, reason: 'search-failed' }]) {
      const instance = Object.create(ConversationWorkflow.prototype);
      const saved = [];
      let displayed = '';
      let finished = 0;
      instance.evidenceService = new NoteEvidenceService();
      instance.cancellationTokens = new Map();
      instance.runOrigins = new Map();
      instance.reportedErrorRuns = new Set();
      instance.memoryProjection = {
        async saveAssistant(_ref, content) { saved.push(content); },
        async updateLearnerProfile() {}, async summarize() {},
      };
      instance.cbs = {
        isCurrentRun: () => true, onProgress() {},
        addAiMsgEmpty: () => 42,
        addAiMsg(_ref, content, _origin, outcome) { displayed = content; if (outcome === 'completed') { finished += 1; } return 42; },
        updateAiMsg(_ref, _id, event) {
          if (event.kind === 'replace-content') { displayed = event.content; }
          else if (event.event.type === 'text') { displayed += event.event.delta; }
        },
        finishAiMsg() { finished += 1; },
        onError(_ref, message) { assert.fail(message); },
      };
      instance.replyService = {
        isConfigured: async () => true,
        normalize: (text) => text,
        complete: async () => '极限回答',
        async stream(_context, sink) {
          if (mode !== 'fallback') { sink({ type: 'text', delta: '极限回答' }); }
          return { content: '极限回答', usedFallback: mode === 'fallback', interrupted: false };
        },
      };
      const ref = { sessionId: 's1', runId: 'r1' };
      if (mode === 'complete') {
        await instance.handleCompleteReply(ref, '', '', '解释极限', evidence, undefined);
      } else {
        await instance.handleStreamReply(ref, '', '', '解释极限', evidence, undefined);
      }
      assert.deepEqual(saved, [displayed], mode);
      assert.equal((displayed.match(/笔记检索：/g) ?? []).length, 1, mode);
      assert.match(displayed, evidence.citations.length > 0 ? /命中 1 条/ : evidence.degraded ? /失败/ : /未命中/);
      assert.equal(finished, 1);
    }
  }
});

test('unexpected retrieval exception remains observable instead of looking like retrieval was skipped', async () => {
  const instance = Object.create(ConversationWorkflow.prototype);
  instance.evidenceService = { async build() { throw new Error('test-query-failure'); } };
  const result = await instance.safeBuildEvidence('极限');
  assert.equal(result.degraded, true);
  assert.equal(result.reason, 'search-failed');
});

function deliveredFailure(error) {
  const messages = [];
  const instance = Object.create(ConversationWorkflow.prototype);
  instance.reportedErrorRuns = new Set();
  instance.cbs = { onError: (_ref, message) => messages.push(message) };
  const ref = { sessionId: 'session', runId: 'run' };
  instance.reportRunError(ref, error);
  instance.reportRunError(ref, error);
  assert.equal(messages.length, 1, 'nested catch blocks must report the reason only once');
  return messages[0];
}

test('note generation failure delivers its actual reason to the frontend', () => {
  const reason = 'standard generation failed: verifier_unavailable: HTTP 429 rate limit';
  assert.ok(deliveredFailure(new Error(reason)).includes(reason));
  assert.match(deliveredFailure(new Error('章节正文为空：请补充题目条件')), /章节正文为空：请补充题目条件/);
});

test('error delivery preserves network reasons and redacts secrets before clipping', () => {
  const display = deliveredFailure(new Error('connection timed out; Authorization: Bearer example-secret; api_key=private-key'));
  assert.match(display, /connection timed out/);
  assert.doesNotMatch(display, /example-secret|private-key/);
  const jsonDetail = deliveredFailure(new Error('HTTP 403 {"api_key":"private-json-key","message":"model denied"}'));
  assert.match(jsonDetail, /model denied/);
  assert.doesNotMatch(jsonDetail, /private-json-key/);
  const longError = deliveredFailure(new Error('校验失败 ' + 'x'.repeat(8000)));
  assert.ok(longError.length < 6500);
  assert.match(longError, /校验失败/);
  assert.match(longError, /已截取/);
  assert.match(deliveredFailure(new Error('原因'.repeat(700) + '第五条：边界极值遗漏')), /第五条：边界极值遗漏/);
});

test('cancellation and missing API key retain their actionable messages', () => {
  assert.equal(deliveredFailure(new Error('CONVERSATION_CANCELLED')), '本轮处理已取消');
  assert.match(deliveredFailure(new Error('NO_API_KEY')), /配置 API Key/);
  assert.match(deliveredFailure(new Error('')), /未提供.*原因/);
});

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
  assert.match(memoryProjection, /if \(!this\.host\.acceptsMemoryRun\(ref\)\) \{ return; \}/);
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
  assert.match(facade, /private readonly runtime: ConversationRuntime/);
  assert.match(facade, /return await this\.runtime\.captureReply/);
  assert.match(facade, /return await this\.runtime\.realReplyStream/);
  assert.doesNotMatch(
    facade,
    /new ConversationWorkflow|new ConversationDraftCoordinator|private readonly coordinator|private readonly inFlight/,
  );
  assert.match(runtime, /this\.workflow = new ConversationWorkflow\(this\.adapter, ports\)/);
  assert.match(runtime, /private readonly coordinator: ConversationRunCoordinator/);
  assert.match(runtime, /private async executeAcceptedOperation<T>/);
  assert.match(runtime, /return this\.coordinator\.start\(sessionId, request\)/);
  assert.doesNotMatch(runtime, /JSON\.stringify\(error\)/);
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

test('Conversation workflow classifies network failures for interruption handling', () => {
  assert.match(workflow, /private static isNetworkError\(e: Object\): boolean/);
  assert.match(workflow, /e\.kind === 'NETWORK_ERROR' \|\| e\.kind === 'TIMEOUT'/);
  assert.match(workflow, /'failed to resolve'/);
  assert.match(workflow, /'couldn\\'t connect to server'/);
  assert.match(workflow, /'connection timed out'/);
  assert.match(workflow, /private static failureOutcome\(error: Object\): ChatMessageOutcome/);
  assert.match(workflow, /ConversationWorkflow\.isNetworkError\(error\) \? 'interrupted' : 'failed'/);
  assert.doesNotMatch(workflow, /errMsg\.indexOf\('NETWORK_ERROR'\)/);
});

test('Conversation workflow records failures as one typed terminal run part', () => {
  assert.match(workflow, /private finishRunFailure\(/);
  assert.match(workflow, /this\.reportRunError\(ref, error\)/);
  assert.match(workflow, /this\.cbs\.finishAiMsg\(ref, messageId, outcome \?\? ConversationWorkflow\.failureOutcome\(error\)\)/);
  assert.doesNotMatch(workflow, /appendAssistantReply\(ref, displayError/);
});

test('Conversation workflow normalizes streamed content through one message event sink', () => {
  assert.match(workflowTypes, /export type ConversationMessageEvent/);
  assert.match(
    workflowTypes,
    /updateAiMsg\(ref: ConversationRunRef, id: number, event: ConversationMessageEvent\): void/,
  );
  assert.doesNotMatch(workflowTypes, /replaceAiMsg/);
  assert.doesNotMatch(workflowTypes, /appendAiMsg/);
  assert.match(workflow, /kind: 'replace-content', content: displayAnswer/);
  assert.doesNotMatch(workflow, /this\.cbs\.replaceAiMsg/);
});
