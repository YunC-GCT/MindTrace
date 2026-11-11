// scripts/on-device-status/tests/on-device-section.test.mjs
// issue #221: 端侧能力位在设置页可观测
// 结构测试: 组件存在 / 状态行文案 / 未就绪禁用开关 / 设置页接入与探测调用

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const SECTION_FILE = resolve(root, 'entry/src/main/ets/pages/AiSettings/OnDeviceModelSection.ets');
const PAGE_FILE = resolve(root, 'entry/src/main/ets/pages/AiSettings/AiSettingsPage.ets');

const readNormalized = (file) => readFileSync(file, 'utf8').replace(/\r\n/g, '\n');

test('OnDeviceModelSection.ets 存在', () => {
  assert.ok(
    existsSync(SECTION_FILE),
    'entry/src/main/ets/pages/AiSettings/OnDeviceModelSection.ets must exist'
  );
});

test('组件展示「端侧模型：」状态行', () => {
  const section = readNormalized(SECTION_FILE);
  assert.match(section, /端侧模型：/, 'OnDeviceModelSection must render the 端侧模型： status line');
});

test('端侧模型未就绪时禁用开关', () => {
  const section = readNormalized(SECTION_FILE);
  // available 为 false 时禁用开关: 用 .enabled(this.available) 表达,或直接传 false
  assert.match(
    section,
    /\.enabled\(\s*(?:this\.available|false)\s*\)/,
    'OnDeviceModelSection must disable the switch when the on-device model is unavailable'
  );
  assert.match(
    section,
    /端侧模型未就绪，暂不可开启/,
    'OnDeviceModelSection must explain why the switch cannot be enabled'
  );
});

test('AiSettingsPage 接入 OnDeviceModelSection', () => {
  const page = readNormalized(PAGE_FILE);
  assert.match(
    page,
    /OnDeviceModelSection\s*\(/,
    'AiSettingsPage must mount OnDeviceModelSection'
  );
});

test('AiSettingsPage 调用 checkAvailability() 探测端侧能力位', () => {
  const page = readNormalized(PAGE_FILE);
  assert.match(
    page,
    /checkAvailability\s*\(/,
    'AiSettingsPage must call OnDeviceLlm.checkAvailability() to read the on-device capability bit'
  );
});
