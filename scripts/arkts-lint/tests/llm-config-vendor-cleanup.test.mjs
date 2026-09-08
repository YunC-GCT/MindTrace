// scripts/arkts-lint/tests/llm-config-vendor-cleanup.test.mjs
// L4 tests (2026-09-08): AiSettingsViewModel keyword-sniff 清理
// 范围 (spec 017 §公共接口变更):
//   - 删 useCustomEP / customEP / mdlIdx / useCustomMD / customMD / temp / maxT / to (8 fields)
//   - 删 syncEndpoint(endpoint) / syncModel(model) (2 keyword-sniff 方法)
//   - 删 12 set/toggle/resolve 方法
//   - load() 不再调 syncEndpoint / syncModel
//   - save() / test() 用 getCurrent* + LlmConfig.getTemperature 等而非 this.resolve*
//   - reset() 不再 reset 旧字段

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, '../../..');
const TARGET_FILE = join(REPO_ROOT, 'entry/src/main/ets/viewmodels/AiSettingsViewModel.ets');

function readVmSource() {
  return readFileSync(TARGET_FILE, 'utf8').replace(/\r\n/g, '\n');
}

test('L4: VM no longer declares useCustomEP / customEP / mdlIdx / useCustomMD / customMD fields', () => {
  const src = readVmSource();
  assert.doesNotMatch(src, /useCustomEP\s*:\s*boolean/, 'VM must NOT declare useCustomEP field');
  assert.doesNotMatch(src, /customEP\s*:\s*string/, 'VM must NOT declare customEP field');
  assert.doesNotMatch(src, /mdlIdx\s*:\s*number/, 'VM must NOT declare mdlIdx field');
  assert.doesNotMatch(src, /useCustomMD\s*:\s*boolean/, 'VM must NOT declare useCustomMD field');
  assert.doesNotMatch(src, /customMD\s*:\s*string/, 'VM must NOT declare customMD field');
});

test('L4: VM no longer declares temp / maxT / to fields (moved to LlmConfig cache)', () => {
  const src = readVmSource();
  // \btemp\b 等 — 字段定义形式 `: number = `
  assert.doesNotMatch(src, /\btemp\s*:\s*number\s*=/, 'VM must NOT declare temp field');
  assert.doesNotMatch(src, /\bmaxT\s*:\s*number\s*=/, 'VM must NOT declare maxT field');
  assert.doesNotMatch(src, /\bto\s*:\s*number\s*=/, 'VM must NOT declare to field');
});

test('L4: VM load() no longer calls syncEndpoint or syncModel', () => {
  const src = readVmSource();
  // load 函数体内不再调 syncEndpoint / syncModel
  const loadBody = src.match(/async\s+load\s*\(\s*\)\s*:\s*Promise\s*<\s*boolean\s*>\s*\{([\s\S]*?)\n\s*\}/);
  assert.ok(loadBody !== null, 'VM.load() body not found');
  assert.doesNotMatch(loadBody[1], /this\.syncEndpoint\(/, 'VM.load() must NOT call this.syncEndpoint()');
  assert.doesNotMatch(loadBody[1], /this\.syncModel\(/, 'VM.load() must NOT call this.syncModel()');
});

test('L4: VM save() uses getCurrent* + LlmConfig cache (not legacy resolve*)', () => {
  const src = readVmSource();
  // source-level 匹配(save 函数体内有嵌套 .map 等,body extraction 不可靠)
  assert.match(src, /save[\s\S]*?getCurrentEndpoint\(\)/, 'VM.save() must use this.getCurrentEndpoint()');
  assert.match(src, /save[\s\S]*?getCurrentModel\(\)/, 'VM.save() must use this.getCurrentModel()');
  // save 不调 resolve*
  assert.doesNotMatch(src, /save[\s\S]*?this\.resolveEndpoint\(/, 'VM.save() must NOT use this.resolveEndpoint()');
  assert.doesNotMatch(src, /save[\s\S]*?this\.resolveModel\(/, 'VM.save() must NOT use this.resolveModel()');
  assert.doesNotMatch(src, /save[\s\S]*?this\.temp/, 'VM.save() must NOT use this.temp (moved to LlmConfig cache)');
  assert.doesNotMatch(src, /save[\s\S]*?this\.maxT/, 'VM.save() must NOT use this.maxT');
  assert.doesNotMatch(src, /save[\s\S]*?this\.to,/, 'VM.save() must NOT use this.to');
});

test('L4: VM test() uses getCurrent* (not resolve*)', () => {
  const src = readVmSource();
  const testBody = src.match(/async\s+test\s*\(\s*\)\s*:\s*Promise\s*<\s*boolean\s*>\s*\{([\s\S]*?)\n\s*\}/);
  assert.ok(testBody !== null, 'VM.test() body not found');
  assert.doesNotMatch(testBody[1], /this\.resolveEndpoint\(/, 'VM.test() must NOT use this.resolveEndpoint()');
  assert.doesNotMatch(testBody[1], /this\.resolveModel\(/, 'VM.test() must NOT use this.resolveModel()');
});

test('L4: VM reset() no longer resets legacy fields', () => {
  const src = readVmSource();
  const resetBody = src.match(/async\s+reset\s*\(\s*\)\s*:\s*Promise\s*<\s*boolean\s*>\s*\{([\s\S]*?)\n\s*\}/);
  assert.ok(resetBody !== null, 'VM.reset() body not found');
  assert.doesNotMatch(resetBody[1], /this\.useCustomEP/, 'VM.reset() must NOT reset useCustomEP');
  assert.doesNotMatch(resetBody[1], /this\.customEP/, 'VM.reset() must NOT reset customEP');
  assert.doesNotMatch(resetBody[1], /this\.mdlIdx/, 'VM.reset() must NOT reset mdlIdx');
  assert.doesNotMatch(resetBody[1], /this\.useCustomMD/, 'VM.reset() must NOT reset useCustomMD');
  assert.doesNotMatch(resetBody[1], /this\.customMD/, 'VM.reset() must NOT reset customMD');
  assert.doesNotMatch(resetBody[1], /this\.temp\s*=/, 'VM.reset() must NOT reset temp');
  assert.doesNotMatch(resetBody[1], /this\.maxT\s*=/, 'VM.reset() must NOT reset maxT');
  assert.doesNotMatch(resetBody[1], /this\.to\s*=/, 'VM.reset() must NOT reset to');
});

test('L4: VM no longer declares 12 set/toggle/resolve methods', () => {
  const src = readVmSource();
  for (const method of [
    /setCustomEndpoint\s*\(\s*value\s*:\s*string\s*\)\s*:\s*void/,
    /toggleCustomEndpoint\s*\(\s*value\s*:\s*boolean\s*\)\s*:\s*void/,
    /selectModel\s*\(\s*index\s*:\s*number\s*\)\s*:\s*void/,
    /setCustomModel\s*\(\s*value\s*:\s*string\s*\)\s*:\s*void/,
    /toggleCustomModel\s*\(\s*value\s*:\s*boolean\s*\)\s*:\s*void/,
    /setTemp\s*\(\s*value\s*:\s*number\s*\)\s*:\s*void/,
    /setMaxTokens\s*\(\s*value\s*:\s*number\s*\)\s*:\s*void/,
    /setTimeout\s*\(\s*value\s*:\s*number\s*\)\s*:\s*void/,
    /syncEndpoint\s*\(\s*endpoint\s*:\s*string\s*\)\s*:\s*void/,
    /syncModel\s*\(\s*model\s*:\s*string\s*\)\s*:\s*void/,
    /resolveEndpoint\s*\(\s*\)\s*:\s*string/,
    /resolveModel\s*\(\s*\)\s*:\s*string/,
  ]) {
    assert.doesNotMatch(src, method, `VM must NOT declare ${method}`);
  }
});

test('L4: VM no longer imports DS_ENDPOINT or PRO_MODEL (legacy constants)', () => {
  const src = readVmSource();
  assert.doesNotMatch(src, /from\s+["']\.\.\/pages\/AiSettings\/EndpointPicker["']/, 'VM must NOT import from EndpointPicker (L5 will git rm)');
  assert.doesNotMatch(src, /from\s+["']\.\.\/pages\/AiSettings\/ModelPicker["']/, 'VM must NOT import from ModelPicker (L5 will git rm)');
});

test('L4: VM no longer declares currentModelText / modelLabel / endpointLabel (replaced by getCurrent*)', () => {
  const src = readVmSource();
  assert.doesNotMatch(src, /currentModelText\s*\(\s*\)\s*:\s*string/, 'VM must NOT declare currentModelText()');
  assert.doesNotMatch(src, /modelLabel\s*\(\s*\)\s*:\s*string/, 'VM must NOT declare modelLabel()');
  assert.doesNotMatch(src, /endpointLabel\s*\(\s*\)\s*:\s*string/, 'VM must NOT declare endpointLabel()');
});
