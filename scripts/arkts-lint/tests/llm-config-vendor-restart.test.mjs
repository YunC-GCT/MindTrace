// scripts/arkts-lint/tests/llm-config-vendor-restart.test.mjs
// 回归测试 (2026-09-08): 双轴审查发现的 critical bug 修复
//
// Bug #1: Custom vendor ID 重生成 — load() 用 NEW id(custom-loaded-{i}-{now})
//   而不是 LlmConfig 存的 id,导致 getCurrentEndpoint/getCurrentModel 重启后 lookup miss 返回 ''
// Bug #2: addCustomVendor 的 apiKey 在 save() 丢失(save 只持久 vendorName/baseUrl/model)
// Bug #3: load() 只还原当前 vendor 的 apiKey(asymmetric load/save)
// Bug #4: 2 处 `delete obj.prop` 违反 arkts-no-delete
//
// 这些 bug 让 user 真实目标"整个后端的大模型链路不断"在 custom vendor 重启后断开。

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8').replace(/\r\n/g, '\n');

const llmConfig = read('common/src/main/ets/llm/LlmConfig.ets');
const providers = read('common/src/main/ets/llm/providers.ets');
const vm = read('entry/src/main/ets/viewmodels/AiSettingsViewModel.ets');

// ===== Bug #1 修复:CustomVendorConfig 含 id 字段,load() 复用 =====
test('regression Bug #1: CustomVendorConfig interface declares id field', () => {
  // 严格匹配 interface CustomVendorConfig { ... id: string; ... }(允许 ? 可选标记)
  const match = providers.match(/interface\s+CustomVendorConfig\s*\{([\s\S]*?)\}/);
  assert.ok(match !== null, 'CustomVendorConfig interface must exist');
  assert.match(
    match[1],
    /^\s*id\??\s*:\s*string/m,
    'CustomVendorConfig must declare id: string (or id?: string) for stable identity across save/load'
  );
});

test('regression Bug #1: VM.toCustomVendorFull preserves saved id (no Date.now() regen)', () => {
  // helper 函数必须在 load 路径使用,不能 regenerate
  // 不应有 'custom-loaded-' prefix(那是 regen)
  assert.doesNotMatch(
    vm,
    /custom-loaded-\$\{i\}/,
    'VM must NOT regenerate id on load — must reuse LlmConfig saved id'
  );
});

test('regression Bug #1: VM.save() must write id field (not strip it)', () => {
  // setCustomVendors 接受的对象必须含 id(vendorName+baseUrl+model+id)
  // 简化:save 中 setCustomVendors 调用的 .map callback 必须返回含 id 的对象
  // 即 (v): CustomVendorFull => ({ ..., id: v.id, ... }) 而非 ({ vendorName, baseUrl, model })
  assert.match(
    vm,
    /setCustomVendors[\s\S]*?id:\s*v\.id/,
    'VM.save() setCustomVendors.map must include id: v.id (preserve identity)'
  );
});

test('regression Bug #1: LlmConfig.findCustomVendor matches by id (not always [0])', () => {
  const findBody = llmConfig.match(/private\s+findCustomVendor\s*\([^)]*\)\s*:\s*CustomVendorConfig\s*\|\s*null\s*\{([\s\S]*?)\n\s*\}/);
  assert.ok(findBody !== null, 'findCustomVendor must exist');
  // 内部循环 must match by id(v.id === id) — 不是 cachedCustomVendors[0]
  assert.match(
    findBody[1],
    /v\.id\s*===\s*id/,
    'findCustomVendor must match by v.id === id (not always return cachedCustomVendors[0])'
  );
});

test('regression Bug #1: getEndpoint() fallback to customVendors match for any custom-prefix id', () => {
  // PR2-T2 ticket #83 T2 (2026-09-08): 用 isCustomVendor helper 替代 startsWith magic
  const epBody = llmConfig.match(/public\s+getEndpoint\s*\(\s*\)\s*:\s*string\s*\{([\s\S]*?)\n\s*\}/);
  assert.ok(epBody !== null, 'getEndpoint body not found');
  assert.match(
    epBody[1],
    /isCustomVendor\s*\(\s*this\.cachedVendorId\s*\)/,
    'getEndpoint must use isCustomVendor(this.cachedVendorId) helper'
  );
});

// ===== Bug #2 修复:save() 持久化 per-custom-vendor apiKey =====
test('regression Bug #2: VM.save() persists per-custom-vendor apiKey via llm.setApiKey', () => {
  // source-level 匹配(避免 body extraction 嵌套 {} 失败)
  assert.match(
    vm,
    /save[\s\S]*?setApiKey\s*\(\s*[^,)]+,\s*v\.id\s*\)/,
    'VM.save() must call llm.setApiKey(apiKey, vendorId) for each custom vendor'
  );
});

// ===== Bug #3 修复:load() 还原所有 vendorApiKeys =====
test('regression Bug #3: VM.load() restores ALL vendorApiKeys (not just current)', () => {
  // source-level 匹配
  assert.match(
    vm,
    /load[\s\S]*?vendorApiKeys\s*=\s*llm\.getAllVendorApiKeys\(\)/,
    'VM.load() must restore ALL vendorApiKeys via llm.getAllVendorApiKeys() (not just current)'
  );
});

test('regression Bug #3: LlmConfig exposes getAllVendorApiKeys(): Record<string, string> method', () => {
  assert.match(
    llmConfig,
    /public\s+getAllVendorApiKeys\s*\(\s*\)\s*:\s*Record\s*<\s*string\s*,\s*string\s*>/,
    'LlmConfig must expose getAllVendorApiKeys(): Record<string, string> method'
  );
});

// ===== Bug #4 修复:无 `delete obj.prop`(arkts-no-delete) =====
test('regression Bug #4: LlmConfig has no `delete obj.prop` (arkts-no-delete)', () => {
  // source-level 检查
  assert.doesNotMatch(
    llmConfig,
    /delete\s+(this|llm|llmConfig|this\.cached)/,
    'LlmConfig must NOT use delete operator (arkts-no-delete; use rebuild Record pattern)'
  );
});
