// scripts/arkts-lint/tests/vendor-picker-remove-edit-button.test.mjs
// PR2-T2 ticket #83 follow-up (2026-09-08): 删 编辑 button
// panel 改 always-visible 后,编辑 button 变成死 UI(只 toggle editingVendorId,无视觉效果)
// 删:Text('编辑') + onClick + @State editingVendorId + onEdit 回调

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const TARGET_FILE = resolve(root, 'entry/src/main/ets/pages/AiSettings/VendorPicker.ets');
const src = readFileSync(TARGET_FILE, 'utf8').replace(/\r\n/g, '\n');

test('VendorPicker: 删 编辑 button Text(\'编辑\')(always-visible 后无意义)', () => {
  assert.doesNotMatch(
    src,
    /Text\(\s*['"]编辑['"]\s*\)/,
    'VendorPicker must NOT have Text("编辑") button (panel always-visible 后,编辑 无视觉效果)'
  );
});

test('VendorPicker: 删 @State editingVendorId(无 gating 用处)', () => {
  assert.doesNotMatch(
    src,
    /@State\s+editingVendorId\s*:/,
    'VendorPicker must NOT have @State editingVendorId field (panel always-visible,无 gating 用处)'
  );
});

test('VendorPicker: 删 onEdit callback 声明(无 caller)', () => {
  // 旧:onEdit: (id: string) => void = (_id: string): void => {};
  assert.doesNotMatch(
    src,
    /onEdit\s*:\s*\(\s*id\s*:\s*string\s*\)\s*=>\s*void\s*=/,
    'VendorPicker must NOT declare onEdit callback (no caller after always-visible change)'
  );
});
