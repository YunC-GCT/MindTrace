// #238 / §17.5：StudyPlanWritePort 契约测试（待办语义，ADR-0022）+ schema v17 源码守护。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const root = resolve(import.meta.dirname, '../../..');
const db = readFileSync(resolve(root, 'common/src/main/ets/DatabaseHelper.ets'), 'utf8');

class StudyPlanError extends Error {
  constructor(code, message, retryable) {
    super(message);
    this.name = 'StudyPlanError';
    this.code = code;
    this.retryable = retryable;
  }
}

const adapterModule = loadNoteReviewEtsModule(
  'entry/src/main/ets/database/StudyPlanWritePortAdapter.ets',
  {
    mocks: {
      common: {
        StudyPlanError,
        STUDY_PLAN_ERROR_READ_FAILED: 'STUDY_PLAN_READ_FAILED',
        STUDY_PLAN_ERROR_OPERATION_REQUIRED: 'OPERATION_ID_REQUIRED',
        STUDY_PLAN_ERROR_INVALID_PLAN: 'INVALID_STUDY_PLAN',
        STUDY_PLAN_ERROR_NOT_FOUND: 'STUDY_PLAN_NOT_FOUND',
        STUDY_PLAN_ERROR_VERSION_CONFLICT: 'VERSION_CONFLICT',
        STUDY_PLAN_ERROR_WRITE_FAILED: 'STUDY_PLAN_WRITE_FAILED',
      },
    },
  },
);
const StudyPlanWritePortAdapter = adapterModule.StudyPlanWritePortAdapter;

function plan(overrides = {}) {
  return {
    id: 'plan-1',
    title: '复习极限',
    isDone: false,
    priority: 2,
    linkedNoteId: 'note-1',
    createdAt: 1,
    dueDate: 0,
    ...overrides,
  };
}

function makeStore() {
  const records = new Map();
  const operations = new Map();
  const calls = { insert: 0, update: 0, setDone: 0 };
  let failMode = null;
  const store = {
    calls,
    failWith(mode) { failMode = mode; },
    async queryOperation(operationId) {
      if (failMode === 'query') { throw new Error('db down'); }
      return operations.get(operationId) ?? null;
    },
    async queryRecord(id) {
      if (failMode === 'query') { throw new Error('db down'); }
      return records.get(id) ?? null;
    },
    async insertRecord(item, command) {
      calls.insert += 1;
      const record = { ...item, id: item.id.length > 0 ? item.id : 'plan-new', version: 1 };
      records.set(record.id, record);
      operations.set(command.operationId, {
        operationId: command.operationId, planId: record.id, kind: 'create', version: 1, committedAt: 1,
      });
      return record;
    },
    async updateRecord(item, command) {
      calls.update += 1;
      const current = records.get(item.id);
      const record = { ...current, ...item, version: current.version + 1 };
      records.set(record.id, record);
      operations.set(command.operationId, {
        operationId: command.operationId, planId: record.id, kind: 'update', version: record.version, committedAt: 1,
      });
      return record;
    },
    async setDone(id, done, command) {
      calls.setDone += 1;
      const current = records.get(id);
      const record = { ...current, isDone: done, version: current.version + 1 };
      records.set(id, record);
      operations.set(command.operationId, {
        operationId: command.operationId, planId: id, kind: 'complete', version: record.version, committedAt: 1,
      });
      return record;
    },
  };
  return store;
}

test('schema v17 adds a version column and the study_plan_op table', () => {
  const version = Number(db.match(/DB_SCHEMA_VERSION: number = (\d+)/)[1]);
  assert.ok(version >= 17, 'study plan write port requires schema >= 17');
  assert.match(db, /ALTER TABLE study_plan ADD COLUMN version INTEGER NOT NULL DEFAULT 1/);
  assert.match(db, /CREATE TABLE IF NOT EXISTS study_plan_op/);
  assert.match(db, /SQL_CREATE_STUDY_PLAN_OP,/);
  assert.match(db, /SQL_INDEX_STUDY_PLAN_OP_PLAN,/);
});

test('StudyPlanWrite.create stores the todo and reports version 1', async () => {
  const store = makeStore();
  const port = new StudyPlanWritePortAdapter(store);
  const outcome = await port.create(plan(), { operationId: 'op-1' });
  assert.equal(outcome.id, 'plan-1');
  assert.equal(outcome.version, 1);
  assert.equal(outcome.duplicate, false);
  assert.equal(store.calls.insert, 1);
});

test('StudyPlanWrite requires operationId and a non-empty title', async () => {
  const port = new StudyPlanWritePortAdapter(makeStore());
  await assert.rejects(port.create(plan(), { operationId: '  ' }), (error) => {
    assert.equal(error.code, 'OPERATION_ID_REQUIRED');
    assert.equal(error.retryable, false);
    return true;
  });
  await assert.rejects(port.create(plan({ title: ' ' }), { operationId: 'op-2' }), (error) => {
    assert.equal(error.code, 'INVALID_STUDY_PLAN');
    return true;
  });
});

test('StudyPlanWrite replays the same operationId without a second write', async () => {
  const store = makeStore();
  const port = new StudyPlanWritePortAdapter(store);
  await port.create(plan(), { operationId: 'op-3' });
  const replay = await port.create(plan(), { operationId: 'op-3' });
  assert.equal(replay.duplicate, true);
  assert.equal(replay.id, 'plan-1');
  assert.equal(store.calls.insert, 1, 'replay must not insert again');
});

test('StudyPlanWrite.update rejects a missing plan as non-retryable', async () => {
  const port = new StudyPlanWritePortAdapter(makeStore());
  await assert.rejects(port.update(plan({ id: 'ghost' }), { operationId: 'op-4' }), (error) => {
    assert.equal(error.code, 'STUDY_PLAN_NOT_FOUND');
    assert.equal(error.retryable, false);
    return true;
  });
});

test('StudyPlanWrite.update enforces expectedVersion CAS', async () => {
  const store = makeStore();
  const port = new StudyPlanWritePortAdapter(store);
  await port.create(plan(), { operationId: 'op-5' });
  await assert.rejects(port.update(plan({ title: '新标题' }), { operationId: 'op-6', expectedVersion: 9 }),
    (error) => {
      assert.equal(error.code, 'VERSION_CONFLICT');
      assert.equal(error.retryable, false);
      return true;
    });
  const outcome = await port.update(plan({ title: '新标题' }), { operationId: 'op-7', expectedVersion: 1 });
  assert.equal(outcome.version, 2);
});

test('StudyPlanWrite.complete is idempotent for an already-done plan', async () => {
  const store = makeStore();
  const port = new StudyPlanWritePortAdapter(store);
  await port.create(plan(), { operationId: 'op-8' });
  const first = await port.complete('plan-1', { operationId: 'op-9' });
  assert.equal(first.version, 2);
  assert.equal(store.calls.setDone, 1);
  const second = await port.complete('plan-1', { operationId: 'op-10' });
  assert.equal(second.duplicate, true, 'already-done must be an idempotent success');
  assert.equal(store.calls.setDone, 1, 'no second write for an already-done todo');
});

test('StudyPlanWrite wraps store failures into STUDY_PLAN_WRITE_FAILED (retryable)', async () => {
  const store = makeStore();
  store.failWith('query');
  const port = new StudyPlanWritePortAdapter(store);
  await assert.rejects(port.create(plan(), { operationId: 'op-11' }), (error) => {
    assert.equal(error.code, 'STUDY_PLAN_WRITE_FAILED');
    assert.equal(error.retryable, true);
    return true;
  });
});
