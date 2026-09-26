import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

test('Conversation coordinator owns cancellation, child hooks, and fixed capacity two', () => {
  const source = read('entry/src/main/ets/services/ConversationRunCoordinator.ets');
  assert.match(source, /static readonly MAX_ACTIVE_RUNS: number = 2/);
  assert.match(source, /code=RUN_CAPACITY/);
  assert.match(source, /cancellationToken\(ref: ConversationRunRef\)/);
  assert.match(source, /registerCancellationHook\(ref: ConversationRunRef/);
  assert.match(source, /cancelAll\(\)/);
  assert.match(source, /current\.cancellation\.cancel\(\)/);
});

test('Cancellation reaches transport, retry/fallback, workflow, and lifecycle owners', () => {
  const client = read('common/src/main/ets/llm/LlmClient.ets');
  const reply = read('entry/src/main/ets/services/ReplyService.ets');
  const workflow = read('entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets');
  const service = read('entry/src/main/ets/services/AgentChatService.ets');
  const runtime = read('entry/src/main/ets/services/ConversationRuntime.ets');
  const window = read('entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets');
  assert.match(client, /request\.cancellationToken\?\.onCancel/);
  assert.match(client, /httpRequest\.destroy\(\)/);
  assert.match(client, /CONVERSATION_CANCELLED/);
  assert.match(reply, /cancellationToken\?\.throwIfCancelled\(\)/);
  assert.match(reply, /cancellationToken: cancellationToken/);
  assert.match(workflow, /this\.cbs\.getCancellationToken\(runRef\)/);
  assert.match(workflow, /safeSaveAssistantMessage/);
  assert.match(service, /cancelSessionRun\(sessionId: string\)/);
  assert.match(service, /this\.runtime\.cancelSessionRun\(sessionId\)/);
  assert.match(runtime, /this\.coordinator\.cancel\(ref\)/);
  assert.match(window, /this\.service\?\.cancelAllRuns\(\)/);
  assert.match(window, /private switchSession\(sid: string\)/);
  const switchBody = window.match(/private switchSession[\s\S]*?\n  private newSession/);
  assert.ok(switchBody !== null);
  assert.doesNotMatch(switchBody[0], /cancelSessionRun/);
});
