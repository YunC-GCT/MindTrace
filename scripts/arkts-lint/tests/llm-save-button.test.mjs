// scripts/arkts-lint/tests/llm-save-button.test.mjs
// PR2-T2 ticket #83 follow-up (2026-09-08): user 反馈"我这里无法保存这些密钥信息"
// 修法:AiSettingsPage 在 LLM section(服务厂商 段)后加专用 "保存模型设置" 按钮
// 显式标示 LLM section 的 save entry point,不依赖底部 ActionBar

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const TARGET_FILE = resolve(root, 'entry/src/main/ets/pages/AiSettings/AiSettingsPage.ets');
const src = readFileSync(TARGET_FILE, 'utf8').replace(/\r\n/g, '\n');

test('LLM save: AiSettingsPage 含 "保存模型设置" 按钮(明示 LLM save 入口)', () => {
  // 找 "保存模型设置" 字符串
  assert.match(
    src,
    /['"]保存模型设置['"]/,
    'AiSettingsPage must have "保存模型设置" button (明示 LLM section save 入口)'
  );
});

test('LLM save: 保存模型设置 按钮调 vm.save() 而非 this.save()(局部 LLM save)', () => {
  // 按钮 onClick 必须调 vm.save()(只保存 LLM,不保存 OCR)
  assert.match(
    src,
    /保存模型设置[\s\S]*?\.onClick\(\s*\(\s*\)\s*:\s*void\s*=>\s*\{[\s\S]*?vm\.save\s*\(/,
    '"保存模型设置" button onClick must call vm.save() (LLM-only save, not this.save() which also touches OCR)'
  );
});

test('LLM save: 按钮位置在 VendorPicker 之后,OCR 之前(LLM section 内)', () => {
  // source-level 顺序:VendorPicker 出现后,"保存模型设置" 出现,OcrConfigSection 出现
  const vendorPickerIdx = src.indexOf('VendorPicker({')
  const llmSaveIdx = src.indexOf('保存模型设置')
  const ocrIdx = src.indexOf('OcrConfigSection({')
  assert.ok(vendorPickerIdx > 0, 'VendorPicker must exist');
  assert.ok(llmSaveIdx > 0, '保存模型设置 button must exist');
  assert.ok(ocrIdx > 0, 'OcrConfigSection must exist');
  assert.ok(
    vendorPickerIdx < llmSaveIdx && llmSaveIdx < ocrIdx,
    '保存模型设置 button must be BETWEEN VendorPicker and OcrConfigSection (in LLM section)'
  );
});
