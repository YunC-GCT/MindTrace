// ADR-0022 / #238：ReviewReadPort 契约测试（只读，不含 SM-2）。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const adapterModule = loadNoteReviewEtsModule('common/src/main/ets/ports/impl/ReviewReadPortAdapter.ets');
const ReviewReadPortAdapter = adapterModule.ReviewReadPortAdapter;

function item(id, overrides = {}) {
  return {
    id,
    unitId: 'unit-' + id,
    subject: '数学',
    status: 'review',
    nextReviewAt: 100,
    intervalDays: 3,
    easeFactor: 2.5,
    repetitions: 2,
    lapses: 0,
    lastReviewedAt: 50,
    createdAt: 10,
    updatedAt: 60,
    ...overrides,
  };
}

function logEntry(id, overrides = {}) {
  return {
    id,
    reviewItemId: 'item-1',
    unitId: 'unit-1',
    reviewedAt: 50,
    grade: 'good',
    correct: true,
    durationMs: 1200,
    intervalBefore: 3,
    intervalAfter: 7,
    ...overrides,
  };
}

function makeStore(options = {}) {
  const calls = { due: [], byUnit: [], logs: [] };
  return {
    calls,
    listDue: async (now, limit) => {
      calls.due.push({ now, limit });
      return options.dueItems ?? [item('a')];
    },
    getByUnit: async (unitId) => {
      calls.byUnit.push(unitId);
      if (options.failByUnit === true) { throw new Error('rdb closed'); }
      return options.unitItem ?? null;
    },
    listLogs: async (unitId, limit) => {
      calls.logs.push({ unitId, limit });
      return options.logs ?? [logEntry('l1')];
    },
  };
}

test('ReviewRead.listDue passes now through and clamps the default limit', async () => {
  const store = makeStore();
  const port = new ReviewReadPortAdapter(store);
  const due = await port.listDue(1234);
  assert.equal(due.length, 1);
  assert.deepEqual(store.calls.due[0], { now: 1234, limit: 20 });
});

test('ReviewRead.listDue rejects a non-positive now', async () => {
  const port = new ReviewReadPortAdapter(makeStore());
  await assert.rejects(port.listDue(0), (error) => {
    assert.equal(error.code, 'INVALID_QUERY');
    assert.equal(error.retryable, false);
    return true;
  });
});

test('ReviewRead.listDue clamps limit into [1, 100]', async () => {
  const store = makeStore();
  const port = new ReviewReadPortAdapter(store);
  await port.listDue(1234, 0);
  await port.listDue(1234, 999);
  assert.deepEqual(Array.from(store.calls.due).map((call) => call.limit), [1, 100]);
});

test('ReviewRead.getByUnit returns the item and rejects an empty unitId', async () => {
  const store = makeStore({ unitItem: item('u1') });
  const port = new ReviewReadPortAdapter(store);
  assert.equal((await port.getByUnit('unit-u1')).id, 'u1');
  await assert.rejects(port.getByUnit(''), (error) => error.code === 'INVALID_QUERY');
});

test('ReviewRead.history returns log entries and clamps the limit', async () => {
  const store = makeStore();
  const port = new ReviewReadPortAdapter(store);
  const history = await port.history('unit-1', 5);
  assert.equal(history.length, 1);
  assert.equal(history[0].grade, 'good');
  assert.deepEqual(store.calls.logs[0], { unitId: 'unit-1', limit: 5 });
});

test('ReviewRead wraps store failures into REVIEW_READ_FAILED (retryable)', async () => {
  const store = makeStore({ failByUnit: true });
  const port = new ReviewReadPortAdapter(store);
  await assert.rejects(port.getByUnit('unit-1'), (error) => {
    assert.equal(error.code, 'REVIEW_READ_FAILED');
    assert.equal(error.retryable, true);
    return true;
  });
});
