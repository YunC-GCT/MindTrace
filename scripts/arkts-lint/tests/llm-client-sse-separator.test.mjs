// scripts/arkts-lint/tests/llm-client-sse-separator.test.mjs
//
// RED 测试: LlmClient.processSseBuffer 必须用 \n (单换行) 分隔 SSE event
//
// 用户报告(2026-09-07 20:17 DevEco 真机):
//   [DEBUG-a4f2] LlmClient: dataEnd dataReceived=true buffer=26689
//   [DEBUG-a4f2] stream completed, accumulatedContent length=0
// → 26KB 流式响应收到, 但 onDelta 调 0 次! → UI 永远空白
//
// 根因(2026-09-07 PR1k): LlmClient.processSseBuffer 之前用 \n\n 双换行找 event 边界,
//   但 OpenAI / DeepSeek 实际 SSE 格式是 data: {...}\n 每个行一个 event (单换行)。
//   找 \n\n 永远找不到 → buffer 累积 26KB 但 0 emit → 走降级非流式。
//
// 修复: processSseBuffer 改用 \n 单换行分隔
//
// 验证: 找源码中 processSseBuffer 用的 separator

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');

const llmClient = read('common/src/main/ets/llm/LlmClient.ets');

// 测试 1: processSseBuffer 找 SSE event 边界用 \n(单换行),不 \n\n
test('LlmClient.processSseBuffer must split SSE events by single newline (\\n), not double (\\n\\n)', () => {
  // 找 processSseBuffer 内的 indexOf 调用
  // 必须用 '\\n' (单),不能用 '\\n\\n' (双)
  const psbMatch = llmClient.match(/processSseBuffer\s*\(\s*buffer\s*:\s*string[\s\S]*?return\s+remaining/);
  assert.ok(psbMatch !== null, 'processSseBuffer body must exist');
  const body = psbMatch[0];

  // 找 indexOf 调用
  assert.match(
    body,
    /indexOf\s*\(\s*['"]\\n['"]/,
    'processSseBuffer must use indexOf("\\n") for single-newline SSE event split (OpenAI/DeepSeek format)'
  );
  // 不能用双换行(老的 bug 形式)
  assert.doesNotMatch(
    body,
    /indexOf\s*\(\s*['"]\\n\\n['"]/,
    'processSseBuffer must NOT use indexOf("\\n\\n") — OpenAI/DeepSeek SSE format is single-newline separated'
  );
});

// 测试 2: substring 切割 buffer 时也用 + 1 (单换行字符长度),不 + 2
test('LlmClient.processSseBuffer substring offset must be +1 for single \\n (not +2)', () => {
  const psbMatch = llmClient.match(/processSseBuffer\s*\(\s*buffer\s*:\s*string[\s\S]*?return\s+remaining/);
  assert.ok(psbMatch !== null, 'processSseBuffer body must exist');
  const body = psbMatch[0];

  // 找 remaining = remaining.substring(..., singleNewlineIdx + 1)
  assert.match(
    body,
    /remaining\s*=\s*remaining\.substring\s*\(\s*singleNewlineIdx\s*\+\s*1\s*\)/,
    'processSseBuffer must use remaining.substring(singleNewlineIdx + 1) for single-newline split'
  );
  // 不能用 + 2(老 bug)
  assert.doesNotMatch(
    body,
    /remaining\.substring\s*\(\s*singleNewlineIdx\s*\+\s*2\s*\)/,
    'processSseBuffer must NOT use +2 offset (that was for double-newline)'
  );
});

test('LlmClient.processSseBuffer accepts SSE data fields without a space after colon', () => {
  const psbMatch = llmClient.match(/processSseBuffer\s*\(\s*buffer\s*:\s*string[\s\S]*?return\s+remaining/);
  assert.ok(psbMatch !== null, 'processSseBuffer body must exist');
  assert.match(
    psbMatch[0],
    /indexOf\s*\(\s*['"]data:['"]\s*\)\s*!==\s*0/,
    'processSseBuffer must recognize the SSE field name independently of optional whitespace'
  );
});
