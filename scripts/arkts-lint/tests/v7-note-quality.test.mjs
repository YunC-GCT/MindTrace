// 路径: scripts/arkts-lint/tests/v7-note-quality.test.mjs
// 职责: 笔记质量三件事的契约——学科收敛、结构化标准字段、写前重复检测。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

const sections = loadNoteReviewEtsModule('agents/src/main/ets/subagents/StructuredSections.ets');
const dedupe = loadNoteReviewEtsModule('agents/src/main/ets/note/NoteDedupe.ets');
const taxonomy = loadNoteReviewEtsModule('agents/src/main/ets/subagents/KnowledgeTaxonomy.ets');
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
  const structurer = read('agents/src/main/ets/subagents/CaptureStructurer.ets');
  assert.match(structurer, /resolution\.decision === 'new'/);
  assert.match(structurer, /return KNOWLEDGE_FALLBACK_SUBJECT/);
  assert.match(structurer, /missingSectionLabels\(normalizedCategory/);
  assert.match(structurer, /软校验/, '缺字段降级为告警');
  assert.match(structurer, /standardMatched === 0/, '完全没有标准字段才重试');
});

test('结构助词归一：只差「的」的同一标题判重', () => {
  const content = '泰勒公式的余项分为佩亚诺余项与拉格朗日余项，用于误差估计。';
  const candidate = {
    id: 't',
    title: '泰勒公式的余项估计',
    content: '泰勒公式的余项分为佩亚诺余项与拉格朗日余项，用于误差估计与不等式证明。',
  };
  assert.equal(dedupe.isDuplicateOf('泰勒公式余项估计', content, candidate), true);
});

test('主题包含：短标题被完整包含且正文实质重合时判重', () => {
  const content = '泰勒公式余项包括佩亚诺余项和拉格朗日余项。';
  const candidate = {
    id: 'c',
    title: '泰勒公式余项估计',
    content: '泰勒公式余项包括佩亚诺余项和拉格朗日余项，可用于误差估计。',
  };
  assert.equal(dedupe.isDuplicateOf('泰勒公式余项', content, candidate), true);
});

test('连续相似度：同标题/同签名为高分，无关题低分，泛化题落灰区', () => {
  const sameTitle = dedupe.similarityScore(
    '计算 21 加 21', '任意正文',
    '计算 21 加 21', '另一种正文',
  );
  assert.equal(sameTitle, 1);
  const sameSignature = dedupe.similarityScore(
    '两个 21 的和', '求两个 21 相加',
    '计算 21 加 21', '21+21=42',
  );
  assert.equal(sameSignature, 0.95);
  const unrelated = dedupe.similarityScore(
    '洛必达法则求极限', '0/0 型求导',
    '矩阵的秩与初等变换', '行阶梯形非零行数',
  );
  assert.ok(unrelated < dedupe.SIMILARITY_GRAY_MIN);
  const gray = dedupe.similarityScore(
    '极限的定义', '函数极限的 epsilon-delta 定义。',
    '极限定义是什么', '用 epsilon-delta 语言描述函数极限。',
  );
  assert.ok(gray >= dedupe.SIMILARITY_GRAY_MIN && gray < dedupe.SIMILARITY_HARD_DUPLICATE);
});

test('灰区仲裁接线：写入服务注入 judge、DAO 提供候选', () => {
  const service = read('entry/src/main/ets/services/KnowledgeUnitWriteService.ets');
  assert.match(service, /NoteSimilarityJudgePort/);
  assert.match(service, /similarityScore\(unit\.title, unit\.content/);
  assert.match(service, /SIMILARITY_GRAY_MIN/);
  assert.match(service, /isSameNote\(unit\.title, unit\.content/);
  const dao = read('entry/src/main/ets/database/NoteDao.ets');
  assert.match(dao, /async findSimilarCandidates\(unit: KnowledgeUnit\)/);
  const factory = read('entry/src/main/ets/services/KnowledgeUnitWriteServiceFactory.ets');
  assert.match(factory, /new LlmNoteSimilarityJudge\(\)/);
  const judge = read('entry/src/main/ets/services/LlmNoteSimilarityJudge.ets');
  assert.match(judge, /implements NoteSimilarityJudgePort/);
  assert.match(judge, /只输出 YES 或 NO/);
});

test('数学签名判重：算式与文字表述是同一道题', () => {
  const candidate = {
    id: 's',
    title: '计算 21 加 21 的结果并写出运算步骤',
    content: '## 问题\n计算 21+21\n## 答案\n42',
  };
  assert.equal(
    dedupe.isDuplicateOf('两个 21 的和是多少', '求两个 21 相加的结果，答案是 42。', candidate),
    true,
  );
});

test('标题归一相同（≥6 字）即判重，正文措辞不同也算', () => {
  const candidate = {
    id: 't',
    title: '计算 21 加 21',
    content: '## 问题\n求两个 21 的和\n## 步骤\n21+21=42\n## 答案\n42',
  };
  assert.equal(
    dedupe.isDuplicateOf('计算 21 加 21', '另一种讲法：把两个 21 相加，结果是 42。', candidate),
    true,
  );
});

test('中文数字归一：80 加 80 与 八十加八十 判重，不同数字不误杀', () => {
  assert.equal(dedupe.cnNumeralToArabic('八十'), '80');
  assert.equal(dedupe.cnNumeralToArabic('二十一'), '21');
  assert.equal(dedupe.cnNumeralToArabic('一百零五'), '105');
  const candidate = {
    id: 'a',
    title: '计算 80 加 80 的结果并写出步骤',
    content: '## 问题\n计算 80+80\n## 答案\n160',
  };
  assert.equal(
    dedupe.isDuplicateOf('计算八十加八十并写出运算步骤', '## 问题\n求八十加八十\n## 答案\n一百六十', candidate),
    true,
  );
  const different = {
    id: 'b',
    title: '计算 21 加 21 的结果并写出步骤',
    content: '## 问题\n计算 21+21\n## 答案\n42',
  };
  assert.equal(
    dedupe.isDuplicateOf('计算八十加八十并写出运算步骤', '## 问题\n求八十加八十\n## 答案\n一百六十', different),
    false,
  );
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
  assert.match(dao, /'signature': extractMathSignature\(unit\.title\)/);
  assert.match(dao, /queryRecentDedupeCandidates\(500\)/);
});


test('P0-2/P0-3 探针与报告接线：阶段耗时日志 + 去重/延迟/质量审计', () => {
  const pipeline = read('entry/src/main/ets/services/ai/CapturePipeline.ets');
  assert.match(pipeline, /CAPTURE_STAGE step=/);
  assert.match(pipeline, /CAPTURE_TOTAL kind=/);
  const runner = [
    read('entry/src/main/ets/debug/DebugCaptureRunner.ets'),
    read('entry/src/main/ets/debug/DebugSchedulerProbes.ets'),
    read('entry/src/main/ets/debug/DebugAgentProbes.ets'),
  ].join('\n');
  assert.match(runner, /static async runDedupeProbe\(/);
  assert.match(runner, /static async runDedupeSimilarityProbe\(/);
  assert.match(runner, /static async runLatencyProbe\(/);
  const entry = read('entry/src/main/ets/entryability/EntryAbility.ets');
  assert.match(entry, /mode === 'dedupeProbe'/);
  assert.match(entry, /mode === 'dedupeSimilarityProbe'/);
  assert.match(entry, /mode === 'latencyProbe'/);
  const audit = read('scripts/quality/note-quality-audit.mjs');
  assert.match(audit, /MAX_DUPLICATE_RATIO/);
  assert.match(audit, /fieldFilledRatio/);
  assert.match(audit, /--assert/);
});


test('输入指纹幂等：同一原文重复整理复用已有笔记（P0-3）', () => {
  const pipeline = read('entry/src/main/ets/services/ai/CapturePipeline.ets');
  assert.match(pipeline, /static captureInputCommitKey\(text: string\): string/);
  assert.match(pipeline, /capture-input:' \+ sourceFingerprint\(normalizeForDedupe\(text\)\)/);
  assert.match(pipeline, /findCommittedByInput\(/);
  assert.match(pipeline, /rememberCommittedInput\(/);
  const dao = read('agents/src/main/ets/models/NoteDaoInterface.ets');
  assert.match(dao, /queryById\?\(id: string\)/);
});


test('快速路由：文字整理跳过分类 LLM（structure 自分类）', () => {
  const options = read('agents/src/main/ets/core/dispatch/DispatchOptions.ets');
  assert.ok(options.includes('skipLlmClassification?: boolean'));
  const classify = read('agents/src/main/ets/graph/nodes/ClassifyNode.ets');
  assert.ok(classify.includes('input.skipClassification === true'));
  const structure = read('agents/src/main/ets/graph/nodes/StructureNode.ets');
  assert.ok(structure.includes('input.skipClassification === true'));
  const structurer = read('agents/src/main/ets/subagents/CaptureStructurer.ets');
  assert.ok(structurer.includes('skipClassifierHint: boolean = false'));
  assert.ok(structurer.includes('this.buildExternalHint(ocrText, type, subject, chapter)'));
  const pipeline = read('entry/src/main/ets/services/ai/CapturePipeline.ets');
  assert.ok(pipeline.includes('this.processAndPersistOutcome(payload, undefined, true)'));
});
