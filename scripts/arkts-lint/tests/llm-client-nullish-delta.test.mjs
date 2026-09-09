// scripts/arkts-lint/tests/llm-client-nullish-delta.test.mjs
//
// RED 测试: LlmClient.tryEmitSseDelta 必须用 != null 而非 !== undefined
//
// 用户报告(2026-09-07 20:35 DevEco 真机):
//   [DEBUG-a4f2] processSseBuffer JSON.parse failed:
//     err=Cannot read property length of null
//   → tryEmitSseDelta 内的 console.error 抛 TypeError
//   → catch 把 eventText 放回 buffer,processSseBuffer 永远循环
//   → 用户看到"0 emit + buffer 累积 30KB"
//
// 根因: DeepSeek 流式响应 delta 字段可能是 null 不是 undefined
//   例: {"content": "你", "reasoning_content": null}
//   原代码用 `delta.reasoning_content !== undefined` 检查 → null 漏过 → null.length 抛错
//
// 修复: 改用 `!= null` (nullish check) 同时排除 null + undefined

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');

const llmClient = read('common/src/main/ets/llm/LlmClient.ets');

// 测试 1: tryEmitSseDelta 内的 if 条件必须用 != null(而非 !== undefined)
test('LlmClient.tryEmitSseDelta must use != null (not !== undefined) for reasoning_content', () => {
  // 找 tryEmitSseDelta 方法体
  const methodMatch = llmClient.match(/private\s+tryEmitSseDelta\s*\([\s\S]*?\n\s*\}\s*\n\s*\}\s*\n/);
  assert.ok(methodMatch !== null, 'tryEmitSseDelta method must exist');
  const body = methodMatch[0];

  // reasoning_content 检查必须用 != null (nullish)
  assert.match(
    body,
    /delta\.reasoning_content\s*!=\s*null/,
    'tryEmitSseDelta must use != null for reasoning_content (DeepSeek may return null, not undefined)'
  );
  // 不能用 !== undefined (老 bug 形式)
  assert.doesNotMatch(
    body,
    /delta\.reasoning_content\s*!==\s*undefined/,
    'tryEmitSseDelta must NOT use !== undefined (misses null values)'
  );
});

// 测试 2: content 检查也必须用 != null
test('LlmClient.tryEmitSseDelta must use != null (not !== undefined) for content', () => {
  const methodMatch = llmClient.match(/private\s+tryEmitSseDelta\s*\([\s\S]*?\n\s*\}\s*\n\s*\}\s*\n/);
  assert.ok(methodMatch !== null, 'tryEmitSseDelta method must exist');
  const body = methodMatch[0];

  assert.match(
    body,
    /delta\.content\s*!=\s*null/,
    'tryEmitSseDelta must use != null for content (DeepSeek may return null)'
  );
  assert.doesNotMatch(
    body,
    /delta\.content\s*!==\s*undefined/,
    'tryEmitSseDelta must NOT use !== undefined for content'
  );
});
