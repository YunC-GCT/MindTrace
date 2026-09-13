import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');

const llmClient = read('common/src/main/ets/llm/LlmClient.ets');

test('structured SSE parsing tolerates null reasoning_content', () => {
  assert.match(llmClient, /const reasoning: string = delta\.reasoning_content \?\? ''/);
  assert.doesNotMatch(llmClient, /tryEmitSseDelta/);
});

test('structured SSE parsing tolerates null content', () => {
  assert.match(llmClient, /const content: string = delta\.content \?\? ''/);
  assert.doesNotMatch(llmClient, /delta\.reasoning_content\.length|delta\.content\.length/);
});
