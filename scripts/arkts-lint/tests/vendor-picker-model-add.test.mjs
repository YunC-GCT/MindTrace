// scripts/arkts-lint/tests/vendor-picker-model-add.test.mjs
// VendorPicker edit panel 模型添加 UX bug (2026-09-08)
// 报告:点击 编辑 → 输入模型名后回车 — 无反应(placeholder 说"输入模型名后回车"但无 .onSubmit handler)
// 影响:default 厂商 + 自定义厂商都中(都用同一 edit panel)

// PR2-T2 ticket #83 follow-up(2026-09-08):user 真机测试发现
// 修法:TextInput 新增 .onSubmit(() => { same as + click }) handler,写 localModels draft

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
    /placeholder:\s*['"]输入模型名后回车['"][\s\S]*?\.onSubmit\s*\(\s*\(\s*\)\s*:\s*void\s*=>\s*\{[\s\S]*?this\.localModels/,
    'VendorPicker 模型 input 必须有 .onSubmit handler 写入 localModels draft'
  );
});

test('VendorPicker: onSubmit 用 trim 后局部 m 写 localModels draft', () => {
  assert.match(
    src,
    /onSubmit[\s\S]*?const\s+m\s*:\s*string\s*=\s*this\.newModelInput\.trim\(\)[\s\S]*?this\.localModels\s*=\s*\[\.\.\.this\.localModels,\s*m\]/,
    'VendorPicker onSubmit must add trimmed m to localModels draft'
  );
});
