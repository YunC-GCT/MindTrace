import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');

const llmClient = read('common/src/main/ets/llm/LlmClient.ets');
const responseParser = read('common/src/main/ets/llm/LlmResponseParser.ets');

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

test('non-stream length responses keep partial text with a truncation marker', () => {
  assert.match(responseParser, /finish_reason === 'length'/);
  assert.match(responseParser, /回复因长度限制被截断/);
  assert.doesNotMatch(llmClient, /throw new LlmError\('LLM response truncated by max_tokens'/);
  assert.match(llmClient, /LlmResponseParser\.buildCallResult\(parsed\)/);
});

test('stream length responses emit a truncation marker event', () => {
  assert.match(llmClient, /finish_reason === 'length'/);
  assert.match(llmClient, /const truncationEvent: StreamEvent = \{ type: 'text', delta: '\\n\\n' \+ TRUNCATION_MARKER \};/);
  assert.match(llmClient, /events\.push\(truncationEvent\)/);
});
