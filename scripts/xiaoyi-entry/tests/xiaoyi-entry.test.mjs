// scripts/xiaoyi-entry/tests/xiaoyi-entry.test.mjs
// issue #225: 应用内「问小艺」入口的结构测试。
// 只做源码级契约断言，不跑构建、不连真机；真机可用性由 AgentController.isAgentSupport 决定。

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const SECTION_FILE = resolve(root, 'entry/src/main/ets/pages/AiSettings/XiaoyiEntrySection.ets');
const SETTINGS_FILE = resolve(root, 'entry/src/main/ets/pages/AiSettings/AiSettingsPage.ets');

const sectionSrc = existsSync(SECTION_FILE)
  ? readFileSync(SECTION_FILE, 'utf8').replace(/\r\n/g, '\n')
  : '';
const settingsSrc = existsSync(SETTINGS_FILE)
  ? readFileSync(SETTINGS_FILE, 'utf8').replace(/\r\n/g, '\n')
  : '';

test('XiaoyiEntrySection.ets 存在', () => {
  assert.ok(existsSync(SECTION_FILE), `missing file: ${SECTION_FILE}`);
});

test('XiaoyiEntrySection 用 isAgentSupport( 做可用性探测', () => {
  assert.match(sectionSrc, /isAgentSupport\s*\(/, 'must call AgentController.isAgentSupport()');
});

test('XiaoyiEntrySection 渲染 FunctionComponent({', () => {
  assert.match(sectionSrc, /FunctionComponent\s*\(\s*\{/, 'must render FunctionComponent({ ... })');
});

test('XiaoyiEntrySection 使用平台生成的 AgentID（agent 前缀）', () => {
  assert.match(sectionSrc, /AGENT_ID[^=]*=\s*'agent[0-9a-f]{32}'/, 'AGENT_ID must be the platform-generated agent id');
});

test('XiaoyiEntrySection 说明文案：回答不会写入本地笔记', () => {
  assert.ok(
    sectionSrc.includes('回答不会写入本地笔记'),
    'must keep the copy: 对话在小艺侧完成，回答不会写入本地笔记'
  );
});

test('XiaoyiEntrySection 覆盖至少 3 个 AgentFrameworkKit 错误码', () => {
  const codes = ['1022400010', '1022400011', '1022400012', '1022400013', '1022400014'];
  const hit = codes.filter((code) => sectionSrc.includes(code));
  assert.ok(
    hit.length >= 3,
    `expected >= 3 error codes, got ${hit.length}: ${hit.join(', ')}`
  );
});

test('AiSettingsPage 在 OnDeviceModelSection 之后接入 XiaoyiEntrySection(', () => {
  assert.match(settingsSrc, /XiaoyiEntrySection\s*\(/, 'AiSettingsPage must render XiaoyiEntrySection()');
  const onDeviceIdx = settingsSrc.indexOf('OnDeviceModelSection({');
  const xiaoyiIdx = settingsSrc.indexOf('XiaoyiEntrySection(');
  assert.ok(onDeviceIdx >= 0, 'OnDeviceModelSection({) not found');
  assert.ok(
    xiaoyiIdx > onDeviceIdx,
    'XiaoyiEntrySection() must be placed after OnDeviceModelSection({...})'
  );
});
