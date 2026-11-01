// 路径: scripts/arkts-lint/tests/v7-write-job-persist.test.mjs
// 职责: spec 040 P1 —— WriteJobScheduler 持久化 hooks（enqueue→claim→run→finish）、恢复路径、flag 默认关。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');
const mod = loadNoteReviewEtsModule('entry/src/main/ets/services/WriteJobScheduler.ets');
const { WriteJobScheduler } = mod;

function fakeHooks(overrides = {}) {
  const calls = [];
  const hooks = {
    calls,
    async enqueue(priority, text) {
      calls.push('enqueue:' + priority);
      return 'job-persisted-1';
    },
    async claim(jobId) {
      calls.push('claim:' + jobId);
      return true;
    },
    async finish(jobId, status, error) {
      calls.push('finish:' + status);
    },
    ...overrides,
  };
  return hooks;
}

test('P1 hooks：enqueue → claim → run → finish(done) 顺序，jobId 用持久 id', async () => {
  const hooks = fakeHooks();
  const scheduler = new WriteJobScheduler({ interactiveConcurrency: 1, backgroundConcurrency: 1, log: () => {} });
  scheduler.setPersistenceHooks(hooks);
  let ranJobId = '';
  const value = await scheduler.submit('interactive', 'persist-text', async () => {
    hooks.calls.push('run');
    return 'ok';
  });
  assert.equal(value, 'ok');
  const enqueueIndex = hooks.calls.indexOf('enqueue:interactive');
  const claimIndex = hooks.calls.indexOf('claim:job-persisted-1');
  const runIndex = hooks.calls.indexOf('run');
  const finishIndex = hooks.calls.indexOf('finish:done');
  assert.ok(enqueueIndex >= 0 && claimIndex > enqueueIndex && runIndex > claimIndex && finishIndex > runIndex,
    '顺序应为 enqueue → claim → run → finish: ' + hooks.calls.join(','));
});

test('P1 hooks：claim 失败 → 拒绝且不执行 executor、不回写 finish', async () => {
  const hooks = fakeHooks({ claim: async () => false });
  const scheduler = new WriteJobScheduler({ interactiveConcurrency: 1, backgroundConcurrency: 1, log: () => {} });
  scheduler.setPersistenceHooks(hooks);
  let ran = false;
  await assert.rejects(
    () => scheduler.submit('interactive', 'x', async () => { ran = true; return 'ok'; }),
    /JOB_CLAIMED_ELSEWHERE/,
  );
  assert.equal(ran, false);
  assert.equal(hooks.calls.includes('finish:failed'), false);
});

test('P1 hooks：executor 失败 → finish(failed) + 调用方 reject', async () => {
  const hooks = fakeHooks();
  const scheduler = new WriteJobScheduler({ interactiveConcurrency: 1, backgroundConcurrency: 1, log: () => {} });
  scheduler.setPersistenceHooks(hooks);
  await assert.rejects(
    () => scheduler.submit('interactive', 'x', async () => { throw new Error('run-boom'); }),
    /run-boom/,
  );
  assert.ok(hooks.calls.includes('finish:failed'));
});

test('P1 hooks：enqueue 失败 → 拒绝，不进入内存队列', async () => {
  const hooks = fakeHooks({ enqueue: async () => { throw new Error('enqueue-boom'); } });
  const scheduler = new WriteJobScheduler({ interactiveConcurrency: 1, backgroundConcurrency: 1, log: () => {} });
  scheduler.setPersistenceHooks(hooks);
  await assert.rejects(
    () => scheduler.submit('interactive', 'x', async () => 'ok'),
    /enqueue-boom/,
  );
  assert.equal(scheduler.stats().queueDepth, 0);
});

test('P1 恢复路径 submitRecovered：不重复 enqueue，仍 claim + run + finish', async () => {
  const hooks = fakeHooks();
  const scheduler = new WriteJobScheduler({ interactiveConcurrency: 1, backgroundConcurrency: 1, log: () => {} });
  scheduler.setPersistenceHooks(hooks);
  scheduler.submitRecovered('recovered-1', 'background', 'recovered-text', async () => 'ok');
  await new Promise((resolveDone) => setTimeout(resolveDone, 60));
  assert.equal(hooks.calls.includes('enqueue:background'), false, '恢复路径不应再次 enqueue');
  assert.ok(hooks.calls.includes('claim:recovered-1'));
  assert.ok(hooks.calls.includes('finish:done'));
});

test('P1 接线：flag 默认关、bootstrap 注册 hooks 并恢复、EntryAbility DB 后调用', () => {
  const config = read('entry/src/main/ets/services/WriteJobConfig.ets');
  assert.ok(config.includes('WRITE_JOB_PERSIST_ENABLED: boolean = false'));
  const bootstrap = read('entry/src/main/ets/services/WriteJobBootstrap.ets');
  assert.ok(bootstrap.includes('WRITE_JOB_PERSIST_ENABLED'));
  assert.ok(bootstrap.includes('setPersistenceHooks'));
  assert.ok(bootstrap.includes('persistence.recover()'));
  assert.ok(bootstrap.includes('submitRecovered'));
  assert.ok(bootstrap.includes('ingestSingleTextDirect'));
  const persistence = read('entry/src/main/ets/services/WriteJobPersistence.ets');
  assert.ok(persistence.includes('sourceFingerprint(normalizeForDedupe(text))'));
  assert.ok(persistence.includes('claimJob(jobId, LEASE_OWNER, LEASE_MS)'));
  assert.ok(persistence.includes('markDone(jobId)'));
  assert.ok(persistence.includes('markFailed(jobId, error)'));
  const entry = read('entry/src/main/ets/entryability/EntryAbility.ets');
  assert.ok(entry.includes('WriteJobBootstrap.install(this.context)'));
  const dao = read('entry/src/main/ets/database/AgentJobDao.ets');
  assert.ok(dao.includes('async claimJob('));
});
