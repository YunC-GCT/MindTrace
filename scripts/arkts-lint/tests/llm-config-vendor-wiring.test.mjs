// scripts/arkts-lint/tests/llm-config-vendor-wiring.test.mjs
// L1+L2+L3 UI wiring (2026-09-08):
//   - AiSettingsViewModel: vendorApiKeys + vendorModels + customVendors 持久化
//   - VendorPicker: @Prop vendorApiKeys + vendorModels + onApiKeyChange + onAddModel + onRemoveModel
//   - AiSettingsPage: 接线这些 props + callbacks 到 VM
//
// 全部 AST 静态检查 (与 llm-config-* 一致)

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, '../../..');

function read(p) {
  return readFileSync(resolve(REPO_ROOT, p), 'utf8').replace(/\r\n/g, '\n');
}

const vm = read('entry/src/main/ets/viewmodels/AiSettingsViewModel.ets');
const vp = read('entry/src/main/ets/pages/AiSettings/VendorPicker.ets');
const pg = read('entry/src/main/ets/pages/AiSettings/AiSettingsPage.ets');

test('wiring: VM declares vendorApiKeys + vendorModels + customVendors fields', () => {
  assert.match(vm, /vendorApiKeys\s*:\s*Record\s*<\s*string\s*,\s*string\s*>/, 'VM must declare vendorApiKeys: Record<string, string>');
  assert.match(vm, /vendorModels\s*:\s*Record\s*<\s*string\s*,\s*string\s*\[\s*\]\s*>/, 'VM must declare vendorModels: Record<string, string[]>');
  assert.match(vm, /customVendors\s*:\s*CustomVendorConfig\s*\[\s*\]/, 'VM must declare customVendors: CustomVendorConfig[]');
});

test('wiring: VM exposes setVendorApiKey method', () => {
  assert.match(vm, /setVendorApiKey\s*\(\s*vendorId\s*:\s*string\s*,\s*key\s*:\s*string\s*\)\s*:\s*void/, 'VM must declare setVendorApiKey(vendorId, key): void');
  assert.doesNotMatch(vm, /clearVendorApiKey\s*\(/, 'VM must not retain unused clearVendorApiKey()');
});

test('wiring: VM exposes addVendorModel + removeVendorModel methods', () => {
  assert.match(vm, /addVendorModel\s*\(\s*vendorId\s*:\s*string\s*,\s*model\s*:\s*string\s*\)\s*:\s*void/, 'VM must declare addVendorModel(vendorId, model): void');
  assert.match(vm, /removeVendorModel\s*\(\s*vendorId\s*:\s*string\s*,\s*model\s*:\s*string\s*\)\s*:\s*void/, 'VM must declare removeVendorModel(vendorId, model): void');
});

test('wiring: VM.save() persists vendorApiKeys via LlmConfig.setApiKey(key, vendorId)', () => {
  assert.match(vm, /llm\.setApiKey\([^,)]+,\s*vid\)/, 'VM.save() must call llm.setApiKey(key, vid) for per-vendor keys');
});

test('wiring: VM.save() persists vendorModels via LlmConfig.addVendorModel', () => {
  assert.match(vm, /llm\.addVendorModel\(/, 'VM.save() must call llm.addVendorModel() for per-vendor models');
});

test('wiring: VM.save() persists customVendors via LlmConfig.setCustomVendors', () => {
  assert.match(vm, /llm\.setCustomVendors\(/, 'VM.save() must call llm.setCustomVendors() for customVendors array');
});

test('wiring: VM.load() reads customVendors from LlmConfig.getCustomVendors', () => {
  assert.match(vm, /llm\.getCustomVendors\(/, 'VM.load() must call llm.getCustomVendors()');
});

test('wiring: VM.load() reads per-vendor models via LlmConfig.getVendorModels', () => {
  // VM.load() 体内必须含 llm.getVendorModels(p.id) — source-level 匹配(避免 body extraction 嵌套块问题)
  assert.match(vm, /llm\.getVendorModels\s*\(\s*p\.id\s*\)/, 'VM.load() must call llm.getVendorModels(p.id) for each preset vendor');
});

test('wiring: VM.load() reads per-vendor API keys via LlmConfig.getAllVendorApiKeys()', () => {
  // PR2-T2 ticket #83 bug fix (2026-09-08): load() 还原所有 vendor keys(原代码只还原 current)
  assert.match(vm, /vendorApiKeys\s*=\s*llm\.getAllVendorApiKeys\(\)/, 'VM.load() must call llm.getAllVendorApiKeys() to restore all vendor api keys');
});

test('wiring: VendorPicker declares @Prop vendorApiKeys + vendorModels', () => {
  assert.match(vp, /@Prop\s+vendorApiKeys\s*:\s*Record\s*<\s*string\s*,\s*string\s*>/, 'VendorPicker must declare @Prop vendorApiKeys');
  assert.match(vp, /@Prop\s+vendorModels\s*:\s*Record\s*<\s*string\s*,\s*string\s*\[\s*\]\s*>/, 'VendorPicker must declare @Prop vendorModels');
});

test('wiring: VendorPicker declares onApiKeyChange + onAddModel + onRemoveModel callbacks', () => {
  assert.match(vp, /onApiKeyChange\s*:\s*\(\s*vendorId\s*:\s*string\s*,\s*key\s*:\s*string\s*\)\s*=>\s*void/, 'VendorPicker must declare onApiKeyChange callback');
  assert.match(vp, /onAddModel\s*:\s*\(\s*vendorId\s*:\s*string\s*,\s*model\s*:\s*string\s*\)\s*=>\s*void/, 'VendorPicker must declare onAddModel callback');
  assert.match(vp, /onRemoveModel\s*:\s*\(\s*vendorId\s*:\s*string\s*,\s*model\s*:\s*string\s*\)\s*=>\s*void/, 'VendorPicker must declare onRemoveModel callback');
});

test('wiring: VendorPicker API Key TextInput.text reads local apiKeyInput draft', () => {
  assert.match(vp, /TextInput\([^)]*text:\s*this\.apiKeyInput/s, 'API Key TextInput must read local apiKeyInput draft');
});

test('wiring: VendorPicker API Key TextInput.onChange only updates local draft', () => {
  assert.match(vp, /onChange\(\(v:\s*string\):\s*void\s*=>\s*\{\s*this\.apiKeyInput\s*=\s*v/, 'API Key onChange must update local draft');
});

test('wiring: VendorPicker model list ForEach reads from localModels draft', () => {
  assert.match(vp, /ForEach\s*\(\s*this\.localModels/s, 'Model list ForEach must iterate localModels draft');
});

test('wiring: VendorPicker model × button updates localModels draft', () => {
  assert.match(vp, /this\.localModels\s*=\s*this\.localModels\.filter/, 'Model × button must update localModels draft');
});

test('wiring: VendorPicker 保存一次性调用 onAddModel/onRemoveModel', () => {
  assert.match(vp, /saveEdit[\s\S]*?onRemoveModel\(vendorId,\s*m\)/, 'saveEdit must commit removals');
  assert.match(vp, /saveEdit[\s\S]*?onAddModel\(vendorId,\s*m\)/, 'saveEdit must commit additions');
});

test('wiring: AiSettingsPage passes vendorApiKeys + vendorModels to VendorPicker', () => {
  assert.match(pg, /vendorApiKeys:\s*this\.vm\.vendorApiKeys/, 'AiSettingsPage must pass vendorApiKeys: this.vm.vendorApiKeys to VendorPicker');
  assert.match(pg, /vendorModels:\s*this\.vm\.vendorModels/, 'AiSettingsPage must pass vendorModels: this.vm.vendorModels to VendorPicker');
});

test('wiring: AiSettingsPage wires onApiKeyChange + onAddModel + onRemoveModel to VM', () => {
  // 多行回调用 [\s\S]*? 匹配 — source-level 验证
  assert.match(pg, /onApiKeyChange[\s\S]*?this\.vm\.setVendorApiKey\s*\(/, 'AiSettingsPage must wire onApiKeyChange to this.vm.setVendorApiKey');
  assert.match(pg, /onAddModel[\s\S]*?this\.vm\.addVendorModel\s*\(/, 'AiSettingsPage must wire onAddModel to this.vm.addVendorModel');
  assert.match(pg, /onRemoveModel[\s\S]*?this\.vm\.removeVendorModel\s*\(/, 'AiSettingsPage must wire onRemoveModel to this.vm.removeVendorModel');
});
