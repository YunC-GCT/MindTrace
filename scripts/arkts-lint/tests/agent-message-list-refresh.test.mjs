import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

const messageList = read('entry/src/main/ets/overlays/AgentFloatWindow/AgentMessageList.ets');
const floatWindow = read('entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets');
const chatBubble = read('entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatBubble.ets');

test('AgentMessageList refreshes rows when streamed reasoning grows', () => {
  assert.match(messageList, /LazyForEach\(this\.dataSource/);
  assert.match(messageList, /chatItemKey\(msg\)/);
  assert.match(messageList, /listener\.onDataReloaded\(\)/);
});

test('reasoning toggle must not scroll chat list to bottom', () => {
  const messagesWatch = floatWindow.match(/onMessagesChange\(\): void \{[\s\S]*?\n  \}/);
  assert.ok(messagesWatch !== null, 'AgentFloatWindow.onMessagesChange must exist');
  assert.doesNotMatch(messagesWatch[0], /scrollEdge\(Edge\.Bottom\)/);
  assert.doesNotMatch(floatWindow, /renderKey/);
  assert.match(messageList, /currentStreamProgressKey\(\)/);
  assert.match(messageList, /progressKey\.length > 0 && progressKey !== this\.lastStreamProgressKey/);
  assert.doesNotMatch(chatBubble, /scrollEdge\(Edge\.Bottom\)/);
  assert.doesNotMatch(chatBubble, /Scroll\(this\.reasoningScroller\)/);
  assert.doesNotMatch(chatBubble, /height\(this\.msg\.streaming \? 168 : 124\)/);
});
