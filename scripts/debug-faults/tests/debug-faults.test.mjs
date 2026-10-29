// scripts/debug-faults/tests/debug-faults.test.mjs
// #224 真机确定性复现 — 源码结构断言
// 覆盖: 故障档位取值/持久化、ReplyService 注入点与日志、AI 设置页隐藏入口与三个 chip。

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8').replace(/\r\n/g, '\n');

const faults = read('entry/src/main/ets/services/DebugFaults.ets');
const reply = read('entry/src/main/ets/services/ReplyService.ets');
const page = read('entry/src/main/ets/pages/AiSettings/AiSettingsPage.ets');

test('DebugFaults: 三种取值 + set/load/current + preferences 持久化', () => {
  assert.match(faults, /export type DebugFault = 'none' \| 'empty' \| 'interrupted'/);
  assert.match(faults, /static async load\(/);
  assert.match(faults, /static async set\(/);
  assert.match(faults, /static current\(\): DebugFault/);
  assert.match(faults, /preferences\.getPreferences/);
  assert.match(faults, /await store\.put\(KEY_FAULT, next\)/);
});

test('ReplyService: 返回前注入 empty/interrupted 并打 [DebugFault] 日志', () => {
  assert.match(reply, /\[DebugFault\] injected=/);
  assert.match(reply, /fault === 'empty'/);
  assert.match(reply, /fault === 'interrupted'/);
  // empty: content 强制置空且 interrupted:false
  assert.match(reply, /content: '',\s*\n\s*interrupted: false/);
  // interrupted: content 保留且 interrupted:true
  assert.match(reply, /content: result\.content,\s*\n\s*interrupted: true/);
  // 注入发生在 stream() 最终返回前
  assert.match(reply, /return this\.applyDebugFault\(success\)/);
});

test('AiSettingsPage: 隐藏入口连点 5 次 + 调试行三 chip', () => {
  assert.match(page, /调试：流式故障注入/);
  assert.match(page, /titleTapCount < 5/);
  assert.match(page, /debugChip\('正常', 'none'\)/);
  assert.match(page, /debugChip\('空流', 'empty'\)/);
  assert.match(page, /debugChip\('中断', 'interrupted'\)/);
  assert.match(page, /DebugFaults\.set\(value\)/);
  assert.match(page, /DebugFaults\.load\(getContext\(this\)\)/);
});
