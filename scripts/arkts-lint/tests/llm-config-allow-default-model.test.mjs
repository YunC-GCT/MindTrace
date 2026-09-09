// scripts/arkts-lint/tests/llm-config-allow-default-model.test.mjs
//
// P0 bug 真实修复的 RED 测试:
// LlmConfig.normalizeModel 不应把 DEFAULT_MODEL 本身视为 reserved keyword
// (ticket #9 修复的副作用: reserved list 误把默认值抛错)
//
// 现象: ViewModel.test() 调用 saveAll(...) 内部 normalizeModel(DEFAULT_MODEL) →
//       抛 NORMALIZE_KEYWORD_REJECTED → 用户看到"连接失败",
//       实际是 normalize 抛错,根因 = 用户保存的就是默认模型(合法)。
//
// 修复: LlmConfig.normalizeModel 删除 `lower === DEFAULT_MODEL ||` 这一行。
//
// 一手信源:
//   docs/specs/016-llm-settings-redesign.md §背景 (P0 bug)
//   docs/specs/009-llm-config-throw-on-silent-override.md (ticket #9 修复精神)
//   docs/agents/llm-settings-scope-2026-09-06.md §附录 D (真实根因诊断)
//   docs/agents/tickets/llm-settings/pr0-fix-pro-model.md

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');

const read = (p) => readFileSync(resolve(root, p), 'utf8');

const llmConfig = read('common/src/main/ets/llm/LlmConfig.ets');

// 测试 1: normalizeModel 不应把 DEFAULT_MODEL 本身视为 reserved keyword
// (ticket #9 副作用的回归测试)
test('normalizeModel allows DEFAULT_MODEL itself (no longer rejects it)', () => {
  // 确认 DEFAULT_MODEL 常量存在并提取其值
  const defaultModelMatch = llmConfig.match(/DEFAULT_MODEL\s*=\s*['"]([^'"]+)['"]/);
  assert.ok(defaultModelMatch !== null, 'DEFAULT_MODEL constant must exist');
  const defaultModel = defaultModelMatch[1];
  assert.ok(defaultModel.length > 0, 'DEFAULT_MODEL must be non-empty');

  // 关键回归:normalizeModel 的 reserved keyword 守卫不应包含
  // `lower === DEFAULT_MODEL` 这一项(否则用户保存默认模型会抛错)
  assert.doesNotMatch(
    llmConfig,
    /lower\s*===\s*DEFAULT_MODEL\s*\|\|/,
    'normalizeModel must NOT treat DEFAULT_MODEL itself as a reserved keyword (P0 bug fix). ' +
    '修复: 删除 `lower === DEFAULT_MODEL ||` 这一行(LlmConfig.ets:232)。'
  );

  // 同时守卫应为空输入返回 DEFAULT_MODEL(不是抛错)
  assert.match(
    llmConfig,
    /if\s*\(\s*t\.length\s*===\s*0\s*\)\s*{\s*return\s+DEFAULT_MODEL/,
    'normalizeModel must return DEFAULT_MODEL for empty input (not throw)'
  );
});

// 测试 2: ticket #9 的其他 keyword 守卫必须保留(不破坏既有修复)
test('normalizeModel still rejects v3 / flash / deepseek-chat / deepseek-reasoner / r1', () => {
  assert.match(
    llmConfig,
    /lower\.indexOf\(['"]v3['"]\)\s*>=\s*0/,
    'normalizeModel must still reject v3 keyword (ticket #9 intent)'
  );
  assert.match(
    llmConfig,
    /lower\.indexOf\(['"]flash['"]\)\s*>=\s*0/,
    'normalizeModel must still reject flash keyword (ticket #9 intent)'
  );
  assert.match(
    llmConfig,
    /lower\.indexOf\(['"]deepseek-chat['"]\)\s*>=\s*0/,
    'normalizeModel must still reject deepseek-chat keyword (ticket #9 intent)'
  );
  assert.match(
    llmConfig,
    /lower\.indexOf\(['"]deepseek-reasoner['"]\)\s*>=\s*0/,
    'normalizeModel must still reject deepseek-reasoner keyword (ticket #9 intent)'
  );
  assert.match(
    llmConfig,
    /lower\.indexOf\(['"]r1['"]\)\s*>=\s*0/,
    'normalizeModel must still reject r1 keyword (ticket #9 intent)'
  );
});

// 测试 3: normalizeEndpoint 不应有同样的 bug(DEFAULT_ENDPOINT 自身不应抛错)
test('normalizeEndpoint does not reject DEFAULT_ENDPOINT itself', () => {
  // normalizeEndpoint 应该没有 `lower === DEFAULT_ENDPOINT` 检查
  assert.doesNotMatch(
    llmConfig,
    /normalizeEndpoint[\s\S]*?lower\s*===\s*DEFAULT_ENDPOINT/,
    'normalizeEndpoint must not reject DEFAULT_ENDPOINT itself (potential P0 bug pattern)'
  );

  // siliconflow 必须仍然被拒
  assert.match(
    llmConfig,
    /lower\.indexOf\(['"]siliconflow['"]\)\s*>=\s*0/,
    'normalizeEndpoint must still reject siliconflow (ticket #9 intent)'
  );
});

// 测试 4: 端到端诊断 — providers.ets deepseek.defaultModel 与 LlmConfig.DEFAULT_MODEL 必须保持一致
// PR2-T2 ticket #83 L5 (2026-09-08): EndpointPicker.ets / ModelPicker.ets git rm,DS_ENDPOINT/PRO_MODEL 字面替换
// 新来源:common/src/main/ets/llm/providers.ets(PR2-T1)的 PROVIDERS[0].defaultModel
// ViewModel.test() 调 saveAll(getCurrentModel()) — 应当命中 vendor-aware normalize 的 deepseek path
// 因此 providers deepseek.defaultModel 必须等于 LlmConfig.DEFAULT_MODEL(否则 vendor-aware normalize 不一致)
test('PROVIDERS deepseek.defaultModel (in providers.ets) equals DEFAULT_MODEL (in LlmConfig)', () => {
  // PROVIDERS[0] = deepseek.defaultModel(PR2-T1 spec)
  const providers = read('common/src/main/ets/llm/providers.ets');
  const firstProviderMatch = providers.match(
    /id:\s*['"]deepseek['"][\s\S]*?defaultModel:\s*['"]([^'"]+)['"]/
  );
  assert.ok(firstProviderMatch !== null, 'PROVIDERS deepseek.defaultModel must exist in providers.ets');
  const providerModel = firstProviderMatch[1];

  // DEFAULT_MODEL 在 LlmConfig.ets 定义
  const defaultModelMatch = llmConfig.match(/DEFAULT_MODEL\s*=\s*['"]([^'"]+)['"]/);
  assert.ok(defaultModelMatch !== null, 'DEFAULT_MODEL constant must exist in LlmConfig.ets');
  const defaultModel = defaultModelMatch[1];

  // 端到端: 两者必须相等
  assert.equal(
    providerModel,
    defaultModel,
    `PROVIDERS deepseek.defaultModel=${providerModel} must equal LlmConfig.DEFAULT_MODEL=${defaultModel}. ` +
    'If they diverge, ViewModel.saveAll(deepseek-default) hits vendor-aware normalize mismatch.'
  );
});
