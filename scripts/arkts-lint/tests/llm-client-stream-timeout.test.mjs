import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');

const llmClient = read('common/src/main/ets/llm/LlmClient.ets');
const replyService = read('entry/src/main/ets/services/ReplyService.ets');

test('LlmClient.callStreamInternal firstByteTimer must be >= 30000ms', () => {
  const firstByteMatch = llmClient.match(/firstByteTimer[\s\S]*?setTimeout[\s\S]*?,\s*(\d+)\s*\)/);
  assert.ok(firstByteMatch !== null, 'firstByteTimer setTimeout call must exist');
  const ms = parseInt(firstByteMatch[1], 10);
  assert.ok(ms >= 30000, `firstByteTimer must be >= 30000ms, got ${ms}ms`);
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

test('ReplyService fallback does not override enableThinking', () => {
  const fallbackMatch = replyService.match(/private async fallback[\s\S]*?client\.call\([\s\S]*?\}\);/);
  assert.ok(fallbackMatch !== null, 'ReplyService fallback call must exist');
  assert.doesNotMatch(fallbackMatch[0], /enableThinking\s*:/);
});
