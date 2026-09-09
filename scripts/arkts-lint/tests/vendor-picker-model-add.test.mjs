// scripts/arkts-lint/tests/vendor-picker-model-add.test.mjs
// VendorPicker edit panel 模型添加 UX bug (2026-09-08)
// 报告:点击 编辑 → 输入模型并回车 — 无反应
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
  // 整体 source-level 匹配(避免 body extraction 嵌套 if 失败)
  assert.match(
    src,
    /placeholder:\s*['"]输入模型['"][\s\S]*?\.onSubmit\s*\(\s*\(\s*\)\s*:\s*void\s*=>\s*\{[\s\S]*?this\.localModels/,
    'VendorPicker 模型 input 必须有 .onSubmit handler 写入 localModels draft'
  );
});

test('VendorPicker: 模型 input 使用短文案和 F_XS 占位字体避免截断', () => {
  assert.match(src, /placeholder:\s*['"]输入模型['"]/);
  assert.match(src, /placeholderFont\(\{\s*size:\s*F_XS\s*\}\)/);
  assert.doesNotMatch(src, /输入模型名后回车/);
});

test('VendorPicker: onSubmit 用 trim 后局部 m 写 localModels draft', () => {
  assert.match(
    src,
    /onSubmit[\s\S]*?const\s+m\s*:\s*string\s*=\s*this\.newModelInput\.trim\(\)[\s\S]*?this\.localModels\s*=\s*\[\.\.\.this\.localModels,\s*m\]/,
    'VendorPicker onSubmit must add trimmed m to localModels draft'
  );
});

test('VendorPicker: 保存时也提交输入框中尚未点加号的模型', () => {
  assert.match(
    src,
    /saveEdit[\s\S]*?const\s+pendingModel\s*:\s*string\s*=\s*this\.newModelInput\.trim\(\)[\s\S]*?this\.localModels\s*=\s*\[\.\.\.this\.localModels,\s*pendingModel\]/,
    'VendorPicker saveEdit must include pending model input before persisting'
  );
});

test('VendorPicker: 保存模型后保持编辑面板展开以显示新模型', () => {
  const saveBody = src.match(/saveEdit\s*=\s*\(vendorId:\s*string\):\s*void\s*=>\s*\{([\s\S]*?)\n\s*\}\n\s*build\(\)/);
  assert.ok(saveBody !== null, 'saveEdit body must be found');
  assert.doesNotMatch(saveBody[1], /this\.editingVendorId\s*=\s*null/, 'saveEdit must not collapse the panel immediately');
  assert.doesNotMatch(saveBody[1], /this\.localModels\s*=\s*\[\]/, 'saveEdit must not clear visible local model list immediately');
});

test('ViewModel: 保存空模型列表时会移除已持久化模型', () => {
  const vmSource = readFileSync(resolve(root, 'entry/src/main/ets/viewmodels/AiSettingsViewModel.ets'), 'utf8').replace(/\r\n/g, '\n');
  const saveBody = vmSource.match(/async\s+saveLlm\s*\(\):\s*Promise<boolean>\s*\{([\s\S]*?)\n\s*\}\n\s*async\s+saveOcr/);
  assert.ok(saveBody !== null, 'saveLlm body must be found');
  assert.doesNotMatch(saveBody[1], /if\s*\(ours\.length\s*>\s*0\)/, 'saveLlm must reconcile empty model lists too');
  assert.match(saveBody[1], /for\s*\(const\s+m\s+of\s+existing\)[\s\S]*?llm\.removeVendorModel\(vid,\s*m\)/, 'saveLlm must remove persisted models missing from current list');
});
