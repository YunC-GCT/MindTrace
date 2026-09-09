// scripts/arkts-lint/tests/llm-config-vendor-file-cleanup.test.mjs
// L5 + L6 测试 (2026-09-08): PR2-T2 ticket #83 file + page cleanup
// 范围 (spec 017):
//   L5 — git rm EndpointPicker.ets / ModelPicker.ets + 字面替换 + test 4 改读 providers.ets
//   L6 — AiSettingsPage.endpointSummary/modelSummary 改用 getCurrent*(清 useCustomEP/customEP/modelLabel 残留)

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8').replace(/\r\n/g, '\n');

// ===== L5: git rm EndpointPicker.ets / ModelPicker.ets =====

test('L5: EndpointPicker.ets must NOT exist (git rm done)', () => {
  assert.ok(
    !existsSync(resolve(root, 'entry/src/main/ets/pages/AiSettings/EndpointPicker.ets')),
    'EndpointPicker.ets must be git rm-ed (replaced by VendorPicker)'
  );
});

test('L5: ModelPicker.ets must NOT exist (git rm done)', () => {
  assert.ok(
    !existsSync(resolve(root, 'entry/src/main/ets/pages/AiSettings/ModelPicker.ets')),
    'ModelPicker.ets must be git rm-ed (replaced by VendorPicker)'
  );
});

test('L5: LlmConfig.ets must NOT import DS_ENDPOINT from EndpointPicker', () => {
  const llmConfig = read('common/src/main/ets/llm/LlmConfig.ets');
  assert.doesNotMatch(
    llmConfig,
    /from\s+["']\.\.\/\.\.\/pages\/AiSettings\/EndpointPicker["']/,
    'LlmConfig must NOT import from EndpointPicker (L5 git rm done)'
  );
});

test('L5: LlmConfig.ets must NOT import PRO_MODEL from ModelPicker', () => {
  const llmConfig = read('common/src/main/ets/llm/LlmConfig.ets');
  assert.doesNotMatch(
    llmConfig,
    /from\s+["']\.\.\/\.\.\/pages\/AiSettings\/ModelPicker["']/,
    'LlmConfig must NOT import from ModelPicker (L5 git rm done)'
  );
});

test('L5: AiSettingsViewModel must NOT import DS_ENDPOINT or PRO_MODEL', () => {
  const vm = read('entry/src/main/ets/viewmodels/AiSettingsViewModel.ets');
  assert.doesNotMatch(vm, /DS_ENDPOINT/, 'VM must NOT reference DS_ENDPOINT (L5 done)');
  assert.doesNotMatch(vm, /PRO_MODEL/, 'VM must NOT reference PRO_MODEL (L5 done)');
  assert.doesNotMatch(vm, /EndpointPicker/, 'VM must NOT import from EndpointPicker');
  assert.doesNotMatch(vm, /ModelPicker/, 'VM must NOT import from ModelPicker');
});

// ===== L5: test 4 改读 providers.ets =====

test('L5: PROVIDERS[0].defaultModel equals LlmConfig.DEFAULT_MODEL (replaces old ModelPicker test 4)', () => {
  const providers = read('common/src/main/ets/llm/providers.ets');
  const llmConfig = read('common/src/main/ets/llm/LlmConfig.ets');

  // LlmConfig.DEFAULT_MODEL 字面
  const defaultModelMatch = llmConfig.match(/DEFAULT_MODEL\s*=\s*['"]([^'"]+)['"]/);
  assert.ok(defaultModelMatch !== null, 'LlmConfig.DEFAULT_MODEL must exist');
  const defaultModel = defaultModelMatch[1];

  // PROVIDERS[0] = deepseek.defaultModel(PR2-T1 spec)
  // 简化: 第一个 PROVIDERS entry 的 defaultModel
  const firstProviderMatch = providers.match(
    /id:\s*['"]deepseek['"][\s\S]*?defaultModel:\s*['"]([^'"]+)['"]/
  );
  assert.ok(firstProviderMatch !== null, 'PROVIDERS deepseek.defaultModel must exist');
  const deepseekModel = firstProviderMatch[1];

  // 端到端: 两者必须相等(否则 saveAll(deepseekDefaultModel) 触发 vendor-aware normalize 不一致)
  assert.equal(
    deepseekModel,
    defaultModel,
    `PROVIDERS deepseek.defaultModel=${deepseekModel} must equal LlmConfig.DEFAULT_MODEL=${defaultModel}. ` +
    'Divergence causes ViewModel.saveAll(deepseek-default) to hit vendor-aware normalize mismatch.'
  );
});

// ===== L6: AiSettingsPage.endpointSummary/modelSummary 改用 getCurrent* =====

test('L6: AiSettingsPage.endpointSummary uses vm.getCurrentEndpoint()', () => {
  const page = read('entry/src/main/ets/pages/AiSettings/AiSettingsPage.ets');
  // endpointSummary 函数体必须调 this.vm.getCurrentEndpoint()
  const epBody = page.match(/endpointSummary\s*\(\s*\)\s*:\s*string\s*\{([\s\S]*?)\n\s*\}/);
  assert.ok(epBody !== null, 'AiSettingsPage.endpointSummary() must exist');
  assert.match(
    epBody[1],
    /this\.vm\.getCurrentEndpoint\(\)/,
    'AiSettingsPage.endpointSummary() must use vm.getCurrentEndpoint()'
  );
});

test('L6: AiSettingsPage.modelSummary uses vm.getCurrentModel()', () => {
  const page = read('entry/src/main/ets/pages/AiSettings/AiSettingsPage.ets');
  // modelSummary 函数体必须调 this.vm.getCurrentModel()
  const mBody = page.match(/modelSummary\s*\(\s*\)\s*:\s*string\s*\{([\s\S]*?)\n\s*\}/);
  assert.ok(mBody !== null, 'AiSettingsPage.modelSummary() must exist');
  assert.match(
    mBody[1],
    /this\.vm\.getCurrentModel\(\)/,
    'AiSettingsPage.modelSummary() must use vm.getCurrentModel()'
  );
});

test('L6: AiSettingsPage no longer references vm.useCustomEP / vm.customEP / vm.modelLabel()', () => {
  const page = read('entry/src/main/ets/pages/AiSettings/AiSettingsPage.ets');
  assert.doesNotMatch(page, /vm\.useCustomEP/, 'Page must NOT reference vm.useCustomEP (L4 deleted)');
  assert.doesNotMatch(page, /vm\.customEP/, 'Page must NOT reference vm.customEP (L4 deleted)');
  assert.doesNotMatch(page, /vm\.modelLabel\(\)/, 'Page must NOT reference vm.modelLabel() (L4 deleted)');
});
