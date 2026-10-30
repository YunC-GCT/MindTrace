// #238 / ADR-0021 Step 3：证据服务注入路径契约测试。
// 装载真实 NoteEvidenceService 源码；RAG 命中与图扩展用 fake，note 读取用 fake NoteReadPort。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const calls = [];

const hitPayload = JSON.stringify({
  query: '极限',
  topK: 3,
  count: 1,
  hits: [{
    noteId: 'note-1',
    version: 1,
    title: '极限定义',
    excerpt: '极限的第一条证据',
    score: 4,
    matchedFields: ['title'],
    subject: '数学',
    chapter: '极限',
    summary: '',
    tags: '[]',
    updatedAt: 10,
  }],
});

const registry = {
  execute: async () => ({ ok: true, content: hitPayload }),
};

class FakeKnowledgeRelationDao {
  constructor(_store) { this.store = _store; }
  async expandAcceptedNeighborhood(_seeds, _limits) {
    return { nodes: [{ unitId: 'note-2' }], edges: [] };
  }
  async expandAcceptedPrerequisites(_seeds, _limits) {
    return { nodes: [{ unitId: 'note-2' }], edges: [] };
  }
}

const serviceModule = loadNoteReviewEtsModule(
  'entry/src/main/ets/services/NoteEvidenceService.ets',
  {
    mocks: {
      common: {
        DatabaseHelper: { getStore: () => ({}) },
        ToolCatalog: { createReadOnlyRegistry: () => registry },
        ToolRegistry: class {},
        ToolResult: class {},
      },
      'entry/src/main/ets/database/KnowledgeRelationDao.ets': {
        KnowledgeRelationDao: FakeKnowledgeRelationDao,
      },
    },
  },
);
const NoteEvidenceService = serviceModule.NoteEvidenceService;

function detail(id) {
  return {
    id,
    title: '关联笔记',
    content: '关联笔记正文：极限的补充说明',
    summary: '极限补充',
    tags: ['极限'],
    subject: '数学',
    category: '定理',
    chapter: '极限',
    difficulty: 2,
    reviewStatus: 'new',
    nextReviewAt: 0,
    intervalDays: 0,
    easeFactor: 2.5,
    repetitions: 0,
    userId: 'local',
    createdAt: 1,
    updatedAt: 20,
    version: 3,
    source: 'manual',
  };
}

function portOf(details) {
  return {
    list: async () => [],
    get: async () => null,
    search: async () => [],
    listByIds: async (ids) => {
      calls.push(ids);
      return details;
    },
  };
}

test('evidence expands through the injected NoteReadPort instead of SQL', async () => {
  calls.length = 0;
  const service = new NoteEvidenceService(portOf([detail('note-2')]));
  const context = await service.build('极限', { graphMode: 'neighborhood' });
  assert.equal(calls.length, 1, 'graph expansion must ask the port for live rows');
  assert.deepEqual(Array.from(calls[0]), ['note-2']);
  const related = context.citations.find((citation) => citation.noteId === 'note-2');
  assert.ok(related !== undefined, 'port rows must become citations');
  assert.equal(related.role, 'related');
  assert.ok(related.excerpt.includes('极限'), 'excerpt must come from the port content');
});
