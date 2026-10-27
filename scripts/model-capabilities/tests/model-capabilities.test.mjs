// scripts/model-capabilities/tests/model-capabilities.test.mjs
// issue #226 + 2026-10-26 ModelSpec 分层: 「思考/图像能力」改为读 ModelSpec / ModelListing,
// 不再看模型名子串, 也不再从 listing.effort 推断 toggle。
// 运行: node --test scripts/model-capabilities/tests/model-capabilities.test.mjs
//
// 断言范围:
//   1. ModelCapabilities.ets 声明四种 control + resolveCapabilities(listing, spec) + 兼容入口
//   2. 能力字段来自 spec.request.thinking / spec.request.effort 与 listing.inputModalities
//   3. LlmClient 无 vendor 特判, JSON/SSE 共用 composeRequest → planModelRequest
//   4. LlmClient 的看门狗按能力分档 (30000 / 60000)
//   5. LlmClient 的请求日志带 thinking= 与 effort= 字段

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');

const capabilities = read('common/src/main/ets/llm/ModelCapabilities.ets');
const llmClient = read('common/src/main/ets/llm/LlmClient.ets');
const commonIndex = read('common/src/main/ets/Index.ets');

test('ModelCapabilities declares the four thinking controls', () => {
  assert.match(
    capabilities,
    /export type ThinkingMode = 'toggle' \| 'always_on' \| 'unsupported' \| 'unverified';/,
    'ThinkingMode must distinguish unsupported from unverified',
  );
});

test('ModelCapabilities declares ModelCapability with thinking / efforts / defaultEffort / supportsImage', () => {
  assert.match(capabilities, /export interface ModelCapability \{/);
  assert.match(capabilities, /thinking: ThinkingMode;/);
  assert.match(capabilities, /efforts: string\[\];/);
  assert.match(capabilities, /defaultEffort: string;/);
  assert.match(capabilities, /supportsImage: boolean;/);
  assert.match(capabilities, /defaultThinkingEnabled: boolean;/);
});

test('ModelCapabilities exports resolveCapabilities(listing, spec) and the compatibility entry', () => {
  assert.match(
    capabilities,
    /export function resolveCapabilities\(\s*listing: ModelListing \| null,\s*spec: ModelSpec \| null,\s*\): ModelCapability/,
  );
  assert.match(
    capabilities,
    /export function resolveModelCapability\(vendorId: string, model: string\): ModelCapability/,
  );
  assert.match(capabilities, /thinking: 'unverified'/);
  assert.match(capabilities, /thinking: 'always_on'/);
});

test('capabilities derive from ModelSpec, not model-name substrings or discovery effort', () => {
  assert.match(capabilities, /spec\.request\.thinking\.control/);
  assert.match(capabilities, /spec\.request\.effort/);
  assert.match(capabilities, /listing\.inputModalities\.indexOf\('image'\)/);
  // 旧实现按模型名猜族群 / 用 effort 非空推 toggle; 现在都必须消失。
  assert.doesNotMatch(capabilities, /indexOf\('deepseek'\)/);
  assert.doesNotMatch(capabilities, /indexOf\('qwen'\)/);
  assert.doesNotMatch(capabilities, /startsWith\('o1'\)/);
  assert.doesNotMatch(capabilities, /startsWith\('o3'\)/);
  assert.doesNotMatch(capabilities, /indexOf\('reasoner'\)/);
  assert.doesNotMatch(capabilities, /listing\.effort/);
});

test('LlmClient has no vendor-specific thinking branches and shares one request builder', () => {
  assert.doesNotMatch(llmClient, /vendorId === 'deepseek'/, 'DeepSeek special case must be deleted');
  assert.doesNotMatch(llmClient, /vendorId === 'tongyi'/, 'Qwen special case must be deleted');
  assert.doesNotMatch(llmClient, /isDeepSeek/, 'vendor flags must be deleted');
  assert.doesNotMatch(llmClient, /enable_thinking\s*=/, 'flat enable_thinking must come from the spec');
  assert.doesNotMatch(llmClient, /reasoning_effort\s*=/, 'effort field must come from the spec');

  const composeCalls = llmClient.match(/this\.composeRequest\(request, (?:true|false)\)/g) ?? [];
  assert.equal(composeCalls.length, 2, 'JSON and SSE must both call the shared composeRequest');
  assert.match(llmClient, /planModelRequest\(resolved\.spec, selection\)/);
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

test('common Index exports the capability resolvers and spec types', () => {
  assert.match(commonIndex, /resolveModelCapability/);
  assert.match(commonIndex, /resolveCapabilities/);
  assert.match(commonIndex, /supportsImageInput/);
  assert.match(commonIndex, /ThinkingMode/);
  assert.match(commonIndex, /getModelSpec/);
  assert.match(commonIndex, /planModelRequest/);
});
