// 路径: scripts/arkts-lint/tests/rag-ranking.test.mjs
// 职责: 044 R3 契约——多词融合排序：命中词数加成、单词行为兼容、稳定排序。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const mod = loadNoteReviewEtsModule('common/src/main/ets/ports/impl/NoteSearchRanking.ets');
const { rankNoteHits, rankNoteHitsByTerms, RAG_DISTINCT_TERM_BONUS } = mod;

function row(overrides) {
  return Object.assign({
    noteId: 'n1',
    title: '',
    version: 1,
    subject: '数学',
    chapter: '',
    tags: '[]',
    summary: '',
    content: '',
    updatedAt: 100,
    score: 0,
    matchedFields: [],
    excerpt: '',
  }, overrides);
}

test('命中两个词的长标题排在只命中一个泛词的正文前面', () => {
  const rows = [
    row({ noteId: 'a', title: '9+9 的加法计算', content: '', updatedAt: 100 }),
    row({ noteId: 'b', title: '无关标题', content: '计算 '.repeat(6), updatedAt: 200 }),
  ];
  const ranked = Array.from(rankNoteHitsByTerms(rows, ['9+9', '加法计算'], 5));
  assert.equal(ranked[0].noteId, 'a');
});

test('命中词数加成按 distinct-1 计', () => {
  const rows = [row({ noteId: 'a', content: '加法计算' })];
  const ranked = Array.from(rankNoteHitsByTerms(rows, ['加法', '计算'], 5));
  // 「加法」「计算」各在正文命中 1 次：1+1，再加重叠 1 个词 * BONUS
  assert.equal(ranked[0].score, 2 + (2 - 1) * RAG_DISTINCT_TERM_BONUS);
});

test('单词调用与 rankNoteHits 打分一致', () => {
  const rows = [row({ noteId: 'a', title: '一加一等于二', content: '一加一' })];
  const single = Array.from(rankNoteHitsByTerms(rows, ['一加一'], 5));
  const legacy = Array.from(rankNoteHits(rows, '一加一', 5));
  assert.equal(single[0].score, legacy[0].score);
});

test('无命中返回空列表', () => {
  const rows = [row({ noteId: 'a', content: '完全无关' })];
  assert.equal(Array.from(rankNoteHitsByTerms(rows, ['勾股定理'], 5)).length, 0);
});

test('同分按更新时间降序，保证排序稳定', () => {
  const rows = [
    row({ noteId: 'old', content: '加法', updatedAt: 100 }),
    row({ noteId: 'new', content: '加法', updatedAt: 200 }),
  ];
  const ranked = Array.from(rankNoteHitsByTerms(rows, ['加法'], 5));
  assert.equal(ranked[0].noteId, 'new');
});

test('词表大小写与重复项归一', () => {
  const rows = [row({ noteId: 'a', title: 'Limit 定义' })];
  const ranked = Array.from(rankNoteHitsByTerms(rows, ['limit', 'LIMIT', ' limit '], 5));
  assert.equal(ranked.length, 1);
  assert.equal(ranked[0].score, 4);
});
