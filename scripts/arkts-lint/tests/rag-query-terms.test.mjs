// 路径: scripts/arkts-lint/tests/rag-query-terms.test.mjs
// 职责: 044 R1 契约——查询归一与关键词拆分：疑问词剥离、数学片段保留、去重与上限。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const mod = loadNoteReviewEtsModule('common/src/main/ets/utils/QueryTerms.ets');
const { planQueryTerms, normalizeQueryText } = mod;

test('口语疑问尾巴被剥离，留下主题词', () => {
  const plan = planQueryTerms('一加一等于几');
  assert.equal(plan.normalized, '一加一');
  assert.deepEqual(Array.from(plan.terms), ['一加一']);
});

test('带「的」和「怎么算」的长句拆成两个关键词', () => {
  const plan = planQueryTerms('9+9 的加法计算怎么算');
  assert.deepEqual(Array.from(plan.terms), ['加法计算', '9+9']);
});

test('「什么是」由既有边界清洗处理', () => {
  const plan = planQueryTerms('什么是导数');
  assert.deepEqual(Array.from(plan.terms), ['导数']);
});

test('句首请求用语与句尾问法一起剥离', () => {
  const plan = planQueryTerms('请问函数在一点连续是什么意思');
  assert.deepEqual(Array.from(plan.terms), ['函数在一点连续']);
});

test('全角字符归一为半角', () => {
  assert.equal(normalizeQueryText('９＋９　的加法计算'), '9+9 的加法计算');
  const plan = planQueryTerms('９＋９ 的加法计算');
  assert.deepEqual(Array.from(plan.terms), ['加法计算', '9+9']);
});

test('数学表达式不被拆分', () => {
  const plan = planQueryTerms('x^2+2x+1=0 怎么解');
  assert.deepEqual(Array.from(plan.terms), ['x^2+2x+1=0']);
});

test('关键词去重且最多三个，按长度降序', () => {
  const plan = planQueryTerms('极限 极限 连续 导数 积分');
  assert.equal(plan.terms.length, 3);
  assert.equal(new Set(Array.from(plan.terms)).size, plan.terms.length);
  for (let i = 1; i < plan.terms.length; i += 1) {
    assert.ok(plan.terms[i - 1].length >= plan.terms[i].length, '按长度降序');
  }
});

test('「的」作为分隔符拆出两个主题词', () => {
  const plan = planQueryTerms('导数的定义');
  assert.deepEqual(Array.from(plan.terms), ['导数', '定义']);
});

test('并列词分隔后保留长词，丢弃单字噪声', () => {
  const plan = planQueryTerms('矩阵的秩和初等变换');
  assert.deepEqual(Array.from(plan.terms), ['初等变换', '矩阵']);
});

test('长词与短词混合时都保留，供短词兜底', () => {
  const plan = planQueryTerms('数列极限的定义');
  assert.deepEqual(Array.from(plan.terms), ['数列极限', '定义']);
});

test('空输入得到空词表；纯停用词回退整句', () => {
  assert.deepEqual(Array.from(planQueryTerms('   ').terms), []);
  const plan = planQueryTerms('的');
  assert.deepEqual(Array.from(plan.terms), ['的']);
});
