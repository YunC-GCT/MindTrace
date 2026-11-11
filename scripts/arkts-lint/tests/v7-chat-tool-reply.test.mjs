// 路径: scripts/arkts-lint/tests/v7-chat-tool-reply.test.mjs
// 职责: Chat 工具回复默认关闭、tool_reply 接线与 ToolLoop 目录。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

test('Chat 工具回复默认开启，但只有笔记检索意图才触发', () => {
  const flags = read('agents/src/main/ets/conversation/ConversationToolReplyFlags.ets');
  assert.match(flags, /CHAT_TOOL_REPLY_ENABLED: boolean = true/);
  assert.match(flags, /static isEnabled\(\)/);
  assert.match(flags, /static setEnabled\(/);
  assert.match(flags, /static shouldUseTools\(userContent: string\)/);
  const mod = loadNoteReviewEtsModule('agents/src/main/ets/conversation/ConversationToolReplyFlags.ets');
  assert.equal(mod.ConversationToolReplyFlags.isEnabled(), true);
  mod.ConversationToolReplyFlags.setEnabled(false);
  assert.equal(mod.ConversationToolReplyFlags.isEnabled(), false);
  mod.ConversationToolReplyFlags.setEnabled(true);
  const should = mod.ConversationToolReplyFlags.shouldUseTools;
  assert.equal(should('查一下我笔记里关于连续性的内容'), true);
  assert.equal(should('帮我复习一下极限'), true);
  assert.equal(should('什么是导数'), false);
  assert.equal(should(''), false);
});

test('ConversationWorkflow 有 tool_reply 节点且只在开关开启时接线', () => {
  const workflow = read('agents/src/main/ets/conversation/ConversationWorkflow.ets');
  assert.match(workflow, /toolReplyEnabled\(\)/);
  assert.match(workflow, /graph\.addNode\('tool_reply'/);
  assert.match(workflow, /return 'tool_reply'/);
  const replyHandler = read('agents/src/main/ets/conversation/ConversationReplyHandler.ets');
  assert.match(replyHandler, /useTools: boolean = false/);
  assert.match(replyHandler, /toolReply\.complete\(/);
  // 流式工具链：tool_reply 节点走 handleStream(..., true)，端口提供 stream()
  assert.match(replyHandler, /toolPort\.stream\(/);
  const ports = read('agents/src/main/ets/conversation/ConversationWorkflowPorts.ets');
  assert.match(ports, /stream\(context: ReplyContext, sink: ReplyEventSink/);
  assert.match(workflow, /handleStream\([\s\S]*?true,\s*\)/);
  assert.match(ports, /interface IConversationToolPort/);
  assert.match(ports, /class ConversationToolAdapter implements IConversationToolPort/);
  assert.match(ports, /ToolCatalog\.createReadOnlyRegistry\(\)/);
  assert.match(ports, /new ToolLoop\(new LlmClient\(\)\)/);
  assert.match(ports, /new ConversationToolAdapter\(classifier\)/);
});
