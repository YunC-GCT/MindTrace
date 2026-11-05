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

test('命中词数加成：命中两个词的分数高于只命中一个词', () => {
  const rows = [row({ noteId: 'a', content: '加法计算' })];
  const two = Array.from(rankNoteHitsByTerms(rows, ['加法', '计算'], 5));
  const one = Array.from(rankNoteHitsByTerms([row({ noteId: 'a', content: '加法计算' })], ['加法'], 5));
  assert.ok(two[0].score > one[0].score);
});

test('旧笔记靠标题命中可以压过新笔记的正文命中', () => {
  const rows = [
    row({ noteId: 'old', title: '导数定义', updatedAt: 100 }),
    row({ noteId: 'new', content: '导数 '.repeat(5), updatedAt: 200 }),
  ];
  const ranked = Array.from(rankNoteHitsByTerms(rows, ['导数'], 5));
  assert.equal(ranked[0].noteId, 'old');
});

test('单词命中走 token 覆盖度，分数为正', () => {
  const rows = [row({ noteId: 'a', title: '一加一等于二', content: '一加一' })];
  const ranked = Array.from(rankNoteHitsByTerms(rows, ['一加一'], 5));
  assert.equal(ranked.length, 1);
  assert.ok(ranked[0].score > 0);
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
  assert.ok(ranked[0].score > 0);
});
