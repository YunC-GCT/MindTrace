import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const page = readFileSync(resolve(root, 'entry/src/main/ets/pages/AiSettings/AiSettingsPage.ets'), 'utf8');
const vm = readFileSync(resolve(root, 'entry/src/main/ets/viewmodels/AiSettingsViewModel.ets'), 'utf8');
const bar = readFileSync(resolve(root, 'entry/src/main/ets/pages/AiSettings/ActionBar.ets'), 'utf8');

test('per-vendor 保存回调调用 LLM-only saveLlm', () => {
  assert.match(page, /onSaveEdit:[\s\S]*?this\.saveLlm\(\)/);
  assert.match(page, /private\s+saveLlm\s*=\s*\(\):\s*void/);
  assert.match(vm, /async\s+saveLlm\s*\(\):\s*Promise<boolean>/);
});

test('底部 ActionBar 仅保存和重置 OCR', () => {
  assert.match(page, /ActionBar\(\{\s*onReset:[\s\S]*?this\.resetOcr\(\)[\s\S]*?onSave:[\s\S]*?this\.saveOcr\(\)/);
  assert.match(bar, /Button\("重置 OCR"\)/);
  assert.match(bar, /Button\("保存 OCR"\)/);
  assert.doesNotMatch(page, /保存模型设置/);
});

test('连接测试读取当前 vendor 的 API key', () => {
  assert.match(vm, /getApiKey\(this\.vendorId\)/);
  assert.doesNotMatch(vm, /async\s+test[\s\S]*?await\s+llm\.setApiKey\(key\)/);
});
