import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');

const llmClient = read('common/src/main/ets/llm/LlmClient.ets');
const replyService = read('entry/src/main/ets/services/ReplyService.ets');

test('LlmClient.callStreamInternal firstByteTimer must be a sane guard (5s..30s)', () => {
  const firstByteMatch = llmClient.match(/firstByteTimer[\s\S]*?setTimeout[\s\S]*?,\s*(\d+)\s*\)/);
  assert.ok(firstByteMatch !== null, 'firstByteTimer setTimeout call must exist');
  const ms = parseInt(firstByteMatch[1], 10);
  // 15s 是当前取值：太长会让用户干等，太短会误降级；上限锁 30s 防回退成大值
  assert.ok(ms >= 5000 && ms <= 30000, `firstByteTimer must be within 5000..30000ms, got ${ms}ms`);
});

test('ReplyService reply paths inherit enableThinking from LlmClient config', () => {
  assert.doesNotMatch(replyService, /enableThinking\s*:\s*false/);
});

test('LlmClient maps enableThinking to the Qwen HTTP switch on both transports', () => {
  const qwenSwitches = llmClient.match(/enable_thinking/g) ?? [];
  assert.ok(qwenSwitches.length >= 2, 'JSON and SSE request bodies must both carry enable_thinking');
  assert.match(llmClient, /body\.enable_thinking\s*=\s*enableThinking/);
  assert.match(llmClient, /bodyObj\[.enable_thinking.\]\s*=\s*enableThinking/);
  assert.doesNotMatch(llmClient, /chat_template_kwargs/);
});

test('LlmClient requestInStream callback tolerates undefined status data', () => {
  assert.match(
    llmClient,
    /private streamCallbackCode\(data: number \| undefined\): string[\s\S]*?return data\.toString\(\)/,
    'requestInStream callback logging must stringify undefined status data safely',
  );
  assert.doesNotMatch(
    llmClient,
    /requestInStream cb err=[\s\S]*?data\.toString\(\)/,
    'requestInStream callback must not call data.toString() directly',
  );
});

test('LlmClient normalizes stream transport failures as network errors', () => {
  assert.match(
    llmClient,
    /'LLM stream request failed: ' \+ err\.message,[\s\S]*?'NETWORK_ERROR'/,
    'stream transport failures must use the shared network error kind',
  );
});

test('ReplyService fallback does not override enableThinking', () => {
  const fallbackMatch = replyService.match(/private async fallback[\s\S]*?\n  \}/);
  assert.ok(fallbackMatch !== null, 'ReplyService fallback call must exist');
  assert.match(fallbackMatch[0], /this\.guardedComplete\(context, 'chat answer fallback'\)/);
  assert.doesNotMatch(fallbackMatch[0], /client\.call/);
  assert.doesNotMatch(fallbackMatch[0], /fallback\.text/);
  assert.doesNotMatch(fallbackMatch[0], /enableThinking\s*:/);
});
