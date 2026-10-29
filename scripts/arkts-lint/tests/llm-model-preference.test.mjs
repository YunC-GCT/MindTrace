// scripts/arkts-lint/tests/llm-model-preference.test.mjs
//
// 2026-10-26: 模型选择与运行偏好分开存。
//   active_model = {vendorId, modelId}                 — 只记选中项
//   model_prefs  = { "vendorId/modelId": {thinking?, effort?} } — 按准确型号存
//   model_specs  = 可选覆盖层, 缺省/非法回落内置 ModelSpec
//
// 断言语义 (不是实现细节):
//   - 偏好不能只按 vendor 存 (同家不同型号值域不同)
//   - LlmClient 未显式传参时读该型号偏好
//   - UI 只在 toggle/always_on 显示控件, unverified 显示「能力未确认」

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8').replace(/\r\n/g, '\n');

const llmConfig = read('common/src/main/ets/llm/LlmConfig.ets');
const llmClient = read('common/src/main/ets/llm/LlmClient.ets');
const vm = read('entry/src/main/ets/viewmodels/AiSettingsViewModel.ets');
const picker = read('entry/src/main/ets/pages/AiSettings/VendorPicker.ets');
const page = read('entry/src/main/ets/pages/AiSettings/AiSettingsPage.ets');

test('LlmConfig declares the three separate persistence keys', () => {
  assert.match(llmConfig, /const KEY_MODEL_PREFS = 'model_prefs';/);
  assert.match(llmConfig, /const KEY_ACTIVE_MODEL = 'active_model';/);
  assert.match(llmConfig, /const KEY_MODEL_SPECS = 'model_specs';/);
  assert.match(llmConfig, /export interface ModelPreference \{/);
  assert.match(llmConfig, /thinking\?: boolean;/);
  assert.match(llmConfig, /effort\?: string;/);
  assert.match(llmConfig, /export interface ModelActiveSelection \{/);
  assert.match(llmConfig, /vendorId: string;/);
  assert.match(llmConfig, /modelId: string;/);
});

test('LlmConfig keys preferences by providerId/modelId, not by vendor only', () => {
  assert.match(
    llmConfig,
    /public static modelPreferenceKey\(vendorId: string, modelId: string\): string \{[\s\S]*?vendorId\.trim\(\) \+ '\/' \+ modelId\.trim\(\)/,
    'model_prefs key must be "vendorId/modelId"',
  );
  assert.match(llmConfig, /getModelPreference\s*\(\s*vendorId: string,\s*modelId: string\s*\)/);
  assert.match(llmConfig, /setModelPreference\s*\(/);
  assert.match(llmConfig, /removeModelPreference\s*\(/);
  assert.match(llmConfig, /getActiveModel\s*\(\s*\)\s*:\s*ModelActiveSelection/);
  assert.match(llmConfig, /setActiveModel\s*\(\s*vendorId: string,\s*modelId: string\s*\)/);
});

test('LlmConfig reads/validates/persists model_specs and falls back to built-ins', () => {
  assert.match(llmConfig, /sanitizeModelSpecs/);
  assert.match(llmConfig, /setModelSpecOverrides\s*\(/);
  assert.match(llmConfig, /isValidModelSpec/);
  assert.match(llmConfig, /KEY_MODEL_SPECS/);
});

test('deleting a model also drops its per-model preference', () => {
  const removeBody = llmConfig.match(
    /public async removeVendorModel\(vendorId: string, model: string\): Promise<void> \{([\s\S]*?)\n  \}/,
  );
  assert.ok(removeBody !== null, 'removeVendorModel body must exist');
  assert.match(removeBody[1], /removeModelPreference\(vendorId, model\)/);
});

test('LlmClient prefers explicit request overrides, then per-model preference, then spec default', () => {
  assert.match(
    llmClient,
    /const preference: ModelPreference = this\.config\.getModelPreference\(vendorId, model\)/,
  );
  assert.match(llmClient, /request\.enableThinking !== undefined\s*\?\s*request\.enableThinking\s*:\s*preference\.thinking/);
  assert.match(llmClient, /request\.reasoningEffort !== undefined\s*\?\s*request\.reasoningEffort\s*:\s*preference\.effort/);
});

test('ViewModel owns per-model preference drafts and persists them immediately', () => {
  assert.match(vm, /modelPrefs: Record<string, ModelPreference> = \{\}/);
  assert.match(vm, /getModelPreference\(vendorId: string, model: string\): ModelPreference/);
  assert.match(vm, /setModelThinking\(vendorId: string, model: string, enabled: boolean\): void/);
  assert.match(vm, /setModelEffort\(vendorId: string, model: string, effort: string\): void/);
  assert.match(vm, /setModelPreference\(vendorId\.trim\(\), model\.trim\(\), pref\)/);
});

test('VendorPicker shows controls by spec control, never fakes unverified as unsupported', () => {
  assert.match(picker, /@Prop modelPrefs: Record<string, ModelPreference> = \{\};/);
  assert.match(picker, /onThinkingChange: \(vendorId: string, model: string, enabled: boolean\) => void/);
  assert.match(picker, /onEffortChange: \(vendorId: string, model: string, effort: string\) => void/);
  // toggle → 开关; always_on 不显示开关; unverified → 能力未确认。
  assert.match(picker, /thinking === 'toggle'/);
  assert.match(picker, /thinking === 'unverified'/);
  assert.match(picker, /'能力未确认'/);
  assert.match(picker, /'推理强度'/);
});

test('AiSettingsPage wires the new per-model callbacks', () => {
  assert.match(page, /modelPrefs: this\.vm\.modelPrefs/);
  assert.match(page, /onThinkingChange:[\s\S]*?this\.vm\.setModelThinking\(/);
  assert.match(page, /onEffortChange:[\s\S]*?this\.vm\.setModelEffort\(/);
});

test('UI: always_on hides the thinking switch; fixed-sampling models get no temperature control', () => {
  const controls = picker.match(/@Builder\n  renderModelSpecControls[\s\S]*?\n  \}\n/);
  assert.ok(controls !== null, 'renderModelSpecControls must exist');
  // 开关只在 toggle 分支; always_on 直接落到强度, 不出现置灰开关。
  assert.match(controls[0], /thinking === 'toggle'/);
  assert.match(controls[0], /thinking === 'unverified'/);
  assert.doesNotMatch(controls[0], /thinking === 'always_on'/);
  // Kimi 的 temperature/top_p 固定 → 设置页没有温度控件, 也不得新增可编辑输入。
  assert.doesNotMatch(controls[0], /temperature/i);
  assert.doesNotMatch(page, /temperature/i);
});
