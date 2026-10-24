import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');
const localChatPath = 'common/src/main/ets/llm/LocalChatProvider.ets';
const portsPath = 'entry/src/main/ets/workflows/conversation/ConversationWorkflowPorts.ets';

test('LocalChatProvider exposes askStream with isStream=true and delta callback', () => {
  const source = read(localChatPath);
  assert.match(source, /askStream\(/);

  const start = source.indexOf('async askStream(');
  const end = source.indexOf('private static extractDelta', start);
  assert.ok(start >= 0 && end > start, 'askStream() body should precede extractDelta()');
  const body = source.slice(start, end);
  assert.match(body, /isStream:\s*true/);
  assert.match(body, /onDelta\(delta, answer\.isFinished\)/);
  assert.match(body, /resolve\(answerText\)/);
});

test('askStream tolerates cumulative content via prefix diff', () => {
  const source = read(localChatPath);
  const start = source.indexOf('private static extractDelta');
  assert.ok(start >= 0);
  const body = source.slice(start);
  assert.match(body, /startsWith\(accumulated\)/);
  assert.match(body, /substring\(accumulated\.length\)/);
});

test('ConversationReplyAdapter.stream routes to on-device when ready', () => {
  const source = read(portsPath);
  const start = source.indexOf('async stream(');
  const end = source.indexOf('normalize(content: string)', start);
  assert.ok(start >= 0 && end > start);
  const body = source.slice(start, end);
  assert.match(body, /isReady\(\)/);
  assert.match(body, /\[StreamRoute\]/);
  assert.match(body, /localChat\.askStream\(/);
});

test('ReplyService.stream remains the remote fallback branch', () => {
  const source = read(portsPath);
  const start = source.indexOf('async stream(');
  const end = source.indexOf('normalize(content: string)', start);
  assert.ok(start >= 0 && end > start);
  const body = source.slice(start, end);

  const remoteIndex = body.indexOf('this.reply.stream(context, sink, token)');
  const onDeviceIndex = body.indexOf('localChat.isReady()');
  assert.ok(remoteIndex >= 0, 'remote fallback must call this.reply.stream');
  assert.ok(onDeviceIndex >= 0 && onDeviceIndex < remoteIndex, 'on-device branch must precede remote fallback');
  assert.match(body, /source=remote/);
});
