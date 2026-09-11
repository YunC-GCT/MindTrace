// scripts/arkts-lint/tests/llm-client-stream-timeout.test.mjs
//
// RED 测试: LlmClient.callStreamInternal 应对 deepseek-v4-pro 思考模式有更长超时
//
// 用户报告(2026-09-07 20:08 DevEco 真机):
//   [DEBUG-a4f2] LlmClient.callStreamInternal: calling requestInStream endpoint=...
//   ... 8 秒无 dataReceive ...
//   [DEBUG-a4f2] AgentChatService stream error: LLM stream no data
//   → 降级非流式成功, 用户最终看到内容
//
// 根因: firstByteTimer 8 秒太短,deepseek-v4-pro 思考模式 thinking_content 阶段
//       可能需要 10-20 秒才发出第一个 chunk,期间 content + reasoning_content 都空。
//
// 修复:
//   1. firstByteTimer 8s → 30s (给 thinking 留时间)
//   2. AgentChatService.realReplyStream 显式 enableThinking: false (chat 不需 thinking)
//
// 验证(简化 grep):
//   1. LlmClient 源码中 firstByteTimer setTimeout 的 ms 阈值 >= 30000
//   2. AgentChatService.realReplyStream 内 client.call 传 enableThinking: false

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');

const llmClient = read('common/src/main/ets/llm/LlmClient.ets');
const replyService = read('entry/src/main/ets/services/ReplyService.ets');

// 测试 1: firstByteTimer 阈值 >= 30000ms
// 找 callStreamInternal 内的 setTimeout 调用,找到 firstByteTimer 的那个
test('LlmClient.callStreamInternal firstByteTimer must be >= 30000ms for deepseek-v4-pro thinking mode', () => {
  // 找 firstByteTimer 后面最近的 setTimeout(... , NNNN)
  // 用 lazy match 跨行 / 跳过 lambda 类型注解 (() : void => )
  const firstByteMatch = llmClient.match(/firstByteTimer[\s\S]*?setTimeout[\s\S]*?,\s*(\d+)\s*\)/);
  assert.ok(firstByteMatch !== null, 'firstByteTimer setTimeout call must exist in callStreamInternal');
  const ms = parseInt(firstByteMatch[1], 10);
  assert.ok(
    ms >= 30000,
    `firstByteTimer must be >= 30000ms to allow deepseek-v4-pro thinking mode, got ${ms}ms`
  );
});

// 测试 2: AgentChatService.realReplyStream 显式传 enableThinking: false
// (chat 不需要 thinking 过程,只要 content)
test('ReplyService stream reply must pass enableThinking: false to skip thinking', () => {
  // 必须含 enableThinking: false
  const realReplyMatch = replyService.match(/async stream\s*\([\s\S]*?client\.call\([\s\S]*?enableThinking\s*:\s*false/);
  assert.ok(realReplyMatch !== null, 'ReplyService.stream client.call must disable thinking');
  const callBlock = realReplyMatch[0];
  assert.match(
    callBlock,
    /enableThinking\s*:\s*false/,
    'ReplyService stream call must disable thinking to avoid 10s+ latency'
  );
});

test('LlmClient maps enableThinking false to the Qwen chat template switch on both transports', () => {
  const qwenSwitches = llmClient.match(/chat_template_kwargs/g) ?? [];
  assert.ok(qwenSwitches.length >= 2, 'JSON and SSE request bodies must both carry chat_template_kwargs');
  assert.match(llmClient, /enable_thinking:\s*enableThinking/);
});

test('ReplyService fallback preserves enableThinking false', () => {
  const fallbackMatch = replyService.match(/private async fallback[\s\S]*?client\.call\([\s\S]*?\}\);/);
  assert.ok(fallbackMatch !== null, 'ReplyService fallback call must exist');
  assert.match(fallbackMatch[0], /enableThinking:\s*false/);
});
