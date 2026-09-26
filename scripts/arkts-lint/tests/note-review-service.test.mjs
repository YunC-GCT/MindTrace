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

function evidence(citations, overrides = {}) {
  return {
    query: overrides.query ?? '极限',
    topK: overrides.topK ?? citations.length,
    citations,
    relations: overrides.relations ?? [],
    contextText: overrides.contextText ?? '证据上下文',
    degraded: overrides.degraded ?? false,
    reason: overrides.reason ?? '',
  };
}

function loadReviewService() {
  return loadNoteReviewEtsModule(
    'entry/src/main/ets/services/NoteReviewService.ets',
    {
      mocks: {
        'entry/src/main/ets/services/NoteEvidenceService.ets': {
          NoteEvidenceService: class NoteEvidenceService {},
          NoteEvidenceStreamFilter: class NoteEvidenceStreamFilter {},
        },
      },
    },
  );
}

function providerFor(responses) {
  const calls = [];
  const provider = {
    calls,
    async build(query, options) {
      calls.push({ query, options });
      const response = responses[query] ?? responses.default;
      return typeof response === 'function' ? response(query, options) : response;
    },
    formatSources(context) {
      return context.citations.map((item) => `[noteId=${item.noteId} version=${item.version}]`).join('\n');
    },
    sanitizeAnswerStrict(citations, answer) {
      const allowed = citations.map((item) => `${item.noteId}:${item.version}`);
      return answer.replace(/\[noteId=([^ ]+) version=([0-9]+)\]/g, (_full, noteId, version) => (
        allowed.includes(`${noteId}:${version}`) ? _full : '[未验证引用]'
      ));
    },
    createStrictStreamFilter() {
      return {};
    },
    hasVerifiedCitation(citations, answer) {
      return citations.some((item) => answer.includes(`[noteId=${item.noteId} version=${item.version}]`));
    },
  };
  return provider;
}

test('NoteReviewService classifies five review intents and excludes note generation', () => {
  const { NoteReviewService } = loadReviewService();
  const service = new NoteReviewService(providerFor({ default: evidence([]) }));

  assert.equal(service.classifyIntent('根据我的笔记解释极限'), 'explain');
  assert.equal(service.classifyIntent('比较笔记中的极限和连续'), 'compare');
  assert.equal(service.classifyIntent('学习导数前需要哪些前置知识'), 'prerequisite');
  assert.equal(service.classifyIntent('我的极限笔记在哪'), 'locate');
  assert.equal(service.classifyIntent('根据极限笔记出 5 道复习题'), 'quiz');
  assert.equal(service.classifyIntent('把极限整理成笔记并保存'), undefined);
  assert.equal(service.classifyIntent('这张怎么解释'), undefined);
  assert.equal(service.classifyIntent('你在哪里'), undefined);
});

test('NoteReviewService plans explain and quiz with bounded topic and question extraction', async () => {
  const provider = providerFor({
    极限: evidence([citation({ noteId: 'note-limit' })]),
  });
  const { NoteReviewService } = loadReviewService();
  const service = new NoteReviewService(provider);

  const explain = await service.plan('根据我的笔记解释极限');
  assert.equal(explain.kind, 'model');
  assert.equal(explain.answer.intent, 'explain');
  assert.equal(explain.answer.status, 'grounded');
  assert.equal(explain.answer.citations.length, 1);
  assert.match(explain.modelUserContent, /主题：极限/);
  assert.equal(provider.calls.length, 1);
  assert.equal(provider.calls[0].query, '极限');

  const quiz = await service.plan('根据极限笔记出 99 道复习题');
  assert.equal(quiz.kind, 'model');
  assert.equal(quiz.quizCount, 5);
  assert.match(quiz.modelUserContent, /生成 5 道复习题/);
});

test('NoteReviewService requires direct evidence for both compare topics', async () => {
  const provider = providerFor({
    极限: evidence([citation({ noteId: 'note-limit' })]),
    连续: evidence([]),
  });
  const { NoteReviewService } = loadReviewService();
  const service = new NoteReviewService(provider);

  const missing = await service.plan('比较笔记中的极限和连续');
  assert.equal(missing.kind, 'terminal');
  assert.equal(missing.answer.status, 'insufficient');
  assert.equal(missing.answer.reason, 'compare-topic-missing');
  assert.match(missing.displayText, /连续/);
  assert.equal(provider.calls.length, 2);
});

test('NoteReviewService follows prerequisite role and extracts the target topic without the direction suffix', async () => {
  const provider = providerFor({
    导数: evidence([
      citation({ noteId: 'note-derivative', role: 'hit' }),
      citation({ noteId: 'note-limit', role: 'prerequisite' }),
    ]),
    导数前: evidence([
      citation({ noteId: 'note-derivative', role: 'hit' }),
      citation({ noteId: 'note-limit', role: 'prerequisite' }),
    ]),
    default: evidence([]),
  });
  const { NoteReviewService } = loadReviewService();
  const service = new NoteReviewService(provider);

  const prerequisite = await service.plan('学习导数前需要哪些前置知识');
  assert.equal(prerequisite.kind, 'model');
  assert.equal(prerequisite.answer.intent, 'prerequisite');
  assert.equal(prerequisite.answer.citations[1].role, 'prerequisite');
  assert.equal(provider.calls[0].options.graphMode, 'prerequisite-incoming');
  assert.equal(provider.calls[0].query, '导数');
});

test('NoteReviewService rejects ambiguous pronoun-only requests with a clarification result', async () => {
  const provider = providerFor({ default: evidence([]) });
  const { NoteReviewService } = loadReviewService();
  const service = new NoteReviewService(provider);
  const ambiguous = await service.plan('这张怎么解释');
  assert.equal(ambiguous.kind, 'terminal');
  assert.equal(ambiguous.answer.status, 'insufficient');
  assert.equal(ambiguous.answer.reason, 'ambiguous-pronoun');
});

test('NoteReviewService distinguishes unavailable retrieval and no-match', async () => {
  const provider = providerFor({
    broken: evidence([], { degraded: true, reason: 'search-failed' }),
    empty: evidence([]),
  });
  const { NoteReviewService } = loadReviewService();
  const service = new NoteReviewService(provider);

  const unavailable = await service.plan('根据我的笔记解释 broken');
  assert.equal(unavailable.answer.status, 'unavailable');
  assert.equal(unavailable.answer.reason, 'search-failed');

  const noMatch = await service.plan('根据我的笔记解释 empty');
  assert.equal(noMatch.answer.status, 'insufficient');
  assert.equal(noMatch.answer.reason, 'no-match');
});

test('NoteReviewService converts provider exceptions into unavailable plans', async () => {
  const provider = {
    async build() {
      throw new Error('provider failed');
    },
    formatSources() {
      return '';
    },
    sanitizeAnswerStrict() {
      return '';
    },
    createStrictStreamFilter() {
      return {};
    },
    hasVerifiedCitation() {
      return false;
    },
  };
  const { NoteReviewService } = loadReviewService();
  const service = new NoteReviewService(provider);

  const result = await service.plan('根据我的笔记解释极限');
  assert.equal(result.answer.status, 'unavailable');
  assert.equal(result.answer.reason, 'evidence-provider-failed');
});

test('NoteReviewService finalization requires an exact allowed citation and marks model failure unavailable', async () => {
  const provider = providerFor({
    极限: evidence([citation({ noteId: 'note-limit', version: 3 })]),
  });
  const { NoteReviewService } = loadReviewService();
  const service = new NoteReviewService(provider);
  const plan = await service.plan('根据我的笔记解释极限');

  const valid = service.finalizeModelAnswer(
    plan,
    '极限是趋近过程。[noteId=note-limit version=3]',
  );
  assert.equal(valid.answer.status, 'grounded');
  assert.equal(valid.answer.citations.length, 1);

  const wrongVersion = service.finalizeModelAnswer(
    plan,
    '极限是趋近过程。[noteId=note-limit version=4]',
  );
  assert.equal(wrongVersion.answer.status, 'insufficient');
  assert.equal(wrongVersion.answer.reason, 'model-missing-valid-citation');

  const failed = service.fallbackFailure(plan, 'model-timeout');
  assert.equal(failed.answer.status, 'unavailable');
  assert.equal(failed.answer.reason, 'model-timeout');
  assert.equal(failed.answer.citations.length, 0);
});
