// #238 契约层：StudyPlanReadPort 契约测试（待办语义）。
// 装载真实 entry 适配器源码；存储行与 subject 派生都用内存假实现。
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

const mod = loadNoteReviewEtsModule(
  'entry/src/main/ets/database/StudyPlanPortAdapter.ets',
  { mocks: { common: { NotePortError } } },
);
const StudyPlanPortAdapter = mod.StudyPlanPortAdapter;

function record(id, overrides = {}) {
  return {
    id,
    title: 'todo-' + id,
    isDone: false,
    priority: 2,
    linkedNoteId: '',
    createdAt: 0,
    dueDate: 0,
    ...overrides,
  };
}

const storeOf = (records) => ({ queryAll: async () => records });

test('StudyPlanReadPort.listPending excludes done items', async () => {
  const port = new StudyPlanPortAdapter(storeOf([
    record('open', { isDone: false }),
    record('done', { isDone: true }),
  ]));
  const pending = await port.listPending();
  assert.deepEqual(Array.from(pending).map((item) => item.id), ['open']);
});

test('StudyPlanReadPort.listPending orders by due date with no-due last', async () => {
  const port = new StudyPlanPortAdapter(storeOf([
    record('none', { dueDate: 0 }),
    record('late', { dueDate: 300 }),
    record('early', { dueDate: 100 }),
  ]));
  const pending = await port.listPending();
  assert.deepEqual(Array.from(pending).map((item) => item.id), ['early', 'late', 'none']);
});

test('StudyPlanReadPort.listPending derives subject from linked note and filters by it', async () => {
  const resolver = async (noteId) => (noteId === 'note-1' ? '数学' : '物理');
  const port = new StudyPlanPortAdapter(storeOf([
    record('a', { linkedNoteId: 'note-1' }),
    record('b', { linkedNoteId: 'note-2' }),
    record('c'),
  ]), resolver);
  const pending = await port.listPending('数学');
  assert.deepEqual(Array.from(pending).map((item) => item.id), ['a']);
  assert.equal((await port.listPending()).length, 3);
});

test('StudyPlanReadPort.listPending degrades to an empty subject when the resolver fails', async () => {
  const broken = async () => { throw new Error('note missing'); };
  const port = new StudyPlanPortAdapter(storeOf([record('a', { linkedNoteId: 'note-1' })]), broken);
  const pending = await port.listPending();
  assert.equal(pending[0].subject, '');
});

test('StudyPlanReadPort.get returns the item by id and null when missing', async () => {
  const port = new StudyPlanPortAdapter(storeOf([record('a', { title: '复习极限' })]));
  assert.equal((await port.get('a')).title, '复习极限');
  assert.equal(await port.get('missing'), null);
});

test('StudyPlanReadPort wraps store failures into STUDY_PLAN_READ_FAILED (retryable)', async () => {
  const broken = { queryAll: async () => { throw new Error('rdb busy'); } };
  const port = new StudyPlanPortAdapter(broken);
  await assert.rejects(port.listPending(), (error) => {
    assert.equal(error.code, 'STUDY_PLAN_READ_FAILED');
    assert.equal(error.retryable, true);
    return true;
  });
});