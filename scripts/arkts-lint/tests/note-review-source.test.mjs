import test from 'node:test';
import assert from 'node:assert/strict';

import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

function citation(overrides = {}) {
  return {
    noteId: overrides.noteId ?? 'note-limit',
    version: overrides.version ?? 3,
    title: overrides.title ?? '极限定义',
    excerpt: overrides.excerpt ?? '摘录',
    role: overrides.role ?? 'hit',
    score: overrides.score ?? 0.9,
    matchedFields: overrides.matchedFields ?? ['title'],
    subject: overrides.subject ?? '数学分析',
    chapter: overrides.chapter ?? '极限',
  };
}

function unit(version, content) {
  return {
    id: 'note-limit',
    title: '极限定义',
    content,
    summary: content,
    tags: [],
    subject: '数学分析',
    category: '数学分析',
    chapter: '极限',
    difficulty: 2,
    source: 'manual',
    createdAt: 1,
    updatedAt: 2,
    reviewStatus: 'LEARNING',
    nextReviewAt: 3,
    intervalDays: 1,
    easeFactor: 2.5,
    repetitions: 1,
    prerequisites: [],
    related: [],
    embedding: [],
    userId: 'u1',
    version,
  };
}

function loadSourceService() {
  return loadNoteReviewEtsModule(
    'entry/src/main/ets/services/NoteReviewSourceService.ets',
    {
      mocks: {
        '@kit.ArkData': {},
        common: {
          DatabaseHelper: {
            getStore() {
              return null;
            },
          },
        },
        'entry/src/main/ets/database/NoteDao.ets': {
          NoteDao: class NoteDao {},
        },
        'entry/src/main/ets/models/KnowledgeUnitWriteModels.ets': {},
        'entry/src/main/ets/models/NoteEvidenceModels.ets': {},
        'entry/src/main/ets/models/NoteReviewModels.ets': {},
      },
    },
  );
}

test('NoteReviewSourceService resolves current version without reading a revision', async () => {
  const { NoteReviewSourceService } = loadSourceService();
  let revisionCalls = 0;
  const reader = {
    async queryCurrentUnit() {
      return unit(3, '当前版本内容');
    },
    async queryRevision() {
      revisionCalls += 1;
      return null;
    },
  };

  const result = await new NoteReviewSourceService(reader).resolve(citation({ version: 3 }));
  assert.equal(result.status, 'current');
  assert.equal(result.content, '当前版本内容');
  assert.equal(result.currentVersion, 3);
  assert.equal(revisionCalls, 0);
});

test('NoteReviewSourceService resolves an existing historical version and reports current version', async () => {
  const { NoteReviewSourceService } = loadSourceService();
  const reader = {
    async queryCurrentUnit() {
      return unit(5, '当前版本内容');
    },
    async queryRevision(_noteId, version) {
      assert.equal(version, 3);
      return { unit: unit(3, '历史版本内容') };
    },
  };

  const result = await new NoteReviewSourceService(reader).resolve(citation({ version: 3 }));
  assert.equal(result.status, 'historical');
  assert.equal(result.content, '历史版本内容');
  assert.equal(result.currentVersion, 5);
  assert.match(result.message, /当前版本为 5/);
});

test('NoteReviewSourceService reports deleted before consulting revisions', async () => {
  const { NoteReviewSourceService } = loadSourceService();
  let revisionCalls = 0;
  const reader = {
    async queryCurrentUnit() {
      return null;
    },
    async queryRevision() {
      revisionCalls += 1;
      return { unit: unit(3, '不应复活') };
    },
  };

  const result = await new NoteReviewSourceService(reader).resolve(citation({ version: 3 }));
  assert.equal(result.status, 'deleted');
  assert.equal(result.content, '');
  assert.equal(revisionCalls, 0);
  assert.match(result.message, /不能通过历史版本复活/);
});

test('NoteReviewSourceService reports missing version without silently substituting current content', async () => {
  const { NoteReviewSourceService } = loadSourceService();
  const reader = {
    async queryCurrentUnit() {
      return unit(5, '当前版本内容');
    },
    async queryRevision() {
      return null;
    },
  };

  const result = await new NoteReviewSourceService(reader).resolve(citation({ version: 3 }));
  assert.equal(result.status, 'missing-version');
  assert.equal(result.content, '');
  assert.equal(result.currentVersion, 5);
  assert.match(result.message, /找不到引用版本/);
});

test('NoteReviewSourceService reports unavailable when no store exists or reader fails', async () => {
  const { NoteReviewSourceService } = loadSourceService();
  const noStore = await new NoteReviewSourceService().resolve(citation());
  assert.equal(noStore.status, 'unavailable');
  assert.equal(noStore.content, '');

  const failed = await new NoteReviewSourceService({
    async queryCurrentUnit() {
      throw new Error('read failed');
    },
    async queryRevision() {
      throw new Error('read failed');
    },
  }).resolve(citation());
  assert.equal(failed.status, 'unavailable');
  assert.equal(failed.content, '');
});
