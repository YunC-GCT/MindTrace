// 路径: scripts/arkts-lint/tests/v7-note-quality.test.mjs
// 职责: 笔记质量三件事的契约——学科收敛、结构化标准字段、写前重复检测。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

const sections = loadNoteReviewEtsModule('agents/src/main/ets/agents/StructuredSections.ets');
const dedupe = loadNoteReviewEtsModule('entry/src/main/ets/services/NoteDedupe.ets');
const taxonomy = loadNoteReviewEtsModule('agents/src/main/ets/agents/KnowledgeTaxonomy.ets');
const arr = (value) => Array.from(value);

test('五类笔记标准字段：缺字段能被检出（表单内容纰漏）', () => {
  const labels = arr(sections.requiredSectionLabels('计算题'));
  assert.deepEqual(labels, ['问题', '步骤', '答案', '方法总结', '常见错误']);
  const fields = [
    { key: 'problem', label: '问题', value: '求方程的解' },
    { key: 'steps', label: '步骤', value: '移项后求解' },
  ];
  const missing = arr(sections.missingSectionLabels('计算题', fields));
  assert.deepEqual(missing, ['答案', '方法总结', '常见错误']);
});

test('同义词规范化：陈述/定理内容、答案解析等标签对齐标准表单', () => {
  assert.equal(sections.canonicalSectionLabel('定理', 'statement', '定理内容'), '陈述');
  assert.equal(sections.canonicalSectionLabel('定理', 'cond', '前提'), '条件');
  assert.equal(sections.canonicalSectionLabel('计算题', 'ans', '答案解析'), '答案');
  assert.equal(sections.canonicalSectionLabel('计算题', 'x', '无关字段'), '');
});

test('规范化输出：标准字段按顺序、占位值丢弃', () => {
  const fields = [
    { key: 'b', label: '答案', value: '9' },
    { key: 'a', label: '问题', value: '求 f(2)' },
    { key: 'c', label: '步骤', value: '无' },
    { key: 'd', label: '自定义', value: '补充内容' },
  ];
  const normalized = arr(sections.normalizeStructuredFields('计算题', fields));
  assert.deepEqual(normalized.slice(0, 2).map((f) => f.label), ['问题', '答案']);
  assert.equal(normalized[2].label, '自定义');
  assert.ok(normalized.every((f) => f.value !== '无'));
});

test('学科收敛：别名归一且未知学科不再新建', () => {
  assert.equal(taxonomy.normalizeSubjectName('数学（优化理论）').subject, '最优化方法');
  assert.equal(taxonomy.normalizeSubjectName('高等数学（下）').subject, '高等数学');
  assert.equal(taxonomy.normalizeSubjectName('数学').subject, '其他');
  const resolution = taxonomy.resolveSubjectName('量子数学', []);
  assert.equal(resolution.decision, 'new');
  const structurer = read('agents/src/main/ets/agents/CaptureStructurer.ets');
  assert.match(structurer, /resolution\.decision === 'new'/);
  assert.match(structurer, /return KNOWLEDGE_FALLBACK_SUBJECT/);
  assert.match(structurer, /missingSectionLabels\(normalizedCategory/);
  assert.match(structurer, /软校验/, '缺字段降级为告警');
  assert.match(structurer, /standardMatched === 0/, '完全没有标准字段才重试');
});

test('重复检测：同题不同措辞判重，不同题不误杀', () => {
  const title = '解一元二次方程 x^2-5x+6=0';
  const content = '## 问题\n求方程 x^2-5x+6=0 的解\n## 步骤\n因式分解 (x-2)(x-3)=0\n## 答案\nx=2 或 x=3';
  const same = {
    id: 'a',
    title: '解一元二次方程 x²-5x+6=0',
    content: '## 问题\n求方程 x^2-5x+6=0 的解\n## 步骤\n因式分解 (x-2)(x-3)=0\n## 答案\nx=2 或 x=3',
  };
  const different = {
    id: 'b',
    title: '洛必达法则求极限',
    content: '## 问题\n用洛必达法则求极限\n## 步骤\n0/0 型直接求导',
  };
  assert.equal(dedupe.isDuplicateOf(title, content, same), true);
  assert.equal(dedupe.isDuplicateOf(title, content, different), false);
  assert.equal(dedupe.findDuplicate(title, content, [different, same]).id, 'a');
});

test('写入口查重接线：服务层跳过重复、DAO 提供候选查询', () => {
  const service = read('entry/src/main/ets/services/KnowledgeUnitWriteService.ets');
  assert.match(service, /private async findDuplicate\(unit: KnowledgeUnit\)/);
  assert.match(service, /DUPLICATE_SKIPPED/);
  assert.ok((service.match(/if \(duplicate !== null\)/g) ?? []).length >= 2, 'create 与 createWithCommitKey 都要查重');
  const dao = read('entry/src/main/ets/database/NoteDao.ets');
  assert.match(dao, /async findDuplicate\(unit: KnowledgeUnit\): Promise<KnowledgeUnit \| null>/);
  assert.match(dao, /queryRecentDedupeCandidates\(120\)/);
});
