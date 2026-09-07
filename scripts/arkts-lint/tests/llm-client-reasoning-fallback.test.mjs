// scripts/arkts-lint/tests/llm-client-reasoning-fallback.test.mjs
//
// RED 测试: LlmClient 提取 SSE delta 时,content 为空时必须 fallback 到 reasoning_content
//
// 用户报告(2026-09-07 DevEco 真机 logcat):
//   - dataReceive: 38385 bytes 收到(流式成功)
//   - dataEnd, buffer: 38385(流正常结束)
//   - requestInStream cb: err=null code=200
//   - 但 UI 完全没消息("对话没有看到 AI 返回")
//
// 根因: deepseek-v4-pro 默认思考模式,响应只含 reasoning_content + 空 content
//   - LlmClient.tryEmitSseDelta 原版: content 空时**不调** onDelta
//   - AgentChatService.realReplyStream line 158: kind !== 'content' 过滤掉 reasoning
//   - 结论: appendAiMsg 0 次调用 → 消息空
//
// 修复: LlmClient.tryEmitSseDelta 加 else if — content 空时用 reasoning_content 替代
//   emit(作为 kind: 'content'),保证上层 AgentChatService 总能收到 content token。
//   reasoning 仍独立 emit(作为 kind: 'reasoning',保留 reasoning 字段显示)
//
// 验证覆盖(简化: 整个文件 grep, 不嵌 method body):
//   1. reasoning-only delta(content 空): 必须有 content fallback 调 onDelta
//   2. content emit 仍存在(现有行为不变)
//   3. reasoning emit 仍存在(现有行为不变)

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');

const llmClient = read('common/src/main/ets/llm/LlmClient.ets');

// 测试 1: tryEmitSseDelta 方法存在
test('LlmClient.tryEmitSseDelta exists', () => {
  assert.match(
    llmClient,
    /private\s+tryEmitSseDelta\s*\(/,
    'LlmClient.tryEmitSseDelta() method must exist'
  );
});

// 测试 2: 关键修复 — content 为空时,else if 分支用 reasoning_content 替代 emit as content
// 模式: ... else if (... reasoning_content ...) { onDelta(... reasoning_content ..., 'content') ... }
test('LlmClient.tryEmitSseDelta must fallback to reasoning_content when content is empty', () => {
  // 整个文件找: else if (...) ... onDelta(..., 'content')
  // 加上 reasoning_content 引用
  assert.match(
    llmClient,
    /else\s+if\s*\([^)]*reasoning_content[^)]*\)\s*\{[^}]*onDelta\s*\([^,]+,\s*['"]content['"]\s*\)/,
    'tryEmitSseDelta must have else-if branch: when content is empty, call onDelta(reasoning_content, "content") to prevent empty UI message'
  );
});

// 测试 3: content emit 仍存在(现有行为不变)
test('LlmClient.tryEmitSseDelta still emits content-only delta correctly', () => {
  assert.match(
    llmClient,
    /delta\.content\s*!==\s*undefined\s*&&\s*delta\.content\.length\s*>\s*0/,
    'tryEmitSseDelta must still check delta.content !== undefined && length > 0 (existing behavior preserved)'
  );
});

// 测试 4: reasoning emit 仍存在(现有行为不变)
test('LlmClient.tryEmitSseDelta still emits reasoning independently', () => {
  assert.match(
    llmClient,
    /onDelta\s*\(\s*delta\.reasoning_content\s*,\s*['"]reasoning['"]\s*\)/,
    'tryEmitSseDelta must still emit reasoning_content with kind: "reasoning"'
  );
});
