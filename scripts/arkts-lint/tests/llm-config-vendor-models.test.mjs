// scripts/arkts-lint/tests/llm-config-vendor-models.test.mjs
//
// L2 测试 (2026-09-08): LlmConfig per-vendor models 持久化
// 范围 (spec 017):
//   - LlmConfig.cachedVendorModels: Record<string, string[]>
//   - KEY_VENDOR_MODELS: string preferences key, JSON record
//   - getVendorModels / addVendorModel / removeVendorModel API
//   - getModel() 当 vendorId 是 preset 时返回 vendorModels[0] ?? defaultModel

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

test('L2: LlmConfig declares cachedVendorModels: Record<string, string[]> field', () => {
  const src = readLlmConfigSource();
  assert.match(
    src,
    /cachedVendorModels\s*:\s*Record\s*<\s*string\s*,\s*string\s*\[\s*\]\s*>/,
    'LlmConfig must declare cachedVendorModels: Record<string, string[]>'
  );
});

test('L2: LlmConfig declares KEY_VENDOR_MODELS preferences key', () => {
  const src = readLlmConfigSource();
  assert.match(src, /KEY_VENDOR_MODELS/, 'LlmConfig must declare KEY_VENDOR_MODELS preferences key');
});

test('L2: LlmConfig.getVendorModels(vendorId): string[] method exists', () => {
  const src = readLlmConfigSource();
  assert.match(
    src,
    /public\s+getVendorModels\s*\(\s*vendorId\s*:\s*string\s*\)\s*:\s*string\s*\[\s*\]/,
    'LlmConfig must declare public getVendorModels(vendorId: string): string[]'
  );
});

test('L2: LlmConfig.addVendorModel(vendorId, model) persists', () => {
  const src = readLlmConfigSource();
  assert.match(
    src,
    /public\s+async\s+addVendorModel\s*\(\s*vendorId\s*:\s*string\s*,\s*model\s*:\s*string\s*\)\s*:\s*Promise\s*<\s*void\s*>/,
    'LlmConfig must declare public async addVendorModel(vendorId, model): Promise<void>'
  );
});

test('L2: LlmConfig.removeVendorModel(vendorId, model) persists', () => {
  const src = readLlmConfigSource();
  assert.match(
    src,
    /public\s+async\s+removeVendorModel\s*\(\s*vendorId\s*:\s*string\s*,\s*model\s*:\s*string\s*\)\s*:\s*Promise\s*<\s*void\s*>/,
    'LlmConfig must declare public async removeVendorModel(vendorId, model): Promise<void>'
  );
});

test('L2: loadAll reads vendorModels JSON from preferences', () => {
  const src = readLlmConfigSource();
  assert.match(
    src,
    /s\.get\(\s*KEY_VENDOR_MODELS\s*[\s\S]*?JSON\.parse/s,
    'loadAll must read KEY_VENDOR_MODELS from preferences and JSON.parse'
  );
});

test('L2: getModel() prefers vendorModels[vendorId][0] over defaultModel for preset vendors', () => {
  const src = readLlmConfigSource();
  // getModel 当 vendorId 不是 'custom' 时,查 vendorModels[vendorId]
  assert.match(
    src,
    /cachedVendorModels[^}]*vendorId[^}]*\[/s,
    'getModel must lookup cachedVendorModels[vendorId] for preset vendors'
  );
});

test('L2: resetDefaults clears cachedVendorModels + KEY_VENDOR_MODELS prefs', () => {
  const src = readLlmConfigSource();
  const resetBody = src.match(/public\s+async\s+resetDefaults\s*\(\s*\)\s*:\s*Promise\s*<\s*void\s*>\s*\{([\s\S]*?)\n\s*\}/);
  assert.ok(resetBody !== null, 'resetDefaults body not found');
  assert.match(
    resetBody[1],
    /cachedVendorModels\s*=\s*\{\s*\}/,
    'resetDefaults must clear cachedVendorModels'
  );
  assert.match(
    resetBody[1],
    /s\.delete\(\s*KEY_VENDOR_MODELS\s*\)/,
    'resetDefaults must delete KEY_VENDOR_MODELS from preferences'
  );
});
