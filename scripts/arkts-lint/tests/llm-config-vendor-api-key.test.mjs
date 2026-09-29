// scripts/arkts-lint/tests/llm-config-vendor-api-key.test.mjs
// L3 测试 (2026-09-08): LlmConfig per-vendor API Key 持久化
// 范围 (spec 017):
//   - LlmConfig.cachedVendorApiKeys: Record<string, string>
//   - KEY_VENDOR_API_KEYS: string preferences key, JSON record
//   - getApiKey(vendorId): per-vendor map 优先,fallback 全局 ApiKeyVault
//   - setApiKey(key, vendorId?): per-vendor 写 map 或全局 ApiKeyVault
//   - clearApiKey(vendorId?): per-vendor map 删或全局清

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

test('L3: LlmConfig declares cachedVendorApiKeys: Record<string, string> field', () => {
  const src = readLlmConfigSource();
  assert.match(
    src,
    /cachedVendorApiKeys\s*:\s*Record\s*<\s*string\s*,\s*string\s*>/,
    'LlmConfig must declare cachedVendorApiKeys: Record<string, string>'
  );
});

test('L3: LlmConfig declares KEY_VENDOR_API_KEYS preferences key', () => {
  const src = readLlmConfigSource();
  assert.match(src, /KEY_VENDOR_API_KEYS/, 'LlmConfig must declare KEY_VENDOR_API_KEYS preferences key');
});

test('L3: LlmConfig.getApiKey(vendorId): Promise<string|null> overload exists', () => {
  const src = readLlmConfigSource();
  assert.match(
    src,
    /public\s+(?:async\s+)?getApiKey\s*\(\s*vendorId\s*\?\s*:\s*string\s*\)\s*:\s*Promise\s*<\s*string\s*\|\s*null\s*>/,
    'LlmConfig must declare public getApiKey(vendorId?: string): Promise<string | null>'
  );
});

test('L3: getApiKey(vendorId) checks per-vendor map before global fallback', () => {
  const src = readLlmConfigSource();
  // getApiKey 必须 reference cachedVendorApiKeys[keyVendorId] AND ApiKeyVault.get() (fallback)
  assert.match(
    src,
    /cachedVendorApiKeys[^}]*keyVendorId[^}]*length\s*>\s*0/s,
    'getApiKey must check cachedVendorApiKeys[keyVendorId] length > 0'
  );
  assert.match(
    src,
    /ApiKeyVault\.get\(\)/,
    'getApiKey must fallback to ApiKeyVault.get() when no per-vendor key'
  );
});

test('L3: LlmConfig.setApiKey(key, vendorId?) overload exists', () => {
  const src = readLlmConfigSource();
  assert.match(
    src,
    /public\s+async\s+setApiKey\s*\(\s*key\s*:\s*string\s*,\s*vendorId\s*\?\s*:\s*string\s*\)\s*:\s*Promise\s*<\s*void\s*>/,
    'LlmConfig must declare public async setApiKey(key: string, vendorId?: string): Promise<void>'
  );
});

test('L3: setApiKey(key) without vendorId still routes to global ApiKeyVault (back-compat)', () => {
  const src = readLlmConfigSource();
  // setApiKey 必须 reference ApiKeyVault.put() (在无 vendorId 路径)— source-level pattern
  assert.match(
    src,
    /ApiKeyVault\.put\(/,
    'setApiKey must reference ApiKeyVault.put() for global fallback (back-compat)'
  );
});

test('L3: LlmConfig.clearApiKey(vendorId?) overload exists', () => {
  const src = readLlmConfigSource();
  assert.match(
    src,
    /public\s+async\s+clearApiKey\s*\(\s*vendorId\s*\?\s*:\s*string\s*\)\s*:\s*Promise\s*<\s*void\s*>/,
    'LlmConfig must declare public async clearApiKey(vendorId?: string): Promise<void>'
  );
});

test('L3: loadAll reads vendorApiKeys JSON from preferences', () => {
  const src = readLlmConfigSource();
  assert.match(
    src,
    /s\.get\(\s*KEY_VENDOR_API_KEYS\s*[\s\S]*?JSON\.parse/s,
    'loadAll must read KEY_VENDOR_API_KEYS from preferences and JSON.parse'
  );
});

test('L3: resetDefaults clears cachedVendorApiKeys + KEY_VENDOR_API_KEYS prefs', () => {
  const src = readLlmConfigSource();
  const resetBody = src.match(/public\s+async\s+resetDefaults\s*\(\s*\)\s*:\s*Promise\s*<\s*void\s*>\s*\{([\s\S]*?)\n\s*\}/);
  assert.ok(resetBody !== null, 'resetDefaults body not found');
  assert.match(
    resetBody[1],
    /cachedVendorApiKeys\s*=\s*\{\s*\}/,
    'resetDefaults must clear cachedVendorApiKeys'
  );
  assert.match(
    resetBody[1],
    /s\.delete\(\s*KEY_VENDOR_API_KEYS\s*\)/,
    'resetDefaults must delete KEY_VENDOR_API_KEYS from preferences'
  );
});

// === L3 wiring (2026-09-08): LlmClient 用 per-vendor key ===

test('L3 wiring: LlmClient.callJsonInternal passes getVendorId() to getApiKey', () => {
  const src = readFileSync(
    resolve(REPO_ROOT, 'common/src/main/ets/llm/LlmClient.ets'),
    'utf8'
  );
  // callJsonInternal 必须用 this.config.getApiKey(this.config.getVendorId())
  assert.match(
    src,
    /getApiKey\(\s*this\.config\.getVendorId\(\)\s*\)/,
    'LlmClient.callJsonInternal must call getApiKey with current vendorId (per-vendor key)'
  );
});

test('L3 wiring: LlmClient.callStreamInternal passes getVendorId() to getApiKey', () => {
  const src = readFileSync(
    resolve(REPO_ROOT, 'common/src/main/ets/llm/LlmClient.ets'),
    'utf8'
  );
  assert.match(
    src,
    /getApiKey\(\s*this\.config\.getVendorId\(\)\s*\)/,
    'LlmClient.callStreamInternal must call getApiKey with current vendorId (per-vendor key)'
  );
});
