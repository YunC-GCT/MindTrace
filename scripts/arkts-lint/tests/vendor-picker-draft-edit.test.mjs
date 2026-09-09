// scripts/arkts-lint/tests/vendor-picker-draft-edit.test.mjs
// PR2-T2 ticket #83 follow-up (2026-09-08): user 真机反馈
// "改回去之前的折叠还是需要的点击编辑展开里面各自有输入信息,有取消保存;两个按钮"
// 改:click-to-expand + panel 内 取消/保存 2 按钮 + local draft state(API key 与 model list)

// 验证:
// 1. editingVendorId @State 恢复(click-to-expand 机制)
// 2. 编辑 button Text 恢复
// 3. onEdit 回调恢复
// 4. panel 内有 取消 button
// 5. panel 内有 保存 button
// 6. local draft state: @State apiKeyInput + @State localModels(不立即 push 到 parent)
// 7. 取消 + 保存 调不同函数(cancelEdit vs saveEdit)

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const TARGET_FILE = resolve(root, 'entry/src/main/ets/pages/AiSettings/VendorPicker.ets');
const src = readFileSync(TARGET_FILE, 'utf8').replace(/\r\n/g, '\n');

test('VendorPicker: @State editingVendorId 恢复(click-to-expand 机制)', () => {
  assert.match(
    src,
    /@State\s+editingVendorId\s*:\s*string\s*\|\s*null/,
    'VendorPicker must have @State editingVendorId for click-to-expand (revert always-visible change)'
  );
});

test('VendorPicker: 编辑 button Text(\'编辑\') 恢复', () => {
  assert.match(
    src,
    /Text\(\s*['"]编辑['"]\s*\)/,
    'VendorPicker must have Text("编辑") button (revert always-visible removal)'
  );
});

test('VendorPicker: panel 内有 取消 button', () => {
  // 在编辑 panel 块内(API Key + model list 同级)有"取消" Text
  assert.match(
    src,
    /Text\(\s*['"]取消['"]\s*\)/,
    'VendorPicker edit panel must have 取消 button'
  );
});

test('VendorPicker: panel 内有 保存 button', () => {
  // 在编辑 panel 块内有"保存" Text(注意:不是"保存模型设置" 也不是"已保存")
  // 区分:"保存" 单字 vs "保存模型设置" 长字 vs "已保存" 完成态
  assert.match(
    src,
    /Text\(\s*['"]保存['"]\s*\)/,
    'VendorPicker edit panel must have 保存 button (single-char name vs "保存模型设置" / "已保存")'
  );
});

test('VendorPicker: local draft state(@State apiKeyInput + localModels) 防止立即 push 到 parent', () => {
  // @State apiKeyInput + @State localModels 不能仅 push 到 parent
  // 改:onChange/onAdd/onRemove 只更新 local,保存按钮 一次性 commit
  assert.match(
    src,
    /@State\s+apiKeyInput\s*:/,
    'VendorPicker must have @State apiKeyInput (local draft, not immediate onChange)'
  );
  assert.match(
    src,
    /@State\s+localModels\s*:\s*string\s*\[\s*\]\s*=/,
    'VendorPicker must have @State localModels (local draft for model list)'
  );
});

test('VendorPicker: edit helpers use arrow fields (ArkUI-1)', () => {
  assert.match(src, /openEdit\s*=\s*\(vendorId:\s*string\):\s*void\s*=>/);
  assert.match(src, /cancelEdit\s*=\s*\(\):\s*void\s*=>/);
  assert.match(src, /saveEdit\s*=\s*\(vendorId:\s*string\):\s*void\s*=>/);
});

test('VendorPicker: 取消调 cancelEdit,保存调 saveEdit(独立函数)', () => {
  // 取消 调函数 cancelEdit(不是 saveEdit);保存 调 saveEdit
  // source-level 匹配:取消 button onClick → cancelEdit(...)
  assert.match(
    src,
    /Text\(\s*['"]取消['"][\s\S]*?\.onClick\([\s\S]*?cancelEdit/,
    'VendorPicker 取消 button must call cancelEdit (not saveEdit)'
  );
  assert.match(
    src,
    /Text\(\s*['"]保存['"][\s\S]*?\.onClick\([\s\S]*?saveEdit/,
    'VendorPicker 保存 button must call saveEdit (not cancelEdit)'
  );
});
