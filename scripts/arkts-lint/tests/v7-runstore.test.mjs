// #238 / §17.5：RunStore 持久化契约测试（schema v16 + adapter 协议）。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const root = resolve(import.meta.dirname, '../../..');
const db = readFileSync(resolve(root, 'common/src/main/ets/DatabaseHelper.ets'), 'utf8');

class RunStoreError extends Error {
  constructor(code, message, retryable) {
    super(message);
    this.name = 'RunStoreError';
    this.code = code;
    this.retryable = retryable;
  }
}

const adapterModule = loadNoteReviewEtsModule('entry/src/main/ets/database/RunStoreAdapter.ets', {
  mocks: {
    common: {
      RunStoreError,
      RUN_STORE_ERROR_RUN_NOT_FOUND: 'RUN_NOT_FOUND',
      RUN_STORE_ERROR_RUN_EXISTS: 'RUN_EXISTS',
      RUN_STORE_ERROR_INVALID_RUN: 'INVALID_RUN',
      RUN_STORE_ERROR_FAILED: 'RUN_STORE_FAILED',
      RUN_EVENTS_DEFAULT_LIMIT: 50,
      RUN_EVENTS_MAX_LIMIT: 200,
    },
  },
});
const RunStoreAdapter = adapterModule.RunStoreAdapter;

function makeStore() {
  const records = new Map();
  const events = new Map();
  let failMode = null;
  const store = {
    failWith(mode) { failMode = mode; },
    async queryRecord(runId) {
      if (failMode === 'query') { throw new Error('db down'); }
      const found = records.get(runId);
      return found === undefined ? null : { ...found };
    },
    async insertRecord(record) {
      if (failMode === 'insert') { throw new Error('db down'); }
      records.set(record.runId, { ...record });
    },
    async updateRecord(record) {
      if (failMode === 'update') { throw new Error('db down'); }
      records.set(record.runId, { ...record });
    },
    async listEvents(runId, afterSequence, limit) {
      const all = (events.get(runId) ?? []).filter((event) => event.sequence > afterSequence);
      return all.slice(0, limit);
    },
    async appendEvent(runId, kind, payloadJson, createdAt) {
      if (failMode === 'append') { throw new Error('db down'); }
      const all = events.get(runId) ?? [];
      const event = {
        eventId: 'e' + (all.length + 1),
        runId,
        sequence: all.length + 1,
        kind,
        payloadJson,
        createdAt,
      };
      all.push(event);
      events.set(runId, all);
      return event;
    },
  };
  return store;
}

const record = (overrides = {}) => ({ runId: 'run-1', status: 'running', updatedAt: 1, ...overrides });

test('schema v16 adds run_store and run_event with their indexes', () => {
  const version = Number(db.match(/DB_SCHEMA_VERSION: number = (\d+)/)[1]);
  assert.ok(version >= 16, 'schema must reach v16');
  assert.match(db, /CREATE TABLE IF NOT EXISTS run_store \([^`]*run_id TEXT PRIMARY KEY/);
  assert.match(db, /CREATE TABLE IF NOT EXISTS run_event \([^`]*event_id TEXT PRIMARY KEY/);
  assert.match(db, /idx_run_event_run_seq ON run_event\(run_id, sequence\)/);
  assert.match(db, /SQL_CREATE_RUN_STORE,/);
  assert.match(db, /SQL_CREATE_RUN_EVENT,/);
  assert.match(db, /SQL_INDEX_RUN_EVENT_RUN_SEQ,/);
});

test('RunStore.create stores a record and rejects a duplicate runId', async () => {
  const port = new RunStoreAdapter(makeStore());
  await port.create(record());
  assert.equal((await port.get('run-1')).status, 'running');
  await assert.rejects(port.create(record()), (error) => {
    assert.equal(error.code, 'RUN_EXISTS');
    assert.equal(error.retryable, false);
    return true;
  });
});

test('RunStore.create rejects an empty runId and an illegal status', async () => {
  const port = new RunStoreAdapter(makeStore());
  await assert.rejects(port.create(record({ runId: '' })), (error) => error.code === 'INVALID_RUN');
  await assert.rejects(port.create(record({ status: 'exploded' })), (error) => error.code === 'INVALID_RUN');
});

test('RunStore.update rejects a missing run as non-retryable RUN_NOT_FOUND', async () => {
  const port = new RunStoreAdapter(makeStore());
  await assert.rejects(port.update(record({ runId: 'ghost' })), (error) => {
    assert.equal(error.code, 'RUN_NOT_FOUND');
    assert.equal(error.retryable, false);
    return true;
  });
});

test('RunStore.update cannot let cancelled overwrite committed facts', async () => {
  const store = makeStore();
  const port = new RunStoreAdapter(store);
  await port.create(record({ status: 'running' }));
  await port.update(record({ status: 'readyPreview', committedNoteId: 'note-1', committedVersion: 3 }));
  await port.update(record({ status: 'cancelled' }));
  const after = await port.get('run-1');
  assert.equal(after.status, 'cancelled');
  assert.equal(after.committedNoteId, 'note-1', 'committed note must survive a cancel');
  assert.equal(after.committedVersion, 3);
});

test('RunStore.appendEvent assigns monotonic sequences and defaults the payload', async () => {
  const port = new RunStoreAdapter(makeStore());
  await port.create(record());
  const first = await port.appendEvent('run-1', 'node_start', '{"node":"ocr"}');
  const second = await port.appendEvent('run-1', 'node_end', '');
  assert.equal(first.sequence, 1);
  assert.equal(second.sequence, 2);
  assert.equal(second.payloadJson, '{}', 'empty payload must default to {}');
});

test('RunStore.listEvents applies afterSequence and clamps the limit', async () => {
  const port = new RunStoreAdapter(makeStore());
  await port.create(record());
  for (let index = 0; index < 3; index += 1) {
    await port.appendEvent('run-1', 'tick', '{}');
  }
  const afterFirst = await port.listEvents('run-1', 1, 10);
  assert.deepEqual(Array.from(afterFirst).map((event) => event.sequence), [2, 3]);
  const clamped = await port.listEvents('run-1', 0, 0);
  assert.equal(clamped.length, 1, 'limit below 1 must clamp to 1');
});

test('RunStore wraps store failures into RUN_STORE_FAILED (retryable)', async () => {
  const store = makeStore();
  store.failWith('query');
  const port = new RunStoreAdapter(store);
  await assert.rejects(port.get('run-1'), (error) => {
    assert.equal(error.code, 'RUN_STORE_FAILED');
    assert.equal(error.retryable, true);
    return true;
  });
});
