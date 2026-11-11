// #238 / ADR-0021：NoteSearchPort 的纯打分与摘录契约测试。
// 只装载纯函数（无 Kit、无 IO），验证与既有 note_query_rag 一致的口径。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const ranking = loadNoteReviewEtsModule('common/src/main/ets/ports/impl/NoteSearchRanking.ets');
const { rankNoteHits, buildExcerpt, countOccurrences } = ranking;

function candidate(noteId, overrides = {}) {
  return {
    noteId,
    title: 'title',
    version: 1,
    subject: '数学',
    chapter: '极限',
    tags: '[]',
    summary: '',
    content: '',
    updatedAt: 1,
    score: 0,
    matchedFields: [],
    excerpt: '',
    ...overrides,
  };
}

test('rankNoteHits weights title above tags above summary above content', () => {
  const rows = [
    candidate('content-hit', { content: 'limit' }),
    candidate('summary-hit', { summary: 'limit' }),
    candidate('tag-hit', { tags: '["limit"]' }),
    candidate('title-hit', { title: 'limit' }),
  ];
  const ranked = rankNoteHits(rows, 'limit', 10);
  assert.deepEqual(Array.from(ranked).map((hit) => hit.noteId),
    ['title-hit', 'tag-hit', 'summary-hit', 'content-hit']);
  assert.equal(ranked[0].score, 4);
  assert.equal(ranked[1].score, 3);
  assert.equal(ranked[2].score, 2);
  assert.equal(ranked[3].score, 1);
});

test('rankNoteHits drops candidates with no hit at all', () => {
  const rows = [candidate('miss', { content: 'nothing here' })];
  assert.equal(rankNoteHits(rows, 'limit', 10).length, 0);
});

test('rankNoteHits breaks ties by updatedAt desc then noteId asc', () => {
  const rows = [
    candidate('b', { content: 'limit', updatedAt: 5 }),
    candidate('a', { content: 'limit', updatedAt: 5 }),
    candidate('newer', { content: 'limit', updatedAt: 9 }),
  ];
  const ranked = rankNoteHits(rows, 'limit', 10);
  assert.deepEqual(Array.from(ranked).map((hit) => hit.noteId), ['newer', 'a', 'b']);
});

test('rankNoteHits truncates to topK', () => {
  const rows = [
    candidate('a', { content: 'limit' }),
    candidate('b', { content: 'limit' }),
    candidate('c', { content: 'limit' }),
  ];
  assert.deepEqual(Array.from(rankNoteHits(rows, 'limit', 2)).map((hit) => hit.noteId), ['a', 'b']);
});

test('rankNoteHits records which fields matched', () => {
  const rows = [candidate('multi', { title: 'limit', content: 'limit again', tags: '["limit"]' })];
  const ranked = rankNoteHits(rows, 'limit', 10);
  assert.deepEqual(Array.from(ranked[0].matchedFields), ['title', 'tags', 'content']);
});

test('countOccurrences counts non-overlapping matches only', () => {
  assert.equal(countOccurrences('aaaa', 'aa'), 2);
  assert.equal(countOccurrences('abc', 'z'), 0);
  assert.equal(countOccurrences('abc', ''), 0);
});

test('buildExcerpt centres the window on the hit and marks truncation', () => {
  const content = 'x'.repeat(200) + 'limit' + 'y'.repeat(200);
  const excerpt = buildExcerpt(content, '', 'limit');
  assert.ok(excerpt.startsWith('…'), 'truncated head must be marked');
  assert.ok(excerpt.endsWith('…'), 'truncated tail must be marked');
  assert.ok(excerpt.includes('limit'), 'the hit must stay inside the excerpt');
});

test('buildExcerpt falls back to summary when content is empty', () => {
  const excerpt = buildExcerpt('', 'summary with limit inside', 'limit');
  assert.equal(excerpt, 'summary with limit inside');
});
