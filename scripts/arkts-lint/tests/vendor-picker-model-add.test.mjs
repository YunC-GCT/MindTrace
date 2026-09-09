// scripts/arkts-lint/tests/vendor-picker-model-add.test.mjs
// VendorPicker edit panel 模型添加 UX bug (2026-09-08)
// 报告:点击 编辑 → 输入模型名后回车 — 无反应(placeholder 说"输入模型名后回车"但无 .onSubmit handler)
// 影响:default 厂商 + 自定义厂商都中(都用同一 edit panel)

// PR2-T2 ticket #83 follow-up(2026-09-08):user 真机测试发现
// 修法:TextInput 新增 .onSubmit(() => { same as + click }) handler

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const TARGET_FILE = resolve(root, 'entry/src/main/ets/pages/AiSettings/VendorPicker.ets');
const src = readFileSync(TARGET_FILE, 'utf8').replace(/\r\n/g, '\n');

test('VendorPicker: 模型 input 含 onSubmit handler(回车触发添加)', () => {
  // 找 "输入模型名后回车" 的 TextInput,必须有 .onSubmit 紧随其后
  // 整体 source-level 匹配(避免 body extraction 嵌套 if 失败)
  assert.match(
    src,
    /placeholder:\s*['"]输入模型名后回车['"][\s\S]*?\.onSubmit\s*\(\s*\(\s*\)\s*:\s*void\s*=>\s*\{[\s\S]*?this\.onAddModel/,
    'VendorPicker 模型 input 必须有 .onSubmit handler 调用 this.onAddModel(placeholder 说"回车"但之前没 handler — UX bug)'
  );
});

test('VendorPicker: onSubmit 调 onAddModel 用 item.id + 局部 m(trim 后)', () => {
  // onSubmit 内:trim newModelInput → 局部 m → onAddModel(item.id, m)(与 + click handler 一致)
  assert.match(
    src,
    /onSubmit[\s\S]*?const\s+m\s*:\s*string\s*=\s*this\.newModelInput\.trim\(\)[\s\S]*?this\.onAddModel\s*\(\s*item\.id\s*,\s*m\s*\)/,
    'VendorPicker onSubmit must call onAddModel(item.id, m) where m = this.newModelInput.trim() (consistent with + click handler)'
  );
});
