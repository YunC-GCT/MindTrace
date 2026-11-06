// 路径: scripts/arkts-lint/tests/rag-eval.test.mjs
// 职责: 044 R5 契约——评测集结构合法，且每条正样本至少有一个关键词能落到期望标题里
//       （防止评测集本身写错，导致评测结果无法解释）。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const evalModule = loadNoteReviewEtsModule('entry/src/main/ets/debug/RagEvalCases.ets');
const termsModule = loadNoteReviewEtsModule('common/src/main/ets/utils/QueryTerms.ets');
const { RAG_EVAL_CASES } = evalModule;
const { planQueryTerms } = termsModule;

test('评测集规模与非空约束', () => {
  const positives = RAG_EVAL_CASES.filter((item) => item.expectTitle.length > 0);
  const negatives = RAG_EVAL_CASES.filter((item) => item.expectTitle.length === 0);
  assert.ok(positives.length >= 10, '至少 10 条正样本');
  assert.ok(negatives.length >= 1, '至少 1 条负样本');
});

test('查询不重复', () => {
  const seen = new Set();
  for (const item of RAG_EVAL_CASES) {
    assert.equal(seen.has(item.query), false, '重复查询: ' + item.query);
    seen.add(item.query);
  }
});

test('精确查询至少有一个关键词能落到期望标题里', () => {
  for (const item of RAG_EVAL_CASES) {
    if (item.kind !== 'exact') {
      continue;
    }
    const terms = Array.from(planQueryTerms(item.query).terms);
    assert.ok(terms.length > 0, '关键词为空: ' + item.query);
    const reachable = terms.some((term) =>
      item.expectTitle.includes(term) || term.includes(item.expectTitle));
    assert.ok(reachable, '关键词与标题无交集: ' + item.query + ' -> ' + terms.join('|'));
  }
});

test('同义改写组：数量足够且都能拆出关键词', () => {
  const paraphrase = RAG_EVAL_CASES.filter((item) => item.kind === 'paraphrase');
  assert.ok(paraphrase.length >= 10, '至少 10 条同义改写样本');
  for (const item of paraphrase) {
    assert.ok(item.expectTitle.length > 0, '改写样本必须声明期望标题: ' + item.query);
    assert.ok(Array.from(planQueryTerms(item.query).terms).length > 0,
      '拆不出关键词: ' + item.query);
  }
});

test('用例类型齐全：改写 / 精确 / 负样本', () => {
  const kinds = new Set(RAG_EVAL_CASES.map((item) => item.kind));
  assert.ok(kinds.has('paraphrase') && kinds.has('exact') && kinds.has('negative'));
  for (const item of RAG_EVAL_CASES) {
    if (item.kind === 'negative') {
      assert.equal(item.expectTitle, '', '负样本不声明期望标题: ' + item.query);
    }
  }
});

test('负样本不声明期望标题', () => {
  const negative = RAG_EVAL_CASES.find((item) => item.query === '今天天气怎么样');
  assert.ok(negative !== undefined, '保留一条闲聊负样本');
  assert.equal(negative.expectTitle, '');
});
