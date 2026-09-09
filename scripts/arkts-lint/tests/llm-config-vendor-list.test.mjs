// scripts/arkts-lint/tests/llm-config-vendor-list.test.mjs
//
// L1 测试 (2026-09-08): LlmConfig per-vendor customVendors 持久化
// 范围 (spec 017):
//   - LlmConfig.cachedCustomVendors: CustomVendorConfig[] (数组而非单值)
//   - KEY_CUSTOM_VENDORS: string preferences key, JSON.stringify 持久化
//   - getCustomVendors / setCustomVendors / addCustomVendor / removeCustomVendor API
//   - getEndpoint() / getModel() 当 vendorId='custom' 时查 customVendors[] 而非单值 legacy 字段
//
// 测试策略: AST 静态检查 (与 llm-config-throw 一致) — 不需真机,跨 worktree 兼容

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, '../../..');
const TARGET_FILE = join(REPO_ROOT, 'common/src/main/ets/llm/LlmConfig.ets');

function readLlmConfigSource() {
  return readFileSync(TARGET_FILE, 'utf8').replace(/\r\n/g, '\n');
}

test('L1: LlmConfig declares cachedCustomVendors: CustomVendorConfig[] field', () => {
  const src = readLlmConfigSource();
  assert.match(
    src,
    /cachedCustomVendors\s*:\s*CustomVendorConfig\s*\[\s*\]\s*=\s*\[\s*\]/,
    'LlmConfig must declare cachedCustomVendors: CustomVendorConfig[] = []'
  );
});

test('L1: LlmConfig declares KEY_CUSTOM_VENDORS preferences key', () => {
  const src = readLlmConfigSource();
  assert.match(src, /KEY_CUSTOM_VENDORS/, 'LlmConfig must declare KEY_CUSTOM_VENDORS preferences key');
});

test('L1: LlmConfig.getCustomVendors(): CustomVendorConfig[] method exists', () => {
  const src = readLlmConfigSource();
  assert.match(
    src,
    /public\s+getCustomVendors\s*\(\s*\)\s*:\s*CustomVendorConfig\s*\[\s*\]/,
    'LlmConfig must declare public getCustomVendors(): CustomVendorConfig[] method'
  );
});

test('L1: LlmConfig.setCustomVendors(arr) persists JSON', () => {
  const src = readLlmConfigSource();
  assert.match(
    src,
    /public\s+async\s+setCustomVendors\s*\(\s*arr\s*:\s*CustomVendorConfig\s*\[\s*\]\s*\)\s*:\s*Promise\s*<\s*void\s*>/,
    'LlmConfig must declare public async setCustomVendors(arr: CustomVendorConfig[]): Promise<void>'
  );
  assert.match(src, /JSON\.stringify\(arr\)/, 'setCustomVendors must JSON.stringify the array');
});

test('L1: LlmConfig.addCustomVendor(cfg) appends + persists', () => {
  const src = readLlmConfigSource();
  assert.match(
    src,
    /public\s+async\s+addCustomVendor\s*\(\s*cfg\s*:\s*CustomVendorConfig\s*\)\s*:\s*Promise\s*<\s*void\s*>/,
    'LlmConfig must declare public async addCustomVendor(cfg: CustomVendorConfig): Promise<void>'
  );
});

test('L1: LlmConfig.removeCustomVendor removes by id (preferred) or (vendorName + baseUrl) tuple fallback', () => {
  const src = readLlmConfigSource();
  assert.match(
    src,
    /public\s+async\s+removeCustomVendor\s*\(\s*matcher\s*:\s*CustomVendorConfig\s*\)\s*:\s*Promise\s*<\s*void\s*>/,
    'LlmConfig must declare public async removeCustomVendor(matcher: CustomVendorConfig): Promise<void>'
  );
  // source-level 匹配:removeCustomVendor 必须 id 优先 + vendorName/baseUrl tuple fallback
  assert.match(
    src,
    /removeCustomVendor[\s\S]*?v\.id\s*!==\s*matcher\.id/,
    'removeCustomVendor must match by id (preferred)'
  );
  assert.match(
    src,
    /removeCustomVendor[\s\S]*?vendorName\s*===\s*matcher\.vendorName/,
    'removeCustomVendor must fallback to (vendorName + baseUrl) tuple'
  );
});

test('L1: loadAll reads customVendors JSON from preferences', () => {
  const src = readLlmConfigSource();
  // loadAll 必须含 KEY_CUSTOM_VENDORS 读 + JSON.parse(无需完整函数体解析)
  assert.match(
    src,
    /s\.get\(\s*KEY_CUSTOM_VENDORS\s*[\s\S]*?JSON\.parse/s,
    'loadAll must read KEY_CUSTOM_VENDORS from preferences and JSON.parse'
  );
});

test('L1: getEndpoint() falls back to customVendors[] when vendorId="custom"', () => {
  const src = readLlmConfigSource();
  // getEndpoint 函数体当 vendorId === 'custom' 时查 cachedCustomVendors
  const epBody = src.match(/public\s+getEndpoint\s*\(\s*\)\s*:\s*string\s*\{([\s\S]*?)\n\s*\}/);
  assert.ok(epBody !== null, 'getEndpoint body not found');
  // 通过 findCustomVendor helper 或 inline .find() 查 cachedCustomVendors
  assert.match(
    epBody[1],
    /cachedCustomVendors[^}]*find|findCustomVendor/s,
    'getEndpoint must search cachedCustomVendors when vendorId === "custom"'
  );
});

test('L1: getModel() falls back to customVendors[].model when vendorId="custom"', () => {
  const src = readLlmConfigSource();
  const modelBody = src.match(/public\s+getModel\s*\(\s*\)\s*:\s*string\s*\{([\s\S]*?)\n\s*\}/);
  assert.ok(modelBody !== null, 'getModel body not found');
  assert.match(
    modelBody[1],
    /cachedCustomVendors[^}]*find|findCustomVendor/s,
    'getModel must search cachedCustomVendors when vendorId === "custom"'
  );
});

test('L1: resetDefaults clears cachedCustomVendors + KEY_CUSTOM_VENDORS prefs', () => {
  const src = readLlmConfigSource();
  const resetBody = src.match(/public\s+async\s+resetDefaults\s*\(\s*\)\s*:\s*Promise\s*<\s*void\s*>\s*\{([\s\S]*?)\n\s*\}/);
  assert.ok(resetBody !== null, 'resetDefaults body not found');
  assert.match(
    resetBody[1],
    /cachedCustomVendors\s*=\s*\[\s*\]/,
    'resetDefaults must clear cachedCustomVendors'
  );
  assert.match(
    resetBody[1],
    /s\.delete\(\s*KEY_CUSTOM_VENDORS\s*\)/,
    'resetDefaults must delete KEY_CUSTOM_VENDORS from preferences'
  );
});
