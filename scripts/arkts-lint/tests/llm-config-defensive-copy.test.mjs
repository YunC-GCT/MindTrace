// scripts/arkts-lint/tests/llm-config-defensive-copy.test.mjs
// T3 follow-up (2026-09-08): getAllVendorApiKeys defensive copy
// 范围:
//   - LlmConfig.getAllVendorApiKeys() 返回 {...this.cachedVendorApiKeys} 而非 mutable ref
//   - VM 修改 returned record 不应影响 LlmConfig.cachedVendorApiKeys

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const TARGET_FILE = resolve(root, 'common/src/main/ets/llm/LlmConfig.ets');
const src = readFileSync(TARGET_FILE, 'utf8').replace(/\r\n/g, '\n');

test('T3: getAllVendorApiKeys returns defensive copy (not direct this.cachedVendorApiKeys ref)', () => {
  const body = src.match(/public\s+getAllVendorApiKeys\s*\(\s*\)\s*:\s*Record\s*<\s*string\s*,\s*string\s*>\s*\{([\s\S]*?)\n\s*\}/);
  assert.ok(body !== null, 'getAllVendorApiKeys must exist');
  // 函数体必须 return 某种 spread copy(不是直接 return this.cachedVendorApiKeys)
  assert.match(
    body[1],
    /return\s*\{?\s*\.\.\.this\.cachedVendorApiKeys/,
    'getAllVendorApiKeys must return {...this.cachedVendorApiKeys} defensive copy'
  );
  // 不应 return this.cachedVendorApiKeys(无 spread)
  assert.doesNotMatch(
    body[1].replace(/\.\.\.this\.cachedVendorApiKeys/g, ''),  // 移除 spread 后的版本
    /return\s+this\.cachedVendorApiKeys\s*[;}]/,
    'getAllVendorApiKeys must NOT return direct reference (use spread for defensive copy)'
  );
});
