import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import ts from 'typescript';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');

const tcs = read('agents/src/main/ets/agents/TruthCheckService.ets');
const km = read('agents/src/main/ets/agents/KnowledgeModel.ets');
const tcsTestPath = resolve(root, 'agents/src/test/TruthCheckService.test.ets');

// Execute production service, node, graph and dispatcher, not a mirror of their rules.
const runtimeSources = [
  'common/src/main/ets/workflow/StateGraph.ets',
  'agents/src/main/ets/graph/AgentState.ets',
  'agents/src/main/ets/agents/TruthCheckService.ets',
  'agents/src/main/ets/graph/nodes/TruthCheckNode.ets',
  'agents/src/main/ets/graph/CaptureGraph.ets',
  'agents/src/main/ets/core/Dispatcher.ets',
].map((path) => read(path).replace(/^import[\s\S]*?;\r?\n/gm, '')).join('\n');
const compiled = ts.transpileModule('class Logger {}\n' + runtimeSources, {
  compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ES2022 },
}).outputText;
const { TruthCheckService, TruthCheckNodeFactory, Dispatcher } = await import(
  'data:text/javascript;base64,' + Buffer.from(compiled).toString('base64')
);

test('valid mathematics and contextual contradictions are not local hard failures', () => {
  const service = new TruthCheckService();
  for (const text of ['x=x', 'x ≠ 0', '10=10', '1/0.5=2',
    '反证得到 1=0，故假设不成立。', '1/0 无定义，不能这样计算。',
    String.raw`$x \rightarrow 0$`, String.raw`\left\{x\right.`,
    String.raw`\begin{align*}x&=1\end{align*}`,
    String.raw`$\int_{0}^{1} f(x)\,\mathrm{d}x$`]) {
    assert.equal(service.check(text).truthFlag, true, text);
    assert.equal(service.check(text).correctedText, undefined, text);
  }
});

test('local gate still rejects empty input, malformed LaTeX and standalone invalid expressions', () => {
  const service = new TruthCheckService();
  for (const text of ['', String.raw`\frac{1}{2`, String.raw`\fract{1}{2}`,
    String.raw`\left(x`, '1/0', '1 / 0', '1=0', '$1 = 0$']) {
    assert.equal(service.check(text).truthFlag, false, text);
  }
});

test('candidate check preserves source state but does not validate raw source as generated content', async () => {
  const input = { captureText: String.raw`原材料损坏: \frac{1}{`, source: 'note_generation',
    currentStep: 'truth_check', persist: false, analysisOnly: false,
    knowledgeUnit: { content: '2+2=4' } };
  const result = await TruthCheckNodeFactory.create(new TruthCheckService())(input);
  assert.equal(result.state.error, undefined);
  assert.equal(result.state.captureText, input.captureText);
  assert.equal(result.state.knowledgeUnit, input.knowledgeUnit);
  assert.equal(input.truthCheck, undefined);
  const withoutCandidate = await TruthCheckNodeFactory.create(new TruthCheckService())({
    ...input, knowledgeUnit: undefined,
  });
  assert.equal(withoutCandidate.state.error.kind, 'TRUTH_CHECK_ERROR');
});

test('dispatcher retains the actual local failure detail through the real prepared graph', async () => {
  const dispatcher = new Dispatcher();
  const result = { draft: { sections: [] }, evidence: [], verification: { issues: [], decisions: [] } };
  const evaluation = await dispatcher.evaluateStandardCandidate(result,
    { fragments: [{ id: 's1', text: 'original' }] }, { mustInclude: [] },
    { draftToKnowledgeUnit: () => ({ content: String.raw`\frac{1}{2` }) });
  assert.equal(evaluation.hardIssueCount, 1);
  assert.match(evaluation.issues[0].message, /bracketPair.*missing closing brace/);
});

test('diagnostics retain long reasons, section locations and all distinct issues', () => {
  const dispatcher = new Dispatcher();
  const issues = Array.from({ length: 5 }, (_, index) => ({ code: 'MATH_ERROR', stage: 'verifier',
    severity: 'hard', sectionId: 'section-' + index, message: '原因'.repeat(60) + '关键结论', repairable: false }));
  const summary = dispatcher.issueSummary(issues);
  assert.match(summary, /section-4/);
  assert.equal(summary.match(/关键结论/g).length, 5);
});

test('soft verifier advice does not mislabel a hard local gate failure', () => {
  const dispatcher = new Dispatcher();
  const issues = [
    { stage: 'verifier', code: 'OPTIONAL_EXPLANATION', severity: 'soft', message: '可补充解释' },
    { stage: 'truth_check', code: 'TRUTH_CHECK_ERROR', severity: 'hard', message: 'missing closing brace' },
  ];
  assert.equal(dispatcher.readOnlyVerificationStopReason(issues), 'artifact_validation_failed');
  issues[0].severity = 'hard';
  assert.equal(dispatcher.readOnlyVerificationStopReason(issues), 'content_verification_failed');
  issues[0].code = 'VERIFIER_UNAVAILABLE';
  assert.equal(dispatcher.readOnlyVerificationStopReason(issues), 'verifier_unavailable');
});

test('generation and verification prompts separate derived math from source quotations and metadata', () => {
  assert.match(km, /Distinguish source givens, derived conclusions, and unconfirmed conditions/);
  assert.match(km, /Do not reject a valid derivation merely because its conclusion is not verbatim/);
  assert.match(km, /confidence metadata alone is not grounds for a hard issue/);
  assert.match(km, /Give each issue a Chinese message/);
  assert.match(read('entry/src/main/ets/services/AgentMemoryService.ets'), /分类置信度（模型元数据，非 OCR 准确率或数学真值）/);
});

// spec 018: 真值检查实现归 TruthCheckService, Capture workflow 节点是唯一调用方。
test('TruthCheckService holds the real truth-check implementation', () => {
  assert.match(tcs, /truthCheck\(ocrText: string\): MvpTruthCheckResult/, 'truthCheck impl must live in TruthCheckService');
  assert.match(tcs, /checkBracePairing\(text: string\)/, 'brace pairing impl must live in TruthCheckService');
  assert.match(tcs, /checkDivisionByZero\(text: string\)/);
  assert.match(tcs, /checkEquation\(text: string\)/);
  assert.match(tcs, /checkLatexInternal\(body: string\)/);
  assert.doesNotMatch(tcs, /patchIntegralDx\(/, 'local checks must not invent an integration variable');
  assert.doesNotMatch(tcs, /from '\.\/KnowledgeModel'/, 'TruthCheckService must not depend on KnowledgeModel');
});

test('the 4 internal result interfaces moved with the logic', () => {
  for (const name of ['BracePairingResult', 'LatexCheckDetail', 'DivisionByZeroCheck', 'EquationCheckResult']) {
    assert.match(tcs, new RegExp(`interface ${name}`), `${name} must be defined in TruthCheckService`);
  }
});

// spec 015 PR3: KnowledgeModel 重构为轻量编排 agent, 调用点直连协作服务。
test('KnowledgeModel structures via PromptBuilder while CaptureGraph owns TruthCheck', () => {
  assert.match(km, /export class KnowledgeModel {/);
  assert.doesNotMatch(km, /truthCheckService\.check\(ocrText\)/, 'structure() must not duplicate TruthCheckNode');
  assert.match(km, /this\.promptBuilder\.buildPrompt\(ocrText\)/, 'callAi must call PromptBuilder directly');
  assert.doesNotMatch(km, /checkBracePairing\(/, 'truth checks must live in TruthCheckService');
  assert.doesNotMatch(km, /你是数学学习笔记结构化助手/, 'prompt body must live in PromptBuilder');
});

test('service-level Hypium coverage exists (4 checks)', () => {
  assert.equal(existsSync(tcsTestPath), true, 'agents/src/test/TruthCheckService.test.ets must exist');
  const t = read('agents/src/test/TruthCheckService.test.ets');
  const itCount = (t.match(/\bit\(/g) ?? []).length;
  assert.ok(itCount >= 4, `expected >=4 Hypium cases, found ${itCount}`);
  for (const marker of ['checkBracePairing', 'checkDivisionByZero', 'checkEquation', 'checkLatexInternal']) {
    assert.match(t, new RegExp(marker), `service test must cover ${marker}`);
  }
});
