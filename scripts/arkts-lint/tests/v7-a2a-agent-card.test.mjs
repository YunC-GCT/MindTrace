// 路径: scripts/arkts-lint/tests/v7-a2a-agent-card.test.mjs
// 职责: AgentCard 图片输入声明守卫（平台反馈：image/* 通配符不被识别、skill inputModes 会覆盖默认值）。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');
const cardPath = 'entry/src/main/resources/base/profile/agent_config.json';

test('AgentCard defaultInputModes 只用具体 MIME，不用 image/* 通配符', () => {
  const data = JSON.parse(read(cardPath));
  const card = data.agentCards[0];
  assert.ok(Array.isArray(card.defaultInputModes));
  assert.equal(card.defaultInputModes.includes('image/*'), false);
  for (const mode of ['text/plain', 'image/jpeg', 'image/png']) {
    assert.ok(card.defaultInputModes.includes(mode), 'defaultInputModes 应含 ' + mode);
  }
  for (const mode of card.defaultInputModes) {
    assert.match(mode, /^[a-z]+\/[a-z0-9.+-]+$/);
    assert.ok(mode.length <= 32, '单个 inputMode 不能超过 32 字节');
  }
});

test('AgentCard skill 不覆盖 inputModes；appInfo 三字段齐全', () => {
  const card = JSON.parse(read(cardPath)).agentCards[0];
  assert.ok(Array.isArray(card.skills) && card.skills.length > 0);
  for (const skill of card.skills) {
    assert.equal(Object.prototype.hasOwnProperty.call(skill, 'inputModes'), false,
      'skill 级 inputModes 会覆盖默认值，应删除');
  }
  assert.equal(card.appInfo.bundleName, 'com.example.mindtrace');
  assert.equal(card.appInfo.moduleName, 'entry');
  assert.equal(card.appInfo.abilityName, 'AgentExtAbility');
});

test('module.json5 的 agent 扩展 metadata 指向 agent_config', () => {
  const module = read('entry/src/main/module.json5');
  assert.match(module, /"type": "agent"/);
  assert.match(module, /\$profile:agent_config/);
});
