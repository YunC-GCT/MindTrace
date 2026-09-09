import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');

function read(path) {
  return readFileSync(resolve(root, path), 'utf8').replace(/\r\n/g, '\n');
}

const llmConfig = read('common/src/main/ets/llm/LlmConfig.ets');
const providers = read('common/src/main/ets/llm/providers.ets');
const vm = read('entry/src/main/ets/viewmodels/AiSettingsViewModel.ets');
const vp = read('entry/src/main/ets/pages/AiSettings/VendorPicker.ets');
const page = read('entry/src/main/ets/pages/AiSettings/AiSettingsPage.ets');
const structureNode = read('agents/src/main/ets/graph/nodes/StructureNode.ets');
const llmClient = read('common/src/main/ets/llm/LlmClient.ets');

test('real LLM: DeepSeek defaults use current official pro model', () => {
  assert.match(llmConfig, /DEFAULT_MODEL\s*=\s*['"]deepseek-v4-pro['"]/, 'LlmConfig DEFAULT_MODEL must be deepseek-v4-pro');
  assert.match(providers, /id:\s*['"]deepseek['"][\s\S]*?defaultModel:\s*['"]deepseek-v4-pro['"]/, 'DeepSeek provider defaultModel must be deepseek-v4-pro');
});

test('real LLM: normalizer allows official DeepSeek model ids instead of rejecting them', () => {
  assert.match(llmConfig, /model\s*===\s*['"]deepseek-v4-flash['"]/, 'deepseek-v4-flash must be allowlisted');
  assert.match(llmConfig, /model\s*===\s*['"]deepseek-v4-pro['"]/, 'deepseek-v4-pro must be allowlisted');
  assert.match(llmConfig, /model\s*===\s*['"]deepseek-v4-flash-vision-exp['"]/, 'deepseek-v4-flash-vision-exp must be allowlisted');
  assert.match(llmConfig, /isAllowedDeepSeekModel\(lower\)[\s\S]*?return\s+t/, 'DeepSeek allowlist must return before reserved keyword rejection');
});

test('settings: active model selection is persisted per vendor', () => {
  assert.match(llmConfig, /KEY_ACTIVE_VENDOR_MODELS/, 'LlmConfig must persist active model per vendor');
  assert.match(llmConfig, /cachedActiveVendorModels\s*:\s*Record\s*<\s*string\s*,\s*string\s*>/, 'LlmConfig must cache active vendor models');
  assert.match(llmConfig, /setActiveVendorModel\s*\(\s*vendorId\s*:\s*string\s*,\s*model\s*:\s*string\s*\)/, 'LlmConfig must expose setActiveVendorModel');
  assert.match(llmConfig, /getActiveVendorModel\s*\(\s*vendorId\s*:\s*string\s*\)/, 'LlmConfig must expose getActiveVendorModel');
});

test('settings: ViewModel current model prefers selected/added model before provider default', () => {
  assert.match(vm, /activeVendorModels\s*:\s*Record\s*<\s*string\s*,\s*string\s*>/, 'ViewModel must track active model per vendor');
  assert.match(vm, /selectVendorModel\s*\(\s*vendorId\s*:\s*string\s*,\s*model\s*:\s*string\s*\)\s*:\s*void/, 'ViewModel must expose selectVendorModel');
  assert.match(vm, /getCurrentModel[\s\S]*?activeVendorModels\[this\.vendorId\]/, 'getCurrentModel must prefer activeVendorModels[current vendor]');
  assert.match(vm, /getCurrentModel[\s\S]*?vendorModels\[this\.vendorId\]/, 'getCurrentModel must consider added vendorModels');
});

test('settings: VendorPicker wires visible model row selection', () => {
  assert.match(vp, /@Prop\s+activeVendorModels\s*:\s*Record\s*<\s*string\s*,\s*string\s*>/, 'VendorPicker must receive activeVendorModels');
  assert.match(vp, /@State\s+localActiveModel\s*:\s*string/, 'VendorPicker must keep local active model draft');
  assert.match(vp, /onSelectModel\s*:\s*\(\s*vendorId\s*:\s*string\s*,\s*model\s*:\s*string\s*\)\s*=>\s*void/, 'VendorPicker must expose onSelectModel');
  assert.match(vp, /this\.localActiveModel\s*=\s*m/, 'model row click must select the active model');
});

test('settings: VendorPicker moves active model when deleting the selected model', () => {
  assert.match(vp, /if\s*\(\s*this\.localActiveModel\s*===\s*m\s*\)[\s\S]*?this\.localActiveModel\s*=\s*this\.localModels\.length\s*>\s*0\s*\?\s*this\.localModels\[0\]\s*:\s*''/, 'deleting selected model must move active model to remaining first model or empty');
});

test('settings: page wires active model selection into ViewModel', () => {
  assert.match(page, /activeVendorModels:\s*this\.vm\.activeVendorModels/, 'AiSettingsPage must pass activeVendorModels');
  assert.match(page, /onSelectModel[\s\S]*?this\.vm\.selectVendorModel\s*\(/, 'AiSettingsPage must wire onSelectModel to ViewModel');
});

test('settings: connection test saves current UI config before reading key and calling API', () => {
  const testBody = vm.match(/async\s+test\s*\(\s*\)\s*:\s*Promise\s*<\s*boolean\s*>\s*\{([\s\S]*?)\n\s*\}\n\s*async\s+testOcr/);
  assert.ok(testBody !== null, 'ViewModel test() body must be found');
  assert.match(testBody[1], /await\s+this\.saveLlm\s*\(\s*\)/, 'test() must persist current vendor/key/model before checking key');
  assert.ok(testBody[1].indexOf('await this.saveLlm()') < testBody[1].indexOf('getApiKey(this.vendorId)'), 'saveLlm() must happen before getApiKey(this.vendorId)');
});

test('settings: connection test can use API key typed in the open vendor panel', () => {
  assert.match(vp, /@State\s+originalApiKeyInput\s*:\s*string/, 'VendorPicker must remember original key for cancel rollback');
  assert.match(vp, /onChange\(\(v:\s*string\):\s*void\s*=>\s*\{[\s\S]*?this\.apiKeyInput\s*=\s*v[\s\S]*?this\.onApiKeyChange\(itemId,\s*v\)/, 'API key input must update ViewModel draft so top connection test uses the latest key');
  assert.match(vp, /cancelEdit[\s\S]*?this\.onApiKeyChange\(this\.editingVendorId,\s*this\.originalApiKeyInput\)/, 'cancel must roll back the parent draft key');
});

test('agent chain: StructureNode passes ClassifyNode result into KnowledgeModel', () => {
  assert.match(structureNode, /structureWithClassification\s*\(\s*input\.captureText\s*,\s*input\.classification/, 'StructureNode must call structureWithClassification when classification exists');
  assert.match(structureNode, /classification:\s*input\.classification/, 'StructureNode must preserve classification in next state');
});

test('diagnostics: LlmClient logs selected vendor and model without API key', () => {
  assert.match(llmClient, /request vendor=.*model=.*endpoint=.*stream=false/, 'JSON LLM request log must include vendor/model/endpoint');
  assert.match(llmClient, /request vendor=.*model=.*endpoint=.*stream=true/, 'stream LLM request log must include vendor/model/endpoint');
  assert.doesNotMatch(llmClient, /console\.info\('\[LlmClient\] request[^\n]*apiKey/, 'request diagnostics must not log API key');
});
