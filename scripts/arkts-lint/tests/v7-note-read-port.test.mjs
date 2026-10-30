// #238 契约层：NoteReadPort 契约测试（P0 修复后）。
// 装载真实 entry 适配器源码（TypeScript 转译 + vm），store 用内存假实现；
// 断言端口语义：过滤 / 排序 / 分页 / 元数据检索边界 / 结构化错误码。
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

const mocks = {
  common: {
    NotePortError,
    NOTE_READ_ERROR_INVALID_QUERY: 'INVALID_QUERY',
    NOTE_READ_ERROR_READ_FAILED: 'NOTE_READ_FAILED',
  },
};
const adapterModule = loadNoteReviewEtsModule(
  'entry/src/main/ets/database/NoteReadPortAdapter.ets',
  { mocks },
);
const NoteReadPortAdapter = adapterModule.NoteReadPortAdapter;

function unit(id, overrides = {}) {
  return {
    id,
    title: 'title-' + id,
    content: 'content-' + id,
    summary: 'summary-' + id,
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
    version: 1,
    ...overrides,
  };
}

function storeOf(units) {
  return {
    queryById: async (id) => units.find((u) => u.id === id) ?? null,
    queryAllMetadata: async () => units,
  };
}

const page = (overrides = {}) => ({ limit: 10, offset: 0, ...overrides });

test('NoteReadPort.get returns the full unit and null for a missing id', async () => {
  const port = new NoteReadPortAdapter(storeOf([unit('a'), unit('b')]));
  assert.equal((await port.get('a')).id, 'a');
  assert.equal(await port.get('missing'), null);
});

test('NoteReadPort.get rejects an empty id with INVALID_QUERY (non-retryable)', async () => {
  const port = new NoteReadPortAdapter(storeOf([]));
  await assert.rejects(port.get(''), (error) => {
    assert.equal(error.code, 'INVALID_QUERY');
    assert.equal(error.retryable, false);
    return true;
  });
});

test('NoteReadPort.get wraps store failures into NOTE_READ_FAILED (retryable)', async () => {
  const broken = {
    queryById: async () => { throw new Error('rdb closed'); },
    queryAllMetadata: async () => [],
  };
  const port = new NoteReadPortAdapter(broken);
  await assert.rejects(port.get('a'), (error) => {
    assert.equal(error.code, 'NOTE_READ_FAILED');
    assert.equal(error.retryable, true);
    assert.match(error.message, /rdb closed/);
    return true;
  });
});

test('NoteReadPort.list filters by subject and chapter, newest first', async () => {
  const units = [
    unit('old', { subject: '数学', chapter: '三角', updatedAt: 10 }),
    unit('new', { subject: '数学', chapter: '三角', updatedAt: 30 }),
    unit('other', { subject: '物理', chapter: '三角', updatedAt: 20 }),
  ];
  const port = new NoteReadPortAdapter(storeOf(units));
  const listed = await port.list(page({ subject: '数学' }));
  assert.deepEqual(listed.map((item) => item.id), ['new', 'old']);
});

test('NoteReadPort.list paginates after sorting, never before', async () => {
  const units = [unit('a', { updatedAt: 10 }), unit('b', { updatedAt: 30 }), unit('c', { updatedAt: 20 })];
  const port = new NoteReadPortAdapter(storeOf(units));
  const listed = await port.list(page({ limit: 1, offset: 1 }));
  assert.deepEqual(listed.map((item) => item.id), ['c'], 'offset must apply to the sorted list');
});

test('NoteReadPort.list rejects a non-positive limit and a negative offset', async () => {
  const port = new NoteReadPortAdapter(storeOf([unit('a')]));
  await assert.rejects(port.list(page({ limit: 0 })), (error) => error.code === 'INVALID_QUERY');
  await assert.rejects(port.list(page({ offset: -1 })), (error) => error.code === 'INVALID_QUERY');
});

test('NoteReadPort.search validates the query before the blank-keyword shortcut', async () => {
  const port = new NoteReadPortAdapter(storeOf([unit('a')]));
  await assert.rejects(port.search(page({ keyword: '  ', limit: 0 })), (error) => {
    assert.equal(error.code, 'INVALID_QUERY');
    assert.equal(error.retryable, false);
    return true;
  });
});

test('NoteReadPort.list projects metadata for review consumers, never content', async () => {
  const port = new NoteReadPortAdapter(storeOf([unit('a', { reviewStatus: 'due', nextReviewAt: 99 })]));
  const listed = await port.list(page());
  assert.equal(Object.prototype.hasOwnProperty.call(listed[0], 'content'), false);
  assert.equal(listed[0].title, 'title-a');
  assert.equal(listed[0].difficulty, 2, 'DifficultyLevel.MEDIUM must keep its enum value');
  assert.equal(listed[0].reviewStatus, 'due');
  assert.equal(listed[0].nextReviewAt, 99);
});

test('NoteReadPort.list copies tags and does not sort the store array in place', async () => {
  const units = [unit('a', { tags: ['x'], updatedAt: 10 }), unit('b', { tags: ['y'], updatedAt: 30 })];
  const port = new NoteReadPortAdapter(storeOf(units));
  const listed = await port.list(page());
  listed[0].tags.push('mutated');
  assert.deepEqual(units.find((u) => u.id === 'b').tags, ['y'], 'projection tags must be a copy');
  assert.deepEqual(units.map((u) => u.id), ['a', 'b'], 'the store array must keep its own order');
});

test('NoteReadPort.search is case-insensitive over metadata and respects limit', async () => {
  const units = [
    unit('hit-title', { title: 'Unary Quadratic', updatedAt: 3 }),
    unit('hit-tag', { tags: ['QUADRATIC'], updatedAt: 2 }),
    unit('miss', { title: 'linear', summary: 'no match here', updatedAt: 1 }),
  ];
  const port = new NoteReadPortAdapter(storeOf(units));
  const hits = await port.search(page({ keyword: 'quadratic' }));
  assert.deepEqual(hits.map((item) => item.id), ['hit-title', 'hit-tag']);
});

test('NoteReadPort.search never falls back to note body text (RAG owns full text)', async () => {
  const units = [unit('body-only', { content: 'quadratic inside body only', title: 'plain', summary: 'plain' })];
  const port = new NoteReadPortAdapter(storeOf(units));
  const hits = await port.search(page({ keyword: 'quadratic' }));
  assert.equal(hits.length, 0, 'body-only matches must not surface through the metadata search');
});

test('NoteReadPort.search returns empty for a blank keyword without scanning', async () => {
  const port = new NoteReadPortAdapter(storeOf([unit('a')]));
  const hits = await port.search(page({ keyword: '   ' }));
  assert.equal(hits.length, 0, 'a blank keyword must not scan the table');
});

test('NoteReadPort.search paginates on the sorted result set', async () => {
  const units = [
    unit('q-old', { title: 'quadratic old', updatedAt: 1 }),
    unit('q-new', { title: 'quadratic new', updatedAt: 9 }),
  ];
  const port = new NoteReadPortAdapter(storeOf(units));
  const hits = await port.search(page({ keyword: 'quadratic', limit: 1, offset: 1 }));
  assert.deepEqual(hits.map((item) => item.id), ['q-old']);
});
