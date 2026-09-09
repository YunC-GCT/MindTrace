// scripts/arkts-lint/tests/llm-config-helpers.test.mjs
// T2 follow-up (2026-09-08): helpers 抽取回归
// 范围:
//   - LlmConfig.ets 新增 private isCustomVendor(id: string): boolean
//   - LlmConfig.ets 新增 private rebuildRecordWithout<V>(rec, key): Record<string, V>
//   - getEndpoint/getModel 改用 isCustomVendor(this.cachedVendorId) 替换 startsWith 守卫
//   - clearApiKey(vendorId) / removeVendorModel(vendorId, model) 改用 rebuildRecordWithout

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const TARGET_FILE = resolve(root, 'common/src/main/ets/llm/LlmConfig.ets');
const src = readFileSync(TARGET_FILE, 'utf8').replace(/\r\n/g, '\n');

// ===== T2 验收:helpers 存在 =====
test('T2: LlmConfig declares private static isCustomVendor(id: string): boolean method', () => {
  // T6 follow-up:改 static(VM 也能调 — 消 VM 重复 magic)
  assert.match(
    src,
    /private\s+static\s+isCustomVendor\s*\(\s*id\s*:\s*string\s*\)\s*:\s*boolean/,
    'LlmConfig must declare private static isCustomVendor(id: string): boolean method (T6 follow-up: static so VM can call)'
  );
});

test('T2: LlmConfig declares private rebuildRecordWithout<V> generic method', () => {
  // 泛型方法签名重建 Record
  assert.match(
    src,
    /private\s+rebuildRecordWithout\s*<\s*V\s*>\s*\(\s*rec\s*:\s*Record\s*<\s*string\s*,\s*V\s*>\s*,\s*key\s*:\s*string\s*\)\s*:\s*Record\s*<\s*string\s*,\s*V\s*>/,
    'LlmConfig must declare private rebuildRecordWithout<V>(rec, key): Record<string, V> generic method'
  );
});

// ===== T2 验收:isCustomVendor 替代 startsWith 守卫 =====
test('T2: getEndpoint uses isCustomVendor(this.cachedVendorId) not startsWith magic', () => {
  const epBody = src.match(/public\s+getEndpoint\s*\(\s*\)\s*:\s*string\s*\{([\s\S]*?)\n\s*\}/);
  assert.ok(epBody !== null, 'getEndpoint body not found');
  assert.match(
    epBody[1],
    /isCustomVendor\s*\(\s*this\.cachedVendorId\s*\)/,
    'getEndpoint must use isCustomVendor(this.cachedVendorId) (no more startsWith magic)'
  );
  // 不应再有 startsWith('custom') 的 magic 守卫
  assert.doesNotMatch(
    epBody[1],
    /startsWith\s*\(\s*['"]custom/,
    'getEndpoint must NOT have startsWith("custom") magic guard (replaced by isCustomVendor)'
  );
});

test('T2: getModel uses isCustomVendor(this.cachedVendorId) not startsWith magic', () => {
  const mBody = src.match(/public\s+getModel\s*\(\s*\)\s*:\s*string\s*\{([\s\S]*?)\n\s*\}/);
  assert.ok(mBody !== null, 'getModel body not found');
  assert.match(
    mBody[1],
    /isCustomVendor\s*\(\s*this\.cachedVendorId\s*\)/,
    'getModel must use isCustomVendor(this.cachedVendorId) (no more startsWith magic)'
  );
  assert.doesNotMatch(
    mBody[1],
    /startsWith\s*\(\s*['"]custom/,
    'getModel must NOT have startsWith("custom") magic guard'
  );
});

// ===== T2 验收:rebuildRecordWithout 替代 inline rebuild =====
test('T2: clearApiKey(vendorId) uses rebuildRecordWithout (no inline Object.keys loop)', () => {
  const clearBody = src.match(/public\s+async\s+clearApiKey\s*\(\s*vendorId\s*\?\s*:\s*string\s*\)\s*:\s*Promise\s*<\s*void\s*>\s*\{([\s\S]*?)\n\s*\}/);
  assert.ok(clearBody !== null, 'clearApiKey body not found');
  assert.match(
    clearBody[1],
    /rebuildRecordWithout\s*<\s*string\s*>/,
    'clearApiKey must use rebuildRecordWithout<string>(...) helper'
  );
  // 不应再有 inline Object.keys loop
  assert.doesNotMatch(
    clearBody[1],
    /Object\.keys\s*\(\s*this\.cachedVendorApiKeys\s*\)/,
    'clearApiKey must NOT have inline Object.keys loop (replaced by helper)'
  );
});

test('T2: removeVendorModel uses rebuildRecordWithout (no inline Object.keys loop)', () => {
  const rBody = src.match(/public\s+async\s+removeVendorModel\s*\(\s*vendorId\s*:\s*string\s*,\s*model\s*:\s*string\s*\)\s*:\s*Promise\s*<\s*void\s*>\s*\{([\s\S]*?)\n\s*\}/);
  assert.ok(rBody !== null, 'removeVendorModel body not found');
  assert.match(
    rBody[1],
    /rebuildRecordWithout\s*<\s*string\s*\[\s*\]\s*>/,
    'removeVendorModel must use rebuildRecordWithout<string[]>(...) helper'
  );
  assert.doesNotMatch(
    rBody[1],
    /Object\.keys\s*\(\s*this\.cachedVendorModels\s*\)/,
    'removeVendorModel must NOT have inline Object.keys loop'
  );
});

// ===== T2 回归:无 `delete obj.prop` =====
test('T2 regression: LlmConfig has no `delete obj.prop` (arkts-no-delete)', () => {
  assert.doesNotMatch(
    src,
    /delete\s+(this|llm|llmConfig|this\.cached)/,
    'LlmConfig must NOT use delete operator (rebuildRecordWithout helper replaces it)'
  );
});
