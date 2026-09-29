import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

const messageList = read('entry/src/main/ets/overlays/AgentFloatWindow/AgentMessageList.ets');
const floatWindow = read('entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets');
const chatBubble = read('entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatBubble.ets');
const runPanel = read('entry/src/main/ets/overlays/AgentFloatWindow/chat/AgentRunPanel.ets');
const autoFollowState = read('entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatAutoFollowState.ets');
const autoFollowStateTest = read('entry/src/test/ChatAutoFollowState.test.ets');

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
  const processSurface = chatBubble + '\n' + runPanel;
  assert.doesNotMatch(processSurface, /scrollEdge\(Edge\.Bottom\)/);
  assert.doesNotMatch(processSurface, /Scroll\(this\.reasoningScroller\)/);
  assert.doesNotMatch(processSurface, /height\(this\.msg\.streaming \? 168 : 124\)/);
});

test('streamed auto-follow pauses for user scrolling and resumes only at the bottom', () => {
  assert.match(autoFollowStateTest, /should follow streamed content while the user remains at the bottom/);
  assert.match(autoFollowStateTest, /should pause streamed auto-follow as soon as the user starts scrolling/);
  assert.match(autoFollowStateTest, /should remain paused when the user stops away from the bottom/);
  assert.match(autoFollowStateTest, /should resume streamed auto-follow after the user returns to the bottom/);
  assert.match(autoFollowState, /onUserScrollStart\(\)/);
  assert.match(autoFollowState, /onScrollStop\(isAtBottom: boolean\)/);
  assert.match(autoFollowState, /shouldFollowStreamProgress\(\)/);
  assert.match(messageList, /\.onScrollStart\(/);
  assert.match(messageList, /\.onScrollStop\(/);
  assert.match(messageList, /this\.scroller\.isAtEnd\(\)/);
  assert.match(messageList, /this\.autoFollowState\.shouldFollowStreamProgress\(\)/);
});
