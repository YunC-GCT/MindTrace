// scripts/arkts-lint/tests/llm-config-provider-vendor.test.mjs
//
// PR2-T1 RED 测试: providers.ets 5 厂商预设 + LlmConfig vendorId/customVendorConfig 字段
//
// 范围(spec 016 PR2-T1):
//   - common/src/main/ets/llm/providers.ets (新建)
//   - LlmConfig 加 getVendorId / setVendorId / getCustomVendorConfig / setCustomVendorConfig
//   - LlmConfig.getEndpoint() / getModel() 解析 vendorId
//   - 持久化(KEY_VENDOR_ID + KEY_CUSTOM_VENDOR as JSON)
//   - common/src/main/ets/Index.ets re-export
//
// 注意: 所有 regex 容忍 ArkTS 类型注解(如 `: string`)

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => {
  try { return readFileSync(resolve(root, p), 'utf8'); } catch { return ''; }
};

const providers = read('common/src/main/ets/llm/providers.ets');
const llmConfig = read('common/src/main/ets/llm/LlmConfig.ets');
const commonIndex = read('common/src/main/ets/Index.ets');

// === providers.ets 存在性 + 基本结构 ===

test('providers.ets exists at common/src/main/ets/llm/providers.ets', () => {
  assert.ok(
    existsSync(resolve(root, 'common/src/main/ets/llm/providers.ets')),
    'providers.ets must be created at common/src/main/ets/llm/providers.ets'
  );
});

test('providers.ets exports PROVIDERS array with 5 vendors', () => {
  assert.match(providers, /export\s+const\s+PROVIDERS/, 'PROVIDERS must be exported');
  const ids = providers.match(/id:\s*['"]([a-z]+)['"]/g) ?? [];
  assert.equal(ids.length, 5, 'PROVIDERS must have exactly 5 entries');
});

test('PROVIDERS contains deepseek, tongyi, glm, kimi, doubao', () => {
  for (const id of ['deepseek', 'tongyi', 'glm', 'kimi', 'doubao']) {
    assert.match(providers, new RegExp(`id:\\s*['"]${id}['"]`), `PROVIDERS must contain vendor "${id}"`);
  }
});

test('PROVIDERS defaultModel uses 2026-09 一手调研的当前推荐', () => {
  assert.match(providers, /id:\s*['"]deepseek['"][\s\S]*?defaultModel:\s*['"]deepseek-v4-pro['"]/);
  assert.match(providers, /id:\s*['"]tongyi['"][\s\S]*?defaultModel:\s*['"]qwen3/);
  assert.match(providers, /id:\s*['"]glm['"][\s\S]*?defaultModel:\s*['"]glm-5\.3['"]/);
  assert.match(providers, /id:\s*['"]kimi['"][\s\S]*?defaultModel:\s*['"]kimi-k/);
  assert.match(providers, /id:\s*['"]doubao['"][\s\S]*?defaultModel:\s*['"]doubao-seed/);
});

test('PROVIDERS baseUrl 都是 https OpenAI 兼容 endpoint', () => {
  const urls = providers.match(/baseUrl:\s*['"]([^'"]+)['"]/g) ?? [];
  assert.ok(urls.length >= 5, 'PROVIDERS must have 5+ baseUrl');
  for (const u of urls) { assert.match(u, /baseUrl:\s*['"]https:\/\//, `baseUrl must be https: ${u}`); }
});

test('PROVIDERS protocolKind 都是 openai-compatible (Q2=A)', () => {
  const kinds = providers.match(/protocolKind:\s*['"]([^'"]+)['"]/g) ?? [];
  assert.ok(kinds.length >= 5);
  for (const k of kinds) {
    assert.equal(k.match(/['"]([^'"]+)['"]/)?.[1], 'openai-compatible', 'PR2-T1 only supports openai-compatible');
  }
});

// === DEFAULT_VENDOR_ID + findProvider (ArkTS 注解容忍) ===

test('providers.ets exports DEFAULT_VENDOR_ID = "deepseek"', () => {
  assert.match(providers, /DEFAULT_VENDOR_ID[^=]*=\s*['"]deepseek['"]/);
  assert.match(providers, /export\s+const\s+DEFAULT_VENDOR_ID\b/);
});

test('providers.ets exports findProvider(id: string): ProviderConfig | null', () => {
  assert.match(providers, /export\s+function\s+findProvider\s*\(\s*id\s*:\s*string\s*\)\s*:\s*ProviderConfig\s*\|\s*null/);
  assert.match(providers, /return\s+p\b/, 'findProvider must return matching provider');
  assert.match(providers, /return\s+null\b/, 'findProvider must return null when not found');
});

// === LlmConfig vendorId / customVendorConfig 字段 (ArkTS 注解容忍) ===

test('LlmConfig has cachedVendorId field with default "deepseek"', () => {
  assert.match(llmConfig, /private\s+cachedVendorId[^;]*=\s*['"]deepseek['"]/);
});

test('LlmConfig has cachedCustomVendor field (nullable)', () => {
  assert.match(llmConfig, /private\s+cachedCustomVendor[^;]*:\s*CustomVendorConfig\s*\|\s*null/);
});

test('LlmConfig declares getVendorId() and setVendorId()', () => {
  assert.match(llmConfig, /public\s+getVendorId\s*\(\s*\)\s*:\s*string/);
  assert.match(llmConfig, /public\s+async\s+setVendorId\s*\(\s*id\s*:\s*string\s*\)\s*:\s*Promise\s*<\s*void\s*>/);
});

test('LlmConfig declares getCustomVendorConfig() and setCustomVendorConfig()', () => {
  assert.match(llmConfig, /public\s+getCustomVendorConfig\s*\(\s*\)\s*:\s*CustomVendorConfig\s*\|\s*null/);
  assert.match(llmConfig, /public\s+async\s+setCustomVendorConfig\s*\(\s*cfg\s*:\s*CustomVendorConfig\s*\|\s*null\s*\)\s*:\s*Promise\s*<\s*void\s*>/);
});

test('LlmConfig loadAll reads vendorId and customVendor from preferences', () => {
  assert.match(llmConfig, /KEY_VENDOR_ID/);
  assert.match(llmConfig, /KEY_CUSTOM_VENDOR/);
});

test('LlmConfig.getEndpoint() resolves by vendorId (preset)', () => {
  assert.match(llmConfig, /public\s+getEndpoint\s*\(\s*\)\s*:\s*string\s*\{/);
  assert.match(llmConfig, /findProvider|cachedVendorId/);
});

test('LlmConfig.getModel() resolves by vendorId (preset)', () => {
  assert.match(llmConfig, /public\s+getModel\s*\(\s*\)\s*:\s*string\s*\{/);
  assert.match(llmConfig, /findProvider|cachedVendorId/);
});

test('LlmConfig.getEndpoint() returns customVendor.baseUrl when vendorId="custom"', () => {
  assert.match(llmConfig, /['"]custom['"]/);
  assert.match(llmConfig, /cachedCustomVendor/);
  assert.match(llmConfig, /\.baseUrl/);
});

test('LlmConfig.resetDefaults() resets vendorId to "deepseek"', () => {
  assert.match(llmConfig, /public\s+async\s+resetDefaults\s*\(\s*\)\s*:\s*Promise\s*<\s*void\s*>/);
  // resetDefaults 函数体内设 cachedVendorId = 'deepseek'
  const rd = llmConfig.match(/public\s+async\s+resetDefaults\s*\([\s\S]*?\)\s*:\s*Promise\s*<\s*void\s*>\s*\{([\s\S]*?)\n\s*\}\s*\n/);
  assert.ok(rd !== null, 'resetDefaults must exist');
  assert.match(rd[1], /cachedVendorId[^;]*=\s*['"]deepseek['"]/);
});

// === Index.ets re-export ===

test('common Index.ets re-exports PROVIDERS, DEFAULT_VENDOR_ID, findProvider', () => {
  assert.match(commonIndex, /PROVIDERS[,\s}]/, 'must export PROVIDERS');
  assert.match(commonIndex, /DEFAULT_VENDOR_ID/, 'must export DEFAULT_VENDOR_ID');
  assert.match(commonIndex, /findProvider/, 'must export findProvider');
});

test('common Index.ets re-exports ProviderConfig and CustomVendorConfig types', () => {
  assert.match(commonIndex, /export\s+type\s*\{[^}]*ProviderConfig/, 'must export type ProviderConfig');
  assert.match(commonIndex, /export\s+type\s*\{[^}]*CustomVendorConfig/, 'must export type CustomVendorConfig');
});

// === PR2-T2 集成修复(2026-09-08): vendor-aware normalize ===

// vendor-aware normalize:必须存在 ForVendor 私有重载
test('LlmConfig.normalizeEndpoint/normalizeModel have vendor-aware ForVendor overload', () => {
  assert.match(llmConfig, /normalizeEndpointForVendor/, 'normalizeEndpoint must have ForVendor overload for vendor-aware keyword check');
  assert.match(llmConfig, /normalizeModelForVendor/, 'normalizeModel must have ForVendor overload for vendor-aware keyword check');
});

// vendor-aware normalizeModel:reserved keywords 仅 vendorId === 'deepseek' 抛错
test('LlmConfig.normalizeModel reserved keywords (flash/v3/r1/etc) gated by vendorId === "deepseek"', () => {
  // 找到 normalizeModelForVendor 的 vendorId check + throw 块
  assert.match(
    llmConfig,
    /if\s*\(\s*vendorId\s*===\s*['"]deepseek['"]\s*\)\s*\{[\s\S]*?lower\.indexOf\(\s*['"]flash['"]\s*\)/,
    'normalizeModel reserved keywords must be wrapped in if (vendorId === "deepseek") check'
  );
});

// vendor-aware normalizeEndpoint: 'siliconflow' 仅 vendorId === 'deepseek' 抛错
test('LlmConfig.normalizeEndpoint siliconflow keyword gated by vendorId === "deepseek"', () => {
  assert.match(
    llmConfig,
    /vendorId\s*===\s*['"]deepseek['"]\s*&&\s*lower\.indexOf\(\s*['"]siliconflow['"]\s*\)/,
    'normalizeEndpoint siliconflow check must include vendorId === "deepseek" gate'
  );
});
