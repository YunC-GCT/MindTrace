import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');

const llmClient = read('common/src/main/ets/llm/LlmClient.ets');

test('LlmClient exposes the structured SSE event emitter', () => {
  assert.match(llmClient, /private\s+emitSseEvents\s*\(/);
  assert.doesNotMatch(llmClient, /tryEmitSseDelta/);
});

test('reasoning-only SSE deltas emit thinking without text fallback', () => {
  assert.match(llmClient, /const thinkingEvent: StreamEvent = \{ type: 'thinking', delta: reasoning \};/);
  assert.doesNotMatch(llmClient, /type: 'text', delta: reasoning/);
});

test('content-only SSE deltas emit text events', () => {
  assert.match(llmClient, /const textEvent: StreamEvent = \{ type: 'text', delta: content \};/);
});

test('reasoning is emitted before text when both channels are present', () => {
  assert.match(llmClient, /events\.push\(thinkingEvent\);[\s\S]*events\.push\(textEvent\);/);
});
