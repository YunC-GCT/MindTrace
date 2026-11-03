// 路径: scripts/arkts-lint/tests/v7-chat-tool-reply.test.mjs
// 职责: Chat 工具回复默认关闭、tool_reply 接线与 ToolLoop 目录。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

test('Chat 工具回复默认关闭，可灰度开启', () => {
  const flags = read('agents/src/main/ets/conversation/ConversationToolReplyFlags.ets');
  assert.match(flags, /CHAT_TOOL_REPLY_ENABLED: boolean = false/);
  assert.match(flags, /static isEnabled\(\)/);
  assert.match(flags, /static setEnabled\(/);
  const mod = loadNoteReviewEtsModule('agents/src/main/ets/conversation/ConversationToolReplyFlags.ets');
  assert.equal(mod.ConversationToolReplyFlags.isEnabled(), false);
  mod.ConversationToolReplyFlags.setEnabled(true);
  assert.equal(mod.ConversationToolReplyFlags.isEnabled(), true);
  mod.ConversationToolReplyFlags.setEnabled(false);
});

test('ConversationWorkflow 有 tool_reply 节点且只在开关开启时接线', () => {
  const workflow = read('agents/src/main/ets/conversation/ConversationWorkflow.ets');
  assert.match(workflow, /toolReplyEnabled\(\)/);
  assert.match(workflow, /graph\.addNode\('tool_reply'/);
  assert.match(workflow, /return 'tool_reply'/);
  assert.match(workflow, /useTools: boolean = false/);
  assert.match(workflow, /this\.toolReplyService\.complete\(/);
  const ports = read('agents/src/main/ets/conversation/ConversationWorkflowPorts.ets');
  assert.match(ports, /interface IConversationToolPort/);
  assert.match(ports, /class ConversationToolAdapter implements IConversationToolPort/);
  assert.match(ports, /ToolCatalog\.createReadOnlyRegistry\(\)/);
  assert.match(ports, /new ToolLoop\(new LlmClient\(\)\)/);
  assert.match(ports, /new ConversationToolAdapter\(classifier\)/);
});
