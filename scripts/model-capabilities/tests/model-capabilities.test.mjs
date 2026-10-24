// scripts/model-capabilities/tests/model-capabilities.test.mjs
// issue #226 + Phase 1 模型适配: 「思考/图像能力」改为读 ModelListing, 不再看模型名子串。
// 运行: node --test scripts/model-capabilities/tests/model-capabilities.test.mjs
//
// 断言范围:
//   1. ModelCapabilities.ets 声明三种 mode + resolveCapabilities(listing) + 兼容入口
//   2. 能力字段只来自 listing.effort / listing.inputModalities
//   3. LlmClient.ets 的 always_on 分支不写 disabled
//   4. LlmClient.ets 的看门狗按能力分档 (30000 / 60000)
//   5. LlmClient.ets 的请求日志带 thinking= 与 effort= 字段

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');

const capabilities = read('common/src/main/ets/llm/ModelCapabilities.ets');
const llmClient = read('common/src/main/ets/llm/LlmClient.ets');
const commonIndex = read('common/src/main/ets/Index.ets');

test('ModelCapabilities declares the three thinking modes', () => {
  assert.match(
    capabilities,
    /export type ThinkingMode = 'toggle' \| 'always_on' \| 'unsupported';/,
    'ThinkingMode must be toggle | always_on | unsupported',
  );
});

test('ModelCapabilities declares ModelCapability with thinking / efforts / defaultEffort / supportsImage', () => {
  assert.match(capabilities, /export interface ModelCapability \{/);
  assert.match(capabilities, /thinking: ThinkingMode;/);
  assert.match(capabilities, /efforts: string\[\];/);
  assert.match(capabilities, /defaultEffort: string;/);
  assert.match(capabilities, /supportsImage: boolean;/);
});

test('ModelCapabilities exports resolveCapabilities(listing) and the compatibility entry', () => {
  assert.match(
    capabilities,
    /export function resolveCapabilities\(listing: ModelListing \| null\): ModelCapability/,
  );
  assert.match(
    capabilities,
    /export function resolveModelCapability\(vendorId: string, model: string\): ModelCapability/,
  );
  assert.match(capabilities, /thinking: 'toggle'/);
  assert.match(capabilities, /thinking: 'unsupported'/);
});

test('capabilities derive from listing fields, not model-name substrings', () => {
  assert.match(capabilities, /listing\.effort\.supportedLevels/);
  assert.match(capabilities, /listing\.effort\.defaultLevel/);
  assert.match(capabilities, /listing\.inputModalities\.indexOf\('image'\)/);

  // 旧实现按模型名猜族群; Phase 1 删除这些分支。
  assert.doesNotMatch(capabilities, /indexOf\('deepseek'\)/);
  assert.doesNotMatch(capabilities, /indexOf\('qwen'\)/);
  assert.doesNotMatch(capabilities, /startsWith\('o1'\)/);
  assert.doesNotMatch(capabilities, /startsWith\('o3'\)/);
  assert.doesNotMatch(capabilities, /indexOf\('reasoner'\)/);
  assert.doesNotMatch(capabilities, /\['low', 'medium', 'high'\]/);
});

test('LlmClient always_on branch never writes disabled', () => {
  const branch = llmClient.match(
    /if \(capability\.thinking === 'always_on'\) \{[\s\S]*?\n    \}/,
  );
  assert.ok(branch !== null, 'always_on branch must exist in LlmClient');
  assert.doesNotMatch(branch[0], /disabled/, 'always_on branch must never write disabled');
  assert.match(branch[0], /body\.reasoning_effort/, 'always_on branch must keep reasoning_effort');
});

test('LlmClient tiers the first-byte watchdog at 30000 / 60000', () => {
  assert.match(llmClient, /firstByteWatchdogMs/);
  assert.match(llmClient, /60000/);
  assert.match(llmClient, /30000/);
});

test('LlmClient logs thinking mode and effort on both transports', () => {
  const thinkingLogs = llmClient.match(/' thinking=' \+ capability\.thinking/g) ?? [];
  const effortLogs = llmClient.match(/' effort=' \+ effortText/g) ?? [];
  assert.ok(thinkingLogs.length >= 2, 'both transports must log thinking=<mode>');
  assert.ok(effortLogs.length >= 2, 'both transports must log effort=<value|none>');
});

test('common Index exports the capability resolvers and types', () => {
  assert.match(commonIndex, /resolveModelCapability/);
  assert.match(commonIndex, /resolveCapabilities/);
  assert.match(commonIndex, /supportsImageInput/);
  assert.match(commonIndex, /ThinkingMode/);
});
