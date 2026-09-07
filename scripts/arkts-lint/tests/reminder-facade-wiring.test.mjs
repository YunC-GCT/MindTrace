import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');

const impl = read('entry/src/main/ets/kit/ReminderFacadeImpl.ets');
const ability = read('entry/src/main/ets/entryability/EntryAbility.ets');
const topBar = read('entry/src/main/ets/pages/Home/HomeTopBar.ets');
const home = read('entry/src/main/ets/pages/Home/HomePage.ets');
const moduleJson = read('entry/src/main/module.json5');

// F3 (spec 013 / ADR-0009 / 复赛冲刺序 2): ReminderFacade 实现落地 entry + 组合根注入。
// UI 入口按用户裁决 (2026-09-06) 暂不挂 — 消费方接入属后续 UI 需求。
test('ReminderFacadeImpl implements the common contract with @kit.BackgroundTasksKit', () => {
  assert.match(impl, /import \{ reminderAgentManager \} from '@kit\.BackgroundTasksKit';/);
  assert.match(impl, /import type \{ ReminderFacade, ReviewReminderRequest \} from 'common';|import \{ ReminderFacade/);
  assert.match(impl, /export class ReminderFacadeImpl implements ReminderFacade/);
  assert.match(impl, /async scheduleReviewReminder\(request: ReviewReminderRequest\): Promise<void>/);
  assert.match(impl, /async cancelByUnit\(unitId: string\): Promise<void>/);
  assert.match(impl, /publishReminder/, 'must call the real reminder API');
  assert.match(impl, /cancelReminder/, 'dedup/cancel must be wired');
});

test('EntryAbility is the composition root and injects the facade', () => {
  assert.match(ability, /new ReminderFacadeImpl\(this\.context\)/);
  assert.match(ability, /AppStorage\.setOrCreate.*reminderFacade/);
});

test('UI stays untouched per user ruling (2026-09-06): no Home entry wired', () => {
  assert.doesNotMatch(topBar, /onSetReminder/, 'HomeTopBar must stay original');
  assert.doesNotMatch(home, /scheduleReviewReminder|getReminderFacade/, 'HomePage must not consume the facade yet');
});

test('agent reminder permission is declared', () => {
  assert.match(moduleJson, /ohos\.permission\.PUBLISH_AGENT_REMINDER/);
});
