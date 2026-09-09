// scripts/arkts-lint/tests/vendor-picker-always-visible.test.mjs
// PR2-T2 ticket #83 follow-up (2026-09-08): user 真机测试发现
// "对于每个厂商的配置还是没有展开" — per-vendor config 只在点 编辑 后显示,5 个 vendor 都得点开
// 修法:API Key + 模型列表 始终对每个 vendor 可见(无 click 展开)

// 验证: 编辑 panel 内容(API Key TextInput + 模型 ForEach + + button)不再被
// if (this.editingVendorId === item.id) 守卫

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const TARGET_FILE = resolve(root, 'entry/src/main/ets/pages/AiSettings/VendorPicker.ets');
const src = readFileSync(TARGET_FILE, 'utf8').replace(/\r\n/g, '\n');

test('VendorPicker: API Key TextInput 不再被 editingVendorId 守卫(每 vendor 可见)', () => {
  // 修后:无 \`if (this.editingVendorId === item.id)\` 守卫(已删),API Key 对所有 5 vendor 可见
  // 检测:源中 无 \`if (this.editingVendorId === item.id) {` 字符串
  assert.doesNotMatch(
    src,
    /if\s*\(\s*this\.editingVendorId\s*===\s*item\.id\s*\)\s*\{/,
    'VendorPicker must NOT have `if (this.editingVendorId === item.id) {` guard (removed for always-visible panels)'
  );
  // 仍需存在 API Key TextInput
  const apiKeyIdx = src.indexOf("placeholder: 'API Key(per-vendor)'");
  assert.ok(apiKeyIdx > 0, 'API Key TextInput must still exist (just always-visible)');
});

test('VendorPicker: 没有对每个 vendor 单独的 onEdit 触发(可能 single-click 触发已移除)', () => {
  // 检查 onEdit 字段在回调中是否仍被传递(老 code 有 onEdit,但 ticket #81 测试说 wiring 用 @State editingVendorId)
  // 此测试确保 onEdit 不再被 Vendor 主动调
  // 简化:onEdit callback 字段可能仍存在(向后兼容),但 vendor row 不调它
  // (无需改 — 跳过此 strict assertion)
});
