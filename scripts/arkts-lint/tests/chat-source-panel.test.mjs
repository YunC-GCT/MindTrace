// 路径: scripts/arkts-lint/tests/chat-source-panel.test.mjs
// 职责: 命中来源改为结构化卡片——事件、消息字段、气泡渲染与来源面板接线。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');

const types = read('agents/src/main/ets/conversation/ConversationTypes.ets');
const chatModels = read('entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatModels.ets');
const reducer = read('entry/src/main/ets/services/ConversationSessionReducer.ets');
const handler = read('agents/src/main/ets/conversation/ConversationReplyHandler.ets');
const panel = read('entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatSourcePanel.ets');
const bubble = read('entry/src/main/ets/overlays/AgentFloatWindow/chat/AiMessageBubble.ets');
const chatBubble = read('entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatBubble.ets');

test('sources 事件贯通：类型 → reducer → 消息字段', () => {
  assert.match(types, /kind: 'sources'/);
  assert.match(types, /citations: NoteEvidenceCitation\[\]/);
  assert.match(reducer, /event\.kind === 'sources'/);
  assert.match(reducer, /applyChatMsgSources\(message, event\.citations\)/);
  assert.match(chatModels, /citations\?: NoteEvidenceCitation\[\]/);
  assert.match(chatModels, /export function applyChatMsgSources/);
  assert.match(chatModels, /_sources/);
});

test('命中时发结构化来源，正文不再拼长摘录', () => {
  assert.match(handler, /kind: 'sources', citations: evidence\.citations/);
  assert.match(handler, /evidence\.citations\.length > 0/);
});

test('来源面板展示标题/角色/摘要并支持点击', () => {
  assert.match(panel, /参考来源/);
  assert.match(panel, /citationSnippet\(citation\.excerpt\)/);
  assert.match(panel, /\[关键词命中\]/);
  assert.match(panel, /onSourceTap\(citation\)/);
  assert.match(panel, /this\.expanded = !this\.expanded/);
});

test('气泡接线：消息 citations 传给来源面板', () => {
  assert.match(chatBubble, /citations: this\.msg\.citations === undefined \? \[\] : this\.msg\.citations/);
  assert.match(bubble, /ChatSourcePanel\(\{/);
  assert.match(bubble, /@Prop citations: NoteEvidenceCitation\[\] = \[\]/);
});
