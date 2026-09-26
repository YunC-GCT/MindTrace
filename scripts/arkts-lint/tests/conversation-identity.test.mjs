import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

test('identity policies are distinct and session fallback is removed', () => {
  const identity = read('entry/src/main/ets/services/ConversationIdentity.ets');
  const workflow = read('entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets');
  const session = read('entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatSession.ets');
  const window = read('entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets');
  assert.match(identity, /class SessionIdPolicy/);
  assert.match(identity, /class ConversationRunIdPolicy/);
  assert.match(identity, /class ChatMessageIdPolicy/);
  assert.match(identity, /PROFILE_GLOBAL_SCOPE_ID/);
  assert.doesNotMatch(workflow, /return sessionId\.length > 0 \? sessionId : 's1'/);
  assert.doesNotMatch(session, /Date\.now\(\)\.toString\(36\)/);
  assert.match(window, /chatMessageIdPolicy\.create\(\)/);
});

test('run coordinator and snapshot decoder expose the required seams', () => {
  const coordinator = read('entry/src/main/ets/services/ConversationRunCoordinator.ets');
  const persistence = read('entry/src/main/ets/services/ChatHistoryPersistence.ets');
  const service = read('entry/src/main/ets/services/AgentChatService.ets');
  const runtime = read('entry/src/main/ets/services/ConversationRuntime.ets');
  const adapter = read('entry/src/main/ets/services/ConversationWorkflowAdapter.ets');
  const reducer = read('entry/src/main/ets/services/ConversationSessionReducer.ets');
  assert.match(coordinator, /start\(sessionId: string, request: ConversationRunRequest\)/);
  assert.match(coordinator, /isCurrent\(ref: ConversationRunRef\)/);
  assert.match(coordinator, /finish\(ref: ConversationRunRef/);
  assert.match(service, /private readonly runtime: ConversationRuntime/);
  assert.doesNotMatch(service, /private readonly coordinator|executeAcceptedOperation<T>/);
  assert.match(runtime, /private readonly coordinator: ConversationRunCoordinator/);
  assert.match(runtime, /const request: ConversationRunRequest = \{ kind: kind \}/);
  assert.match(runtime, /return this\.coordinator\.start\(sessionId, request\)/);
  assert.match(runtime, /executeAcceptedOperation<T>/);
  assert.match(persistence, /export function decodeChatHistorySnapshot/);
  assert.match(persistence, /unsupported-version/);
  assert.match(persistence, /CHAT_HISTORY_SCHEMA_VERSION/);
  assert.match(persistence, /CHAT_HISTORY_DECODER_CATALOG/);
  assert.match(persistence, /decodeChatHistorySnapshotV1/);
  assert.match(reducer, /class ConversationSessionReducer/);
  assert.match(reducer, /DUPLICATE_CHAT_MESSAGE_ID/);
  assert.match(adapter, /code=STALE_RUN_EVENT/);
  assert.match(service, /cancelSessionRun\(sessionId: string\)/);
  assert.doesNotMatch(service, /activeRuns|busyRunCount/);
});
