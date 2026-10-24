// scripts/model-capabilities/tests/model-capabilities.test.mjs
// issue #226: 按模型能力适配「思考模式」—— 结构断言
// 运行: node --test scripts/model-capabilities/tests/model-capabilities.test.mjs
//
// 断言范围:
//   1. ModelCapabilities.ets 声明三种 mode + resolveModelCapability
//   2. LlmClient.ets 的 always_on 分支不写 disabled
//   3. LlmClient.ets 的看门狗按能力分档 (30000 / 60000)
//   4. LlmClient.ets 的请求日志带 thinking= 与 effort= 字段

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

test('ModelCapabilities declares ModelCapability with thinking + efforts', () => {
  assert.match(capabilities, /export interface ModelCapability \{/);
  assert.match(capabilities, /thinking: ThinkingMode;/);
  assert.match(capabilities, /efforts: string\[\];/);
});

test('ModelCapabilities exports resolveModelCapability(vendorId, model)', () => {
  assert.match(
    capabilities,
    /export function resolveModelCapability\(vendorId: string, model: string\): ModelCapability/,
  );
  assert.match(capabilities, /thinking: 'toggle'/);
  assert.match(capabilities, /thinking: 'always_on'/);
  assert.match(capabilities, /thinking: 'unsupported'/);
});

test('resolver covers deepseek / qwen / o1-o3-reasoner / unknown', () => {
  // deepseek: toggle + 三档 effort
  assert.match(capabilities, /indexOf\('deepseek'\)/);
  // qwen: toggle, efforts 为空
  assert.match(capabilities, /indexOf\('qwen'\)/);
  // o1 / o3 / reasoner: always_on
  assert.match(capabilities, /startsWith\('o1'\)/);
  assert.match(capabilities, /startsWith\('o3'\)/);
  assert.match(capabilities, /indexOf\('reasoner'\)/);
  // 三档 effort 字面量
  assert.match(capabilities, /\['low', 'medium', 'high'\]/);
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

test('common Index exports the capability resolver and types', () => {
  assert.match(commonIndex, /resolveModelCapability/);
  assert.match(commonIndex, /ThinkingMode/);
});
