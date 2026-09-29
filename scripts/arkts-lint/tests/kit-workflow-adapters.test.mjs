import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

const backgroundPath = resolve(root, 'entry/src/main/ets/kit/BackgroundTaskFacadeImpl.ets');
const formPath = resolve(root, 'entry/src/main/ets/kit/FormCardFacadeImpl.ets');
const storePath = resolve(root, 'common/src/main/ets/kit/CardSnapshotStore.ets');

test('BackgroundTaskFacade uses the real transient task API and owns cancellation', () => {
  assert.ok(existsSync(backgroundPath));
  const source = read('entry/src/main/ets/kit/BackgroundTaskFacadeImpl.ets');
  assert.match(source, /implements BackgroundTaskFacade/);
  assert.match(source, /backgroundTaskManager\.requestSuspendDelay/);
  assert.match(source, /backgroundTaskManager\.cancelSuspendDelay/);
  assert.match(source, /Map<BackgroundTaskTag, number>/);
});

test('FormCardFacade persists one snapshot source and updates real running forms', () => {
  assert.ok(existsSync(formPath));
  assert.ok(existsSync(storePath));
  const source = read('entry/src/main/ets/kit/FormCardFacadeImpl.ets');
  const store = read('common/src/main/ets/kit/CardSnapshotStore.ets');
  assert.match(source, /implements FormCardFacade/);
  assert.match(source, /CardSnapshotStore\.save/);
  assert.match(source, /formProvider\.getPublishedRunningFormInfos/);
  assert.match(source, /formProvider\.updateForm/);
  assert.match(store, /StorageType\.GSKV/);
  assert.match(store, /load\(context: Context\): CardSnapshot/);
});

test('EntryAbility injects all three Kit facade implementations', () => {
  const source = read('entry/src/main/ets/entryability/EntryAbility.ets');
  assert.match(source, /new ReminderFacadeImpl/);
  assert.match(source, /new BackgroundTaskFacadeImpl/);
  assert.match(source, /new FormCardFacadeImpl/);
  assert.match(source, /requestOneShot\('review_sync'\)/);
  assert.match(source, /CardSnapshotService\.refresh\(this\.context\)/);
  assert.match(source, /facade\.finish\('review_sync'\)/);
});

test('FormAbility reads the shared snapshot and removes fixed mock data', () => {
  const source = read('cardservice/src/main/ets/formability/FormAbility.ets');
  assert.match(source, /CardSnapshotStore\.load\(this\.context\)/);
  assert.match(source, /private loadSnapshot\(\): CardSnapshot/);
  assert.match(source, /this\.loadSnapshot\(\)/);
  assert.match(source, /formProvider\.updateForm/);
  assert.doesNotMatch(source, /todayCount:\s*5/);
  assert.doesNotMatch(source, /totalCount:\s*12/);
});

test('cardservice declares its FormExtensionAbility and only depends on common', () => {
  const moduleConfig = read('cardservice/src/main/module.json5');
  const packageConfig = read('cardservice/oh-package.json5');
  assert.match(moduleConfig, /"extensionAbilities"/);
  assert.match(moduleConfig, /"type":\s*"form"/);
  assert.match(moduleConfig, /\$profile:form_config/);
  assert.doesNotMatch(packageConfig, /"agents"/);
});
