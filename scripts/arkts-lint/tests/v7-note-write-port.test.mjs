// #238 契约层：NoteWritePort 契约测试（幂等 / CAS / 审批哈希 / 取消 / 错误分流）。
// 直接装载真实 NoteWriteDecisions + NoteWritePortAdapter 源码；store 用内存假实现。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

class NotePortError extends Error {
  constructor(code, message, retryable) {
    super(message);
    this.name = 'NotePortError';
    this.code = code;
    this.retryable = retryable;
  }
}

const decisions = loadNoteReviewEtsModule('common/src/main/ets/ports/NoteWriteDecisions.ets');
const mod = loadNoteReviewEtsModule(
  'entry/src/main/ets/database/NoteWritePortAdapter.ets',
  {
    mocks: {
      common: {
        NotePortError,
        NOTE_WRITE_ERROR_FAILED: 'NOTE_WRITE_FAILED',
        decideWrite: decisions.decideWrite,
      },
    },
  },
);
const NoteWritePortAdapter = mod.NoteWritePortAdapter;

function unit(id, overrides = {}) {
  return {
    id,
    title: 'title-' + id,
    content: 'content',
    summary: 'summary',
    tags: [],
    subject: '数学',
    category: '计算题',
    chapter: '一元二次方程',
    difficulty: 2,
    source: 'manual',
    createdAt: 1,
    updatedAt: 1,
    reviewStatus: 'new',
    nextReviewAt: 0,
    intervalDays: 0,
    easeFactor: 2.5,
    repetitions: 0,
    prerequisites: [],
    related: [],
    embedding: [],
    userId: 'local',
    version: 3,
    ...overrides,
  };
}

function makeStore(options = {}) {
  const calls = { insert: 0, update: 0 };
  const store = {
    calls,
    queryCommit: async () => {
      if (options.throwOnCommit !== undefined) { throw options.throwOnCommit; }
      return options.commit ?? null;
    },
    querySnapshot: async () => options.snapshot ?? null,
    insert: async (u, command) => {
      calls.insert += 1;
      if (options.insertResult !== undefined) { return options.insertResult; }
      return { noteId: u.id.length > 0 ? u.id : 'note-new', version: 1, commitKey: command.commitKey };
    },
    update: async (u, expectedVersion, command) => {
      calls.update += 1;
      if (options.updateResult !== undefined) { return options.updateResult; }
      return { noteId: u.id, version: expectedVersion + 1, commitKey: command.commitKey };
    },
  };
  return store;
}

function tokenOf(cancelled) {
  return { isCancelled: () => cancelled, throwIfCancelled: () => undefined };
}

test('NoteWritePort rejects an empty commitKey before touching the store', async () => {
  const store = makeStore();
  const port = new NoteWritePortAdapter(store);
  await assert.rejects(port.commit(unit('n1'), { commitKey: '   ' }), (error) => {
    assert.equal(error.code, 'COMMIT_KEY_REQUIRED');
    assert.equal(error.retryable, false);
    return true;
  });
  assert.equal(store.calls.insert + store.calls.update, 0);
});

test('NoteWritePort returns the first result on a duplicate commitKey replay', async () => {
  const store = makeStore({ commit: { noteId: 'n1', version: 4, commitKey: 'c1', committedAt: 777 } });
  const port = new NoteWritePortAdapter(store);
  const outcome = await port.commit(unit('n1'), { commitKey: 'c1' });
  assert.equal(outcome.duplicate, true);
  assert.equal(outcome.committed, true);
  assert.equal(outcome.noteId, 'n1');
  assert.equal(outcome.version, 4);
  assert.equal(outcome.committedAt, 777, 'replay must return the first committedAt');
  assert.equal(store.calls.insert + store.calls.update, 0, 'replay must not write again');
});

test('NoteWritePort inserts a new note when the unit has no id', async () => {
  const store = makeStore();
  const port = new NoteWritePortAdapter(store);
  const outcome = await port.commit(unit(''), { commitKey: 'c2' });
  assert.equal(outcome.duplicate, false);
  assert.equal(outcome.committed, true);
  assert.equal(store.calls.insert, 1);
  assert.equal(store.calls.update, 0);
});

test('NoteWritePort reports a store-side duplicate race as duplicate', async () => {
  const store = makeStore({
    insertResult: { noteId: 'n1', version: 2, commitKey: 'c3', duplicate: true },
  });
  const port = new NoteWritePortAdapter(store);
  const outcome = await port.commit(unit(''), { commitKey: 'c3' });
  assert.equal(outcome.duplicate, true, 'in-transaction replay must not be reported as a fresh write');
});

test('NoteWritePort rejects a stale expectedVersion with VERSION_CONFLICT', async () => {
  const store = makeStore({ snapshot: { noteId: 'n1', version: 3 } });
  const port = new NoteWritePortAdapter(store);
  await assert.rejects(port.commit(unit('n1'), { commitKey: 'c4', expectedVersion: 2 }), (error) => {
    assert.equal(error.code, 'VERSION_CONFLICT');
    assert.equal(error.retryable, false);
    return true;
  });
  assert.equal(store.calls.update, 0);
});

test('NoteWritePort updates with the command expectedVersion when it matches', async () => {
  const store = makeStore({ snapshot: { noteId: 'n1', version: 3 } });
  const port = new NoteWritePortAdapter(store);
  const outcome = await port.commit(unit('n1'), { commitKey: 'c5', expectedVersion: 3 });
  assert.equal(store.calls.update, 1);
  assert.equal(outcome.version, 4);
});

test('NoteWritePort updates against the current version when expectedVersion is omitted', async () => {
  const store = makeStore({ snapshot: { noteId: 'n1', version: 3 } });
  const port = new NoteWritePortAdapter(store);
  const outcome = await port.commit(unit('n1'), { commitKey: 'c6' });
  assert.equal(store.calls.update, 1);
  assert.equal(outcome.version, 4, 'update must CAS on the snapshot version, not 0');
});

test('NoteWritePort rejects a stale approval hash without writing', async () => {
  const store = makeStore({ snapshot: { noteId: 'n1', version: 3 } });
  const port = new NoteWritePortAdapter(store);
  await assert.rejects(port.commit(unit('n1'), { commitKey: 'c7', approvedCheckpointHash: 'hash-new' }), (error) => {
    assert.equal(error.code, 'APPROVAL_HASH_MISMATCH');
    assert.equal(error.retryable, false);
    return true;
  });
  assert.equal(store.calls.update, 0);
});

test('NoteWritePort reports NOTE_NOT_FOUND for a positive expectedVersion on a missing note', async () => {
  const store = makeStore({ snapshot: null });
  const port = new NoteWritePortAdapter(store);
  await assert.rejects(port.commit(unit('n1'), { commitKey: 'c8', expectedVersion: 5 }), (error) => {
    assert.equal(error.code, 'NOTE_NOT_FOUND');
    assert.equal(error.retryable, false);
    return true;
  });
});

test('NoteWritePort wraps store failures into NOTE_WRITE_FAILED (retryable)', async () => {
  const store = makeStore({ throwOnCommit: new Error('rdb closed') });
  const port = new NoteWritePortAdapter(store);
  await assert.rejects(port.commit(unit('n1'), { commitKey: 'c9' }), (error) => {
    assert.equal(error.code, 'NOTE_WRITE_FAILED');
    assert.equal(error.retryable, true);
    return true;
  });
});

test('NoteWritePort preserves structured store errors instead of flattening them', async () => {
  const store = makeStore({ throwOnCommit: new NotePortError('VERSION_CONFLICT', 'race lost', false) });
  const port = new NoteWritePortAdapter(store);
  await assert.rejects(port.commit(unit('n1'), { commitKey: 'c10' }), (error) => {
    assert.equal(error.code, 'VERSION_CONFLICT', 'a store-side VERSION_CONFLICT must not become NOTE_WRITE_FAILED');
    assert.equal(error.retryable, false);
    return true;
  });
});

test('NoteWritePort reports cancelled before commit without any IO', async () => {
  const store = makeStore();
  const port = new NoteWritePortAdapter(store);
  const outcome = await port.commit(unit('n1'), { commitKey: 'c11', cancellationToken: tokenOf(true) });
  assert.equal(outcome.cancelled, true);
  assert.equal(outcome.committed, false);
  assert.equal(outcome.duplicate, false);
  assert.equal(store.calls.insert + store.calls.update, 0);
});

test('NoteWritePort reports cancelled after commit as committed (cannot un-write)', async () => {
  const store = makeStore({ snapshot: { noteId: 'n1', version: 3 } });
  const port = new NoteWritePortAdapter(store);
  // 第一次检查（提交前）未取消，第二次检查（落库后）已取消：模拟「提交后取消」。
  let checks = 0;
  const token = {
    isCancelled: () => { checks += 1; return checks > 1; },
    throwIfCancelled: () => undefined,
  };
  const outcome = await port.commit(unit('n1'), { commitKey: 'c12', cancellationToken: token, expectedVersion: 3 });
  assert.equal(outcome.cancelled, true);
  assert.equal(outcome.committed, true, 'a landed write must be reported as committed');
  assert.equal(outcome.noteId, 'n1');
});
