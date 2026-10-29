// 路径: scripts/arkts-lint/tests/v7-knowledge-taxonomy.test.mjs
// 职责: 学科归一 + 标题去复核标记的契约测试（装载真实 .ets，不复制实现）。
// Why: 同一门课被写成三种学科、复核提示长在标题上，都会直接暴露给用户；
//      这两件事必须是确定性的纯函数，不能靠 prompt 祈祷。

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const mod = loadNoteReviewEtsModule('agents/src/main/ets/agents/KnowledgeTaxonomy.ets');
const normalizeSubjectName = mod.normalizeSubjectName;
const sanitizeNoteTitle = mod.sanitizeNoteTitle;
const resolveSubjectName = mod.resolveSubjectName;

test('subject aliases collapse into one canonical name', () => {
  const cases = [
    ['最优化', '最优化方法'],
    ['最优化理论', '最优化方法'],
    ['运筹学', '最优化方法'],
    ['数学（优化理论/运筹学）', '最优化方法'],
    ['概率论与数理统计', '概率论'],
    ['线代', '线性代数'],
    ['线性代数（矩阵）', '线性代数'],
    ['高数', '高等数学'],
    ['数值计算方法', '数值分析'],
    ['初中数学', '初中数学'],
  ];
  for (const [raw, expected] of cases) {
    const result = normalizeSubjectName(raw);
    assert.equal(result.subject, expected, `subject of ${raw}`);
  }
});

test('subject resolution reuses what is already in the library', () => {
  const known = ['数学分析', '线性代数', '最优化方法', '初中数学'];
  // loader 产出的对象原型不同，逐字段断言
  const optimisation = resolveSubjectName('最优化', known);
  assert.equal(optimisation.subject, '最优化方法');
  assert.equal(optimisation.decision, 'canonical');
  const continued = resolveSubjectName('高等数学（下）', ['高等数学']);
  assert.equal(continued.subject, '高等数学');
  // 内置学科表里就有「高等数学」，所以走 canonical；库里自建学科才走 existing
  assert.equal(continued.decision, 'canonical');
  const custom = resolveSubjectName('数据结构（树）', ['数据结构', '数学分析']);
  assert.equal(custom.subject, '数据结构');
  assert.equal(custom.decision, 'existing');
  const linear = resolveSubjectName('线性代数', known);
  assert.equal(linear.subject, '线性代数');
  assert.equal(linear.decision, 'canonical');
});

test('a genuinely new subject is marked new and gets candidates to pick from', () => {
  const known = ['数学分析', '线性代数', '最优化方法'];
  const fresh = resolveSubjectName('数据结构与算法', known);
  assert.equal(fresh.decision, 'new');
  assert.equal(fresh.subject, '数据结构与算法');
  const near = resolveSubjectName('最优化理论选讲', known);
  assert.equal(near.decision, 'canonical');
});

test('a canonical subject is left untouched and reported as unchanged', () => {
  const result = normalizeSubjectName('数学分析');
  assert.equal(result.subject, '数学分析');
  assert.equal(result.changed, false);
});

test('an unknown subject is kept, never invented', () => {
  const result = normalizeSubjectName('数据结构与算法');
  assert.equal(result.subject, '数据结构与算法');
  assert.equal(result.changed, false);
});

test('an empty subject falls back to the classifier hint', () => {
  assert.equal(normalizeSubjectName('', '线性代数').subject, '线性代数');
  assert.equal(normalizeSubjectName('未知', '线性代数').subject, '线性代数');
});

test('review markers are stripped out of titles', () => {
  const cases = [
    ['系数矩阵的 LL 分解（OCR 信息不完整）', '系数矩阵的 LL 分解'],
    ['优化理论试卷第二至七题摘要（含OCR待核对项）', '优化理论试卷第二至七题摘要'],
    ['二次规划解与 Lagrange 乘子证明及乘子法算例（含待确认）', '二次规划解与 Lagrange 乘子证明及乘子法算例'],
    ['矩阵算子范数(ocr pending)', '矩阵算子范数'],
    ['无约束优化算法（OCR 信息不完整', '无约束优化算法'],
    ['线性多步法的 A 稳定性判定（隐式公式无法识别项）', '线性多步法的 A 稳定性判定'],
  ];
  for (const [raw, expected] of cases) {
    const result = sanitizeNoteTitle(raw);
    assert.equal(result.title, expected, `title of ${raw}`);
    assert.ok(result.stripped.length >= 1, `stripped markers of ${raw}`);
  }
});

test('ordinary parentheses survive: scores, years and formulas', () => {
  const cases = [
    '求 f(x) 在 x=1 处的导数（10 分）',
    '2024 年数学分析期末试题（A 卷）',
    '计算二重积分（先 y 后 x）',
  ];
  for (const raw of cases) {
    const result = sanitizeNoteTitle(raw);
    assert.equal(result.title, raw);
    assert.equal(result.stripped.length, 0);
  }
});

test('a title made only of markers becomes empty so the caller can fall back', () => {
  const result = sanitizeNoteTitle('（OCR 信息不完整）');
  assert.equal(result.title, '');
  assert.equal(result.stripped.length, 1);
});

test('trailing separators left behind by a stripped marker are cleaned', () => {
  const result = sanitizeNoteTitle('泰勒展开与余项 · （含待确认）');
  assert.equal(result.title, '泰勒展开与余项');
});
