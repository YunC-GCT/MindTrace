import test from 'node:test';
import assert from 'node:assert/strict';

import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

function citation(overrides = {}) {
  return {
    noteId: overrides.noteId ?? 'note-limit',
    version: overrides.version ?? 3,
    title: overrides.title ?? '极限定义',
    excerpt: overrides.excerpt ?? '数列极限用 epsilon-N 语言描述。',
    role: overrides.role ?? 'hit',
    score: overrides.score ?? 0.91,
    matchedFields: overrides.matchedFields ?? ['title'],
    subject: overrides.subject ?? '数学分析',
    chapter: overrides.chapter ?? '极限与连续',
  };
}

function context(citations) {
  return {
    query: '极限',
    topK: citations.length,
    citations,
    relations: [],
    contextText: '',
    degraded: false,
    reason: '',
  };
}

function resultSet(rows) {
  let index = -1;
  const columns = ['id', 'title', 'version', 'subject', 'chapter', 'summary', 'content'];
  return {
    goToFirstRow() {
      index = rows.length > 0 ? 0 : -1;
      return index >= 0;
    },
    goToNextRow() {
      index += 1;
      return index < rows.length;
    },
    getColumnIndex(name) {
      return columns.indexOf(name);
    },
    getString(columnIndex) {
      return String(rows[index][columns[columnIndex]] ?? '');
    },
    getLong(columnIndex) {
      return Number(rows[index][columns[columnIndex]] ?? 0);
    },
    close() {},
  };
}

function loadEvidenceService(runtime = {}) {
  const store = runtime.store ?? null;
  const registry = runtime.registry ?? {
    execute() {
      return Promise.resolve({ ok: false, content: 'not used' });
    },
  };
  const relationDao = runtime.relationDao ?? class KnowledgeRelationDao {};
  return loadNoteReviewEtsModule(
    'entry/src/main/ets/services/NoteEvidenceService.ets',
    {
      mocks: {
        common: {
          DatabaseHelper: {
            getStore() {
              return store;
            },
          },
          ToolCatalog: {
            createReadOnlyRegistry() {
              return registry;
            },
          },
        },
        'entry/src/main/ets/database/KnowledgeRelationDao.ets': { KnowledgeRelationDao: relationDao },
        'entry/src/main/ets/models/NoteEvidenceModels.ets': {},
      },
    },
  );
}

test('NoteEvidenceService filters same-note wrong-version citations', () => {
  const { NoteEvidenceService } = loadEvidenceService();
  const service = new NoteEvidenceService();
  const answer = '依据 [noteId=note-limit version=4] 的内容。';

  const sanitized = service.sanitizeAnswer(
    context([citation({ noteId: 'note-limit', version: 3 })]),
    answer,
  );

  assert.equal(sanitized, '依据 [未验证引用] 的内容。');

  for (const malformed of [
    '[noteId=note-limit version=3abc]',
    '[noteId=note-limit version=3.5]',
    '[noteId=note-limit version=4 version=3]',
  ]) {
    assert.equal(
      service.sanitizeAnswerStrict([citation({ noteId: 'note-limit', version: 3 })], malformed),
      '[未验证引用]',
    );
  }
});

test('NoteEvidenceService keeps exact noteId and version citations across split stream chunks', () => {
  const { NoteEvidenceService } = loadEvidenceService();
  const service = new NoteEvidenceService();
  const filter = service.createStreamFilter(
    context([citation({ noteId: 'note-limit', version: 3 })]),
  );

  const first = filter.push('依据 [noteId=note-limit ver');
  const second = filter.push('sion=3] 的定义。');
  const final = filter.flush();

  assert.equal(first, '依据 ');
  assert.equal(second, '[noteId=note-limit version=3] 的定义。');
  assert.equal(final, '');
});

test('NoteEvidenceService replaces incomplete and arbitrary citations safely', () => {
  const { NoteEvidenceService } = loadEvidenceService();
  const service = new NoteEvidenceService();
  const filter = service.createStreamFilter(
    context([citation({ noteId: 'note-limit', version: 3 })]),
  );

  const first = filter.push('正文 [noteId=note-limit');
  const second = filter.push(' version=3');
  const final = filter.flush();

  assert.equal(first, '正文 ');
  assert.equal(second, '');
  assert.equal(final, '[未验证引用]');

  const arbitrary = service.sanitizeAnswer(
    context([citation({ noteId: 'note-limit', version: 3 })]),
    '[noteId=forged version=3]',
  );
  assert.equal(arbitrary, '[未验证引用]');
});

test('NoteEvidenceService does not pass forged citations through an empty evidence set', () => {
  const { NoteEvidenceService } = loadEvidenceService();
  const service = new NoteEvidenceService();

  const sanitized = service.sanitizeAnswer(
    context([]),
    '没有证据但模型写了 [noteId=forged version=99]。',
  );

  const strict = service.sanitizeAnswerStrict(
    [],
    '没有证据但模型写了 [noteId=forged version=99]。',
  );

  assert.equal(sanitized, '没有证据但模型写了 [noteId=forged version=99]。');
  assert.equal(strict, '没有证据但模型写了 [未验证引用]。');
});

test('NoteEvidenceService source formatting includes bounded source versions', () => {
  const { NoteEvidenceService } = loadEvidenceService();
  const service = new NoteEvidenceService();
  const citations = Array.from({ length: 12 }, (_, index) => citation({
    noteId: `note-${index}`,
    version: index + 1,
    title: `标题 ${index}`,
  }));

  const sources = service.formatSources(context(citations));

  assert.match(sources, /\[noteId=note-0 version=1\]/);
  assert.match(sources, /\[noteId=note-9 version=10\]/);
  assert.doesNotMatch(sources, /\[noteId=note-10 version=11\]/);
  assert.match(sources, /其余 2 条证据已省略/);
});

test('NoteEvidenceService distinguishes no-match and search failure without calling an answer model', async () => {
  let calls = 0;
  const registry = {
    execute() {
      calls += 1;
      return Promise.resolve({ ok: true, content: JSON.stringify({ hits: [] }) });
    },
  };
  const { NoteEvidenceService } = loadEvidenceService({
    store: {},
    registry,
  });
  const service = new NoteEvidenceService();

  const noMatch = await service.build('我的极限笔记', { topK: 99, maxDepth: 99 });
  assert.equal(noMatch.reason, 'no-match');
  assert.equal(noMatch.degraded, false);
  assert.equal(noMatch.citations.length, 0);
  assert.equal(calls, 1);

  const failedRegistry = {
    execute() {
      calls += 1;
      return Promise.resolve({ ok: false, content: 'query failed' });
    },
  };
  const failedService = loadEvidenceService({
    store: {},
    registry: failedRegistry,
  }).NoteEvidenceService;
  const failed = await new failedService().build('我的极限笔记');
  assert.equal(failed.reason, 'search-failed');
  assert.equal(failed.degraded, true);
  assert.equal(failed.citations.length, 0);
  assert.equal(calls, 2);
});

test('NoteEvidenceService bounds retrieval options and keeps direct hits when graph expansion fails', async () => {
  let args = '';
  const registry = {
    execute(_name, rawArgs) {
      args = rawArgs;
      return Promise.resolve({
        ok: true,
        content: JSON.stringify({
          hits: [{
            noteId: 'note-limit',
            version: 3,
            title: '极限定义',
            excerpt: '极限摘录',
            score: 0.9,
            matchedFields: ['title'],
            subject: '数学分析',
            chapter: '极限',
          }],
        }),
      });
    },
  };
  const relationDao = class KnowledgeRelationDao {
    constructor(_store) {}

    expandAcceptedNeighborhood() {
      return Promise.reject(new Error('graph unavailable'));
    }
  };
  const { NoteEvidenceService } = loadEvidenceService({
    store: {},
    registry,
    relationDao,
  });
  const service = new NoteEvidenceService();
  const result = await service.build('根据我的笔记解释极限', { topK: 99, maxDepth: 99 });

  assert.equal(JSON.parse(args).topK, 10);
  assert.equal(result.topK, 10);
  assert.equal(result.degraded, true);
  assert.equal(result.reason, 'graph-failed');
  assert.equal(result.citations.length, 1);
  assert.equal(result.citations[0].noteId, 'note-limit');
});

test('NoteEvidenceService follows incoming prerequisite direction and preserves edge endpoints', async () => {
  const registry = {
    execute() {
      return Promise.resolve({
        ok: true,
        content: JSON.stringify({
          hits: [{
            noteId: 'note-derivative',
            version: 2,
            title: '导数',
            excerpt: '导数摘录',
            score: 0.9,
            matchedFields: ['title'],
            subject: '数学分析',
            chapter: '导数',
          }],
        }),
      });
    },
  };
  const prerequisiteEdge = {
    id: 'edge-limit-derivative',
    fromUnitId: 'note-limit',
    toUnitId: 'note-derivative',
    relationType: 'prerequisite',
    reason: '先掌握极限',
  };
  const relationDao = class KnowledgeRelationDao {
    constructor(_store) {}

    expandAcceptedNeighborhood() {
      throw new Error('wrong graph direction');
    }

    expandAcceptedPrerequisites() {
      return Promise.resolve({
        nodes: [
          { unitId: 'note-derivative', depth: 0 },
          { unitId: 'note-limit', depth: 1 },
        ],
        edges: [prerequisiteEdge],
        truncated: false,
      });
    }
  };
  const store = {
    querySql(_sql, _args, callback) {
      callback(null, resultSet([{
        id: 'note-limit',
        title: '极限',
        version: 4,
        subject: '数学分析',
        chapter: '极限',
        summary: '极限摘要',
        content: '极限内容',
      }]));
    },
  };
  const { NoteEvidenceService } = loadEvidenceService({
    store,
    registry,
    relationDao,
  });
  const service = new NoteEvidenceService();
  const result = await service.build('导数', { graphMode: 'prerequisite-incoming' });

  assert.equal(result.citations.some((item) => item.noteId === 'note-limit' && item.role === 'prerequisite'), true);
  assert.equal(result.relations.length, 1);
  assert.equal(result.relations[0].fromNoteId, 'note-limit');
  assert.equal(result.relations[0].toNoteId, 'note-derivative');
});

test('NoteEvidenceService drops relations whose endpoint was capped or deleted from evidence rows', async () => {
  const registry = {
    execute() {
      return Promise.resolve({
        ok: true,
        content: JSON.stringify({
          hits: [{
            noteId: 'note-derivative',
            version: 2,
            title: '导数',
            excerpt: '导数摘录',
            score: 0.9,
            matchedFields: ['title'],
            subject: '数学分析',
            chapter: '导数',
          }],
        }),
      });
    },
  };
  const relationDao = class KnowledgeRelationDao {
    constructor(_store) {}

    expandAcceptedNeighborhood() {
      return Promise.resolve({
        nodes: [
          { unitId: 'note-derivative', depth: 0 },
          { unitId: 'note-limit', depth: 1 },
          { unitId: 'deleted-neighbor', depth: 1 },
        ],
        edges: [
          {
            id: 'edge-live',
            fromUnitId: 'note-limit',
            toUnitId: 'note-derivative',
            relationType: 'prerequisite',
            reason: 'live',
          },
          {
            id: 'edge-deleted',
            fromUnitId: 'deleted-neighbor',
            toUnitId: 'note-derivative',
            relationType: 'prerequisite',
            reason: 'deleted',
          },
        ],
        truncated: true,
      });
    }
  };
  const store = {
    querySql(_sql, _args, callback) {
      callback(null, resultSet([{
        id: 'note-limit',
        title: '极限',
        version: 4,
        subject: '数学分析',
        chapter: '极限',
        summary: '极限摘要',
        content: '极限内容',
      }]));
    },
  };
  const { NoteEvidenceService } = loadEvidenceService({
    store,
    registry,
    relationDao,
  });
  const result = await new NoteEvidenceService().build('导数');

  assert.equal(result.citations.some((item) => item.noteId === 'deleted-neighbor'), false);
  assert.equal(result.relations.some((item) => item.edgeId === 'edge-deleted'), false);
});
