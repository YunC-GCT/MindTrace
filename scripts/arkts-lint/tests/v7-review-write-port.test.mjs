// 路径: scripts/arkts-lint/tests/v7-review-write-port.test.mjs
// 职责: ReviewWritePort 契约——operationId 幂等、错误码分流、日志与条目同事务语义（fake store）。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

const REVIEW_WRITE_ERROR_OPERATION_REQUIRED = 'OPERATION_ID_REQUIRED';
const REVIEW_WRITE_ERROR_INVALID_ITEM = 'INVALID_REVIEW_ITEM';
const REVIEW_WRITE_ERROR_ITEM_NOT_FOUND = 'REVIEW_ITEM_NOT_FOUND';
const REVIEW_WRITE_ERROR_WRITE_FAILED = 'REVIEW_WRITE_FAILED';

class ReviewPortError extends Error {
  constructor(code, message, retryable) {
    super(message);
    this.name = 'ReviewPortError';
    this.code = code;
    this.retryable = retryable;
  }
}

const commonMock = {
  ReviewPortError,
  REVIEW_WRITE_ERROR_OPERATION_REQUIRED,
  REVIEW_WRITE_ERROR_INVALID_ITEM,
  REVIEW_WRITE_ERROR_ITEM_NOT_FOUND,
  REVIEW_WRITE_ERROR_WRITE_FAILED,
};

const { ReviewWritePortAdapter } = loadNoteReviewEtsModule(
  'entry/src/main/ets/database/ReviewWritePortAdapter.ets',
  { mocks: { common: commonMock } },
);

function makeItem(overrides = {}) {
  return {
    id: 'item-1',
    unitId: 'unit-1',
    subject: '数学分析',
    status: 'learning',
    nextReviewAt: 1000,
    intervalDays: 1,
    easeFactor: 2.5,
    repetitions: 1,
    lapses: 0,
    lastReviewedAt: 900,
    createdAt: 800,
    updatedAt: 900,
    ...overrides,
  };
}

function makeLog(overrides = {}) {
  return {
    id: 'log-1',
    reviewItemId: 'item-1',
    unitId: 'unit-1',
    reviewedAt: 1200,
    grade: 'good',
    correct: true,
    durationMs: 3000,
    intervalBefore: 1,
    intervalAfter: 3,
    ...overrides,
  };
}

class FakeStore {
  constructor() {
    this.operations = new Map();
    this.items = new Map([['item-1', makeItem()]]);
    this.logs = new Map();
    this.upsertCalls = 0;
    this.appendCalls = 0;
    this.failNext = false;
  }

  async queryOperation(operationId) {
    return this.operations.get(operationId) ?? null;
  }

  async queryItem(id) {
    return this.items.get(id) ?? null;
  }

  async queryLog(id) {
    return this.logs.get(id) ?? null;
  }

  async upsertItem(item, command) {
    if (this.failNext) {
      this.failNext = false;
      throw new Error('disk full');
    }
    this.upsertCalls += 1;
    this.items.set(item.id, item);
    this.operations.set(command.operationId, {
      operationId: command.operationId,
      kind: 'schedule',
      itemId: item.id,
      logId: '',
      committedAt: Date.now(),
    });
    return item;
  }

  async appendLog(item, entry, command) {
    if (!this.items.has(item.id)) {
      throw new ReviewPortError(REVIEW_WRITE_ERROR_ITEM_NOT_FOUND, 'review item not found', false);
    }
    if (this.failNext) {
      this.failNext = false;
      throw new Error('disk full');
    }
    this.appendCalls += 1;
    this.logs.set(entry.id, entry);
    this.operations.set(command.operationId, {
      operationId: command.operationId,
      kind: 'record',
      itemId: item.id,
      logId: entry.id,
      committedAt: Date.now(),
    });
    return entry;
  }
}

test('schedule 写入后重放同一 operationId 返回 duplicate 且不重复写', async () => {
  const store = new FakeStore();
  const port = new ReviewWritePortAdapter(store);
  const first = await port.schedule(makeItem(), { operationId: 'op-schedule' });
  assert.equal(first.duplicate, false);
  assert.equal(first.item.id, 'item-1');
  const second = await port.schedule(makeItem(), { operationId: 'op-schedule' });
  assert.equal(second.duplicate, true);
  assert.equal(store.upsertCalls, 1);
});

test('record 追加日志并可重放；重放带回首次日志', async () => {
  const store = new FakeStore();
  const port = new ReviewWritePortAdapter(store);
  const first = await port.record(makeItem(), makeLog(), { operationId: 'op-record' });
  assert.equal(first.duplicate, false);
  assert.equal(first.log.id, 'log-1');
  const second = await port.record(makeItem(), makeLog(), { operationId: 'op-record' });
  assert.equal(second.duplicate, true);
  assert.equal(second.log.id, 'log-1');
  assert.equal(store.appendCalls, 1);
});

test('operationId 必填；unitId 必填；record 的 reviewItemId 必须匹配', async () => {
  const port = new ReviewWritePortAdapter(new FakeStore());
  await assert.rejects(
    () => port.schedule(makeItem(), { operationId: '  ' }),
    (error) => error.code === REVIEW_WRITE_ERROR_OPERATION_REQUIRED,
  );
  await assert.rejects(
    () => port.schedule(makeItem({ unitId: '' }), { operationId: 'op' }),
    (error) => error.code === REVIEW_WRITE_ERROR_INVALID_ITEM,
  );
  await assert.rejects(
    () => port.record(makeItem(), makeLog({ reviewItemId: 'other' }), { operationId: 'op' }),
    (error) => error.code === REVIEW_WRITE_ERROR_INVALID_ITEM,
  );
});

test('存储失败映射为 REVIEW_WRITE_FAILED(retryable)；条目不存在映射为 NOT_FOUND', async () => {
  const store = new FakeStore();
  const port = new ReviewWritePortAdapter(store);
  store.failNext = true;
  await assert.rejects(
    () => port.schedule(makeItem(), { operationId: 'op-fail' }),
    (error) => error.code === REVIEW_WRITE_ERROR_WRITE_FAILED && error.retryable === true,
  );
  await assert.rejects(
    () => port.record(makeItem({ id: 'missing' }), makeLog({ reviewItemId: 'missing' }), { operationId: 'op-missing' }),
    (error) => error.code === REVIEW_WRITE_ERROR_ITEM_NOT_FOUND,
  );
});

test('schema v23 与 DAO 事务接线：review_op 与业务写入同事务', () => {
  const db = read('common/src/main/ets/DatabaseHelper.ets');
  assert.match(db, /DB_SCHEMA_VERSION: number = 23/);
  assert.match(db, /CREATE TABLE IF NOT EXISTS review_op/);
  const dao = read('entry/src/main/ets/database/ReviewWriteStoreDao.ets');
  assert.match(dao, /await transaction\.insert\('review_op'/);
  assert.match(dao, /await transaction\.commit\(\)/);
  assert.match(dao, /createTransaction\(\)/);
  const adapter = read('entry/src/main/ets/database/ReviewWritePortAdapter.ets');
  assert.match(adapter, /implements ReviewWritePort/);
  assert.match(adapter, /store\.upsertItem/);
  assert.match(adapter, /store\.appendLog/);
});
