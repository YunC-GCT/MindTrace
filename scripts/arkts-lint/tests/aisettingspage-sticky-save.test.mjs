// scripts/arkts-lint/tests/aisettingspage-sticky-save.test.mjs
// PR2-T2 ticket #83 follow-up (2026-09-08): user 真机测试发现
// AI 设置页太长 + edit panel 展开后保存按钮在 Scroll 底部,用户看不到
// 修法:ActionBar 移出 Scroll,放 Column 底部(.layoutWeight(1) 让 Scroll 占据剩余空间)

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const TARGET_FILE = resolve(root, 'entry/src/main/ets/pages/AiSettings/AiSettingsPage.ets');
const src = readFileSync(TARGET_FILE, 'utf8').replace(/\r\n/g, '\n');

test('AISettingsPage: ActionBar 移出 Scroll (在 build() 顶层,save 按钮永远可见)', () => {
  // source-level pattern: Scroll() {...} 关闭后才 ActionBar(在 Scroll 外,可能中间有 .layoutWeight + comment)
  // pattern: Scroll() { ... } [any content] ActionBar
  assert.match(
    src,
    /Scroll\s*\(\s*\)\s*\{[\s\S]*?\}[\s\S]*?ActionBar\s*\(\s*\{/,
    'AISettingsPage build() must have ActionBar() AFTER Scroll(){} closing (not inside Scroll)'
  );
});

test('AISettingsPage: Scroll 内容 .layoutWeight(1) 占据剩余空间(给 ActionBar 让位)', () => {
  // Scroll 后跟 .layoutWeight(1) 占据 Column 剩余空间
  // pattern: Scroll\s*\(\s*\)\s*\{[\s\S]*?\}\s*\.layoutWeight\s*\(\s*1\s*\)
  assert.match(
    src,
    /Scroll\s*\(\s*\)\s*\{[\s\S]*?\}\s*\.layoutWeight\s*\(\s*1\s*\)/,
    'AISettingsPage Scroll must have .layoutWeight(1) so ActionBar stays visible at bottom'
  );
});
