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

function loadEvidenceService() {
  return loadNoteReviewEtsModule('agents/src/main/ets/evidence/NoteEvidenceService.ets');
}

/**
 * 证据服务现在只认三个端口：检索 / 图谱 / 读行。
 * 测试直接给假端口，不再 mock DatabaseHelper 或 DAO。
 */
function makeService(runtime = {}) {
  const { NoteEvidenceService } = loadEvidenceService();
  const calls = { search: [], graph: [], read: [] };
  const search = {
    async search(query, topK, options) {
      calls.search.push({ query, topK, options });
      if (runtime.searchError) { throw new Error(runtime.searchError); }
      return runtime.citations ?? [];
    },
  };
  const emptyGraph = { nodes: [], edges: [], truncated: false };
  const graph = {
    async expandAcceptedNeighborhood(seedIds, maxDepth) {
      calls.graph.push({ mode: 'neighborhood', seedIds, maxDepth });
      if (runtime.graphError) { throw new Error(runtime.graphError); }
      return runtime.neighborhood ?? emptyGraph;
    },
    async expandAcceptedPrerequisites(seedIds, maxDepth) {
      calls.graph.push({ mode: 'prerequisites', seedIds, maxDepth });
      if (runtime.graphError) { throw new Error(runtime.graphError); }
      return runtime.prerequisites ?? emptyGraph;
    },
  };
  const read = {
    async listByIds(ids) {
      calls.read.push(ids);
      return runtime.rows ?? [];
    },
  };
  return { service: new NoteEvidenceService(search, graph, read), calls };
}

test('natural-language evidence requests retrieve a topic instead of the entire sentence', async () => {
  const { service, calls } = makeService({ citations: [citation()] });
  for (const input of ['解释一下极限', '请帮我讲讲极限', '根据我的笔记解释一下极限', '极限是什么？']) {
    const result = await service.build(input, { graphMode: 'none' });
    assert.equal(result.citations.length, 1, input);
    assert.equal(result.query, '极限', input);
  }
  assert.deepEqual(calls.search.map((item) => item.query), ['极限', '极限', '极限', '极限']);
});

test('retrieval status distinguishes hits, no match, unavailable storage and partial graph failure', () => {
  const { NoteEvidenceService } = loadEvidenceService();
  const service = new NoteEvidenceService();
  assert.match(service.formatRetrievalStatus(context([citation()])), /笔记检索：命中 1 条/);
  assert.match(service.formatRetrievalStatus({ ...context([]), reason: 'no-match' }), /未命中/);
  assert.match(service.formatRetrievalStatus({ ...context([]), degraded: true, reason: 'store-not-ready' }), /失败.*尚未就绪/);
  assert.match(service.formatRetrievalStatus({ ...context([]), degraded: true, reason: 'search-failed' }), /失败.*查询异常/);
  assert.match(service.formatRetrievalStatus({ ...context([citation()]), degraded: true, reason: 'graph-failed' }), /命中 1 条.*关系扩展/);
  assert.match(service.formatRetrievalStatus({ ...context([]), reason: 'empty-query' }), /未检索.*主题/);
});

test('topic normalization preserves mathematical symbols and words inside the topic', () => {
  const { NoteRetrievalQuery } = loadNoteReviewEtsModule('common/src/main/ets/utils/NoteRetrievalQuery.ets');
  for (const topic of ['阶乘 n!', 'f(x)=x^2', String.raw`\frac{1}{x}`, '机器学习的学习率', '能量守恒']) {
    assert.equal(NoteRetrievalQuery.normalize(topic), topic);
    assert.equal(NoteRetrievalQuery.normalize('请帮我解释一下' + topic + '？'), topic);
  }
  assert.equal(NoteRetrievalQuery.normalize('解释一下'), '');
  assert.equal(NoteRetrievalQuery.normalize('请解释一下这个'), '');
});

test('empty extracted topic never triggers a broad database query', async () => {
  const { NoteEvidenceService } = loadEvidenceService({ store: {}, registry: {
    execute() { assert.fail('empty topic must not query'); },
  } });
  const result = await new NoteEvidenceService().build('请解释一下');
  assert.equal(result.reason, 'empty-query');
  assert.equal(result.citations.length, 0);
});

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
    '[noteId=note-limit version=3 version=3]',
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



test('NoteEvidenceService keeps exact citations when stream arrives one character at a time', () => {
  const { NoteEvidenceService } = loadEvidenceService();
  const service = new NoteEvidenceService();
  const filter = service.createStreamFilter(
    context([citation({ noteId: 'note-limit', version: 3 })]),
  );

  let streamed = '';
  for (const char of '依据 [noteId=note-limit version=3]。') {
    streamed += filter.push(char);
  }
  streamed += filter.flush();

  assert.equal(streamed, '依据 [noteId=note-limit version=3]。');
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
  const noMatchHarness = makeService({ citations: [] });
  const noMatch = await noMatchHarness.service.build('我的极限笔记', { topK: 99, maxDepth: 99 });
  assert.equal(noMatch.reason, 'no-match');
  assert.equal(noMatch.degraded, false);
  assert.equal(noMatch.citations.length, 0);
  assert.equal(noMatch.topK, 10, 'topK 应被夹到上限');
  assert.equal(noMatchHarness.calls.search.length, 1);

  const failedHarness = makeService({ searchError: 'query failed' });
  const failed = await failedHarness.service.build('我的极限笔记');
  assert.equal(failed.reason, 'search-failed');
  assert.equal(failed.degraded, true);
  assert.equal(failed.citations.length, 0);
  assert.equal(failedHarness.calls.search.length, 1);
});

test('NoteEvidenceService bounds retrieval options and keeps direct hits when graph expansion fails', async () => {
  const hit = {
    noteId: 'note-limit',
    version: 3,
    title: '极限定义',
    excerpt: '极限摘录',
    role: 'hit',
    score: 0.9,
    matchedFields: ['title'],
    subject: '数学分析',
    chapter: '极限',
  };
  const { service, calls } = makeService({ citations: [hit], graphError: 'graph unavailable' });
  const result = await service.build('根据我的笔记解释极限', { topK: 99, maxDepth: 99 });

  assert.equal(calls.search[0].topK, 10, 'topK 应夹到上限');
  assert.equal(calls.graph[0].maxDepth, 2, 'maxDepth 应夹到上限');
  assert.equal(result.topK, 10);
  assert.equal(result.degraded, true);
  assert.equal(result.reason, 'graph-failed');
  assert.equal(result.citations.length, 1);
  assert.equal(result.citations[0].noteId, 'note-limit');
});

test('NoteEvidenceService follows incoming prerequisite direction and preserves edge endpoints', async () => {
  const derivative = {
    noteId: 'note-derivative',
    version: 2,
    title: '导数',
    excerpt: '导数摘录',
    role: 'hit',
    score: 0.9,
    matchedFields: ['title'],
    subject: '数学分析',
    chapter: '导数',
  };
  const prerequisiteEdge = {
    id: 'edge-limit-derivative',
    fromUnitId: 'note-limit',
    toUnitId: 'note-derivative',
    relationType: 'prerequisite',
    reason: '先掌握极限',
  };
  const { service, calls } = makeService({
    citations: [derivative],
    prerequisites: {
      nodes: [
        { unitId: 'note-derivative', depth: 0 },
        { unitId: 'note-limit', depth: 1 },
      ],
      edges: [prerequisiteEdge],
      truncated: false,
    },
    rows: [{
      id: 'note-limit',
      title: '极限',
      version: 4,
      subject: '数学分析',
      chapter: '极限',
      summary: '极限摘要',
      content: '极限内容',
    }],
  });
  const result = await service.build('导数', { graphMode: 'prerequisite-incoming' });

  assert.equal(calls.graph[0].mode, 'prerequisites', '应走前置方向而不是邻域');
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
