// scripts/arkts-lint/tests/t6-followup-cleanup.test.mjs
// T6 follow-up (2026-09-08): 修 T5 review 发现的 2 issue
// 范围:
//   - isCustomVendor 提升为 static(VM 可复用,消 magic 在 VM 重复)
//   - VM.load() legacy migration 仅在 cvList.length === 1 时 assign cachedVendorId
//     (多 vendor 时 fallback id 已 unique,不需要 migration 避免 id 冲突)

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const TARGET_LLM = resolve(root, 'common/src/main/ets/llm/LlmConfig.ets');
const TARGET_VM = resolve(root, 'entry/src/main/ets/viewmodels/AiSettingsViewModel.ets');
const llmConfig = readFileSync(TARGET_LLM, 'utf8').replace(/\r\n/g, '\n');
const vm = readFileSync(TARGET_VM, 'utf8').replace(/\r\n/g, '\n');

// ===== T6.1: isCustomVendor 提升为 static(VM 复用) =====
test('T6.1: LlmConfig.isCustomVendor is static (callable from VM without instance)', () => {
  // static method 签名:private static isCustomVendor(...)
  assert.match(
    llmConfig,
    /private\s+static\s+isCustomVendor\s*\(\s*id\s*:\s*string\s*\)\s*:\s*boolean/,
    'LlmConfig.isCustomVendor must be static (not instance method) so VM can call LlmConfig.isCustomVendor(id)'
  );
});

test('T6.1: VM uses LlmConfig.isCustomVendor (not local length > 6 && startsWith magic)', () => {
  // VM 不应再含 'custom' prefix + length>6 守卫
  assert.doesNotMatch(
    vm,
    /startsWith\(\s*['"]custom['"]\s*\)\s*&&\s*[a-zA-Z]+\.length\s*>\s*6/,
    'VM must NOT have inline startsWith("custom") && length > 6 magic (replaced by LlmConfig.isCustomVendor)'
  );
  // VM 应有 LlmConfig.isCustomVendor(...) 调用
  assert.match(
    vm,
    /LlmConfig\.isCustomVendor\s*\(/,
    'VM must call LlmConfig.isCustomVendor(...) (no inline magic)'
  );
});

// ===== T6.2: T4 migration 仅 single legacy vendor =====
test('T6.2: VM legacy migration is gated on cvList.length === 1 (multi-vendor safe)', () => {
  // legacy migration 必须有 cvList.length === 1 守卫
  // pattern: if (isCustomVendor(...) && cvList.length === 1) { ... }
  assert.match(
    vm,
    /load[\s\S]*?LlmConfig\.isCustomVendor\s*\(\s*this\.vendorId\s*\)[\s\S]*?cvList\.length\s*===\s*1/,
    'VM legacy migration must gate on cvList.length === 1 (avoid assigning same id to all multi-vendor cvList)'
  );
});
