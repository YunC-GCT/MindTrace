import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const reminder = readFileSync(resolve(root, 'common/src/main/ets/kit/ReminderFacade.ets'), 'utf8');
const background = readFileSync(resolve(root, 'common/src/main/ets/kit/BackgroundTaskFacade.ets'), 'utf8');
const formCard = readFileSync(resolve(root, 'common/src/main/ets/kit/FormCardFacade.ets'), 'utf8');
const commonIndex = readFileSync(resolve(root, 'common/src/main/ets/Index.ets'), 'utf8');

// D4 spec 013: facade 契约文件只声明接口, 禁止 import @kit / @ohos 实现。
test('Kit facade files declare contracts without importing kit implementations', () => {
  for (const [name, text] of [['ReminderFacade', reminder], ['BackgroundTaskFacade', background], ['FormCardFacade', formCard]]) {
    assert.match(text, /export interface/, `${name} must export an interface`);
    assert.doesNotMatch(text, /^import .*@kit\.|^import .*@ohos\./m, `${name} must not import kit implementations`);
  }
});

test('ReminderFacade covers schedule and cancel semantics', () => {
  assert.match(reminder, /scheduleReviewReminder\(request: ReviewReminderRequest\): Promise<void>/);
  assert.match(reminder, /cancelByUnit\(unitId: string\): Promise<void>/);
  assert.match(reminder, /unitId: string/);
  assert.match(reminder, /fireAt: number/);
});

test('BackgroundTaskFacade covers one-shot request and pending check', () => {
  assert.match(background, /requestOneShot\(tag: BackgroundTaskTag\): Promise<boolean>/);
  assert.match(background, /hasPending\(tag: BackgroundTaskTag\): boolean/);
});

test('FormCardFacade covers snapshot push', () => {
  assert.match(formCard, /pushSnapshot\(snapshot: CardSnapshot\): Promise<void>/);
  assert.match(formCard, /todayReviewCount: number/);
  assert.match(formCard, /streakDays: number/);
});

test('common Index exports all D4 facade contracts', () => {
  assert.match(commonIndex, /from '\.\/kit\/ReminderFacade'/);
  assert.match(commonIndex, /from '\.\/kit\/BackgroundTaskFacade'/);
  assert.match(commonIndex, /from '\.\/kit\/FormCardFacade'/);
});
