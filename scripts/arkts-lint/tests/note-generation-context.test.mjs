import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
  chatModelsDependencyMocks,
  loadNoteReviewEtsModule,
} from './note-review-ets-loader.mjs';

const root = resolve(import.meta.dirname, '../../..');

function readRepoFile(relativePath) {
  return readFileSync(resolve(root, relativePath), 'utf8').replace(/\r\n/g, '\n');
}

function sourceFingerprint(text) {
  let hash = 2166136261;
  for (let index = 0; index < text.length; index += 1) {
    hash ^= text.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return `fp-${(hash >>> 0).toString(16)}`;
}

function loadContextBuilder() {
  return loadNoteReviewEtsModule(
    'entry/src/main/ets/services/NoteGenerationContextBuilder.ets',
    {
      mocks: {
        common: { sourceFingerprint },
      },
    },
  ).NoteGenerationContextBuilder;
}

function buildInput(overrides = {}) {
  return {
    summary: undefined,
    pendingNotes: [],
    recentMessages: [],
    instruction: '',
    inlineMaterial: '',
    currentConversationText: '',
    currentRunId: 'run-context-test',
    contextWindowTokens: 65536,
    ...overrides,
  };
}

function message(id, role, content, outcome = 'completed', createdAt = 1) {
  return {
    id,
    messageKey: id,
    sessionId: 'session-context-test',
    role,
    content,
    sequence: createdAt,
    origin: 'chat',
    outcome,
    createdAt,
  };
}

function pending(id, content, updatedAt = 1) {
  return {
    id,
    sessionId: 'session-context-test',
    type: 'pending_note',
    content,
    source: 'ocr',
    used: 0,
    createdAt: updatedAt,
    updatedAt,
  };
}

test('NoteGenerationContextBuilder collects only durable note material before rendering sources', () => {
  const builder = readRepoFile('entry/src/main/ets/services/NoteGenerationContextBuilder.ets');

  assert.match(builder, /class NoteGenerationContextBuilder/);
  assert.match(builder, /input\.inlineMaterial\.trim\(\)\.length > 0/);
  assert.match(builder, /input\.pendingNotes/);
  assert.match(builder, /input\.recentMessages/);
  assert.match(builder, /input\.summary/);
  assert.match(builder, /input\.currentConversationText/);

  assert.match(builder, /private static cleanCandidateText/);
  assert.match(builder, /stripRolePrefix/);
  assert.match(builder, /stripControlWrapper/);
  assert.match(builder, /isErrorMessage/);
  assert.match(builder, /isPureControl/);
  assert.match(builder, /candidate\.outcome !== undefined && candidate\.outcome !== 'completed'/);
  assert.match(builder, /candidate\.role === 'system'/);
  assert.match(builder, /hasMathSignal/);
});

test('NoteGenerationContextBuilder dedupes overlap while preserving source provenance', () => {
  const builder = readRepoFile('entry/src/main/ets/services/NoteGenerationContextBuilder.ets');
  const models = readRepoFile('common/src/main/ets/models/NoteGenerationModels.ets');

  assert.match(models, /provenanceIds\?: string\[\]/);
  assert.match(builder, /private static mergeCandidates/);
  assert.match(builder, /sourceFingerprint\(normalizedText\)/);
  assert.match(builder, /findExactDuplicate/);
  assert.match(builder, /findApproximateDuplicate/);
  assert.match(builder, /JACCARD_DUPLICATE_THRESHOLD: number = 0\.88/);
  assert.match(builder, /CONTAINMENT_DUPLICATE_THRESHOLD: number = 0\.95/);
  assert.match(builder, /private static mergeUnit/);
  assert.match(builder, /appendUnique\(provenance/);
  assert.match(builder, /provenanceIds: provenance/);
});

test('NoteGenerationContextBuilder detects competing topics and narrows by explicit instruction', () => {
  const builder = readRepoFile('entry/src/main/ets/services/NoteGenerationContextBuilder.ets');

  assert.match(builder, /const topics: NoteTopicCandidate\[\] = NoteGenerationContextBuilder\.detectTopics\(merged\)/);
  assert.match(builder, /detectInstructionTopics\(input\.instruction, topics\)/);
  assert.match(builder, /requiresClarification: boolean = topics\.length >= 2 && instructionTopics\.length !== 1/);
  assert.match(builder, /filterUnitsByTopic\(merged, instructionTopics\[0\]\)/);
  assert.match(builder, /id: 'linear-algebra'/);
  assert.match(builder, /id: 'calculus-derivative'/);
  assert.match(builder, /id: 'calculus-integral'/);
  assert.match(builder, /id: 'limit-continuity'/);
  assert.match(builder, /id: 'probability'/);
});

test('note-generation context budget leaves output safety and protocol reserve intact', () => {
  const builder = readRepoFile('entry/src/main/ets/services/NoteGenerationContextBuilder.ets');
  const llmConfig = readRepoFile('common/src/main/ets/llm/LlmConfig.ets');

  assert.match(llmConfig, /export const DEFAULT_CONTEXT_WINDOW_TOKENS: number = 65536/);
  assert.match(llmConfig, /KEY_MODEL_CONTEXT_WINDOWS/);
  assert.match(llmConfig, /getContextWindowTokens\(vendorId\?: string, model\?: string\): number/);
  assert.match(llmConfig, /setContextWindowTokens\(vendorId: string, model: string, value: number\): Promise<void>/);
  assert.match(llmConfig, /normalizeContextWindow\(value: number\): number/);

  assert.match(builder, /const OUTPUT_TOKEN_RESERVE: number = 12000/);
  assert.match(builder, /const SAFETY_TOKEN_RESERVE: number = 2048/);
  assert.match(builder, /const PROTOCOL_TOKEN_RESERVE: number = 1600/);
  assert.match(builder, /private static inputBudget/);
  assert.match(builder, /Math\.min\(seventyPercent, bounded\)/);
  assert.match(builder, /Math\.max\(0, sourceBudget\)/);
  assert.match(builder, /private static trimToBudget/);
  assert.match(builder, /private static clipByParagraphs/);
});

test('NoteContextValidityReviewer only asks the model about unresolved non-OCR fragments', () => {
  const reviewer = readRepoFile('entry/src/main/ets/services/NoteContextValidityReviewer.ets');

  assert.match(reviewer, /private static ambiguousFragments/);
  assert.match(reviewer, /for \(const topic of context\.topics\)/);
  assert.match(reviewer, /for \(const sourceId of topic\.sourceIds\)/);
  assert.match(reviewer, /if \(!claimed\.includes\(fragment\.id\) && fragment\.kind !== 'ocr'\)/);
  assert.match(reviewer, /REVIEW_FRAGMENT_LIMIT: number = 12/);
  assert.match(reviewer, /private static async isReviewAvailable/);
  assert.match(reviewer, /await LlmConfig\.getInstance\(\)\.isConfigured\(\)/);
  assert.match(reviewer, /callJsonWithRetry/);
  assert.match(reviewer, /sourceId must reference an allowed source/);
});

test('NoteContextValidityReviewer applies semantic review without allowing source-id drift', () => {
  const reviewer = readRepoFile('entry/src/main/ets/services/NoteContextValidityReviewer.ets');

  assert.match(reviewer, /const allowedIds: string\[\] = ambiguous\.map/);
  assert.match(reviewer, /allowedIds\.includes\(sourceId\)/);
  assert.match(reviewer, /private static parse/);
  assert.match(reviewer, /private static apply/);
  assert.match(reviewer, /rejectedIds\.push\(item\.sourceId\)/);
  assert.match(reviewer, /NoteContextValidityReviewer\.addTopicGroup/);
  assert.match(reviewer, /if \(!rejectedIds\.includes\(fragment\.id\)\) \{ fragments\.push\(fragment\); \}/);
  assert.match(reviewer, /pendingSourceIds: context\.pendingSourceIds\.filter/);
  assert.match(reviewer, /const requiresClarification: boolean = context\.requiresClarification \|\| topics\.length >= 2/);
  assert.match(reviewer, /requiresClarification: requiresClarification/);
});

test('note context schema migration and repository persistence stay compatible', () => {
  const database = readRepoFile('common/src/main/ets/DatabaseHelper.ets');
  const repository = readRepoFile('entry/src/main/ets/database/NoteGenerationRepository.ets');
  const models = readRepoFile('common/src/main/ets/models/NoteGenerationModels.ets');

  assert.match(database, /const DB_SCHEMA_VERSION: number = 13;/);
  assert.match(database, /clarification_json TEXT NOT NULL DEFAULT ''/);
  assert.match(database, /provenance_ids TEXT NOT NULL DEFAULT '\[\]'/);
  assert.match(database, /context_budget_tokens INTEGER NOT NULL DEFAULT 0/);
  assert.match(database, /SQL_MIGRATE_GENERATION_CLARIFICATION/);
  assert.match(database, /SQL_MIGRATE_GENERATION_SOURCE_PROVENANCE/);
  assert.match(database, /SQL_MIGRATE_GENERATION_CONTEXT_BUDGET/);

  assert.match(models, /export interface NoteContextClarification/);
  assert.match(models, /clarification\?: NoteContextClarification/);
  assert.match(models, /provenanceIds\?: string\[\]/);

  assert.match(repository, /const persistedClarification: string = run\.clarification === undefined && runExists/);
  assert.match(repository, /'clarification_json': run\.clarification === undefined \? persistedClarification : JSON\.stringify\(run\.clarification\)/);
  assert.match(repository, /'provenance_ids': JSON\.stringify\(fragment\.provenanceIds \?\? \[fragment\.id\]\)/);
  assert.match(repository, /'context_budget_tokens': run\.contextBudgetTokens \?\? persistedContextBudget/);
  assert.match(repository, /clarification: NoteGenerationRepository\.parseClarification/);
  assert.match(repository, /typeof parsed\.runId !== 'string'/);
  assert.match(repository, /NoteGenerationRepository\.isValidTopicCandidate\(candidate\)/);
  assert.match(repository, /typeof sourceId !== 'string'/);
  assert.match(repository, /provenanceIds: provenanceIds\.length > 0 \? provenanceIds : undefined/);
});

test('interrupted topic selection is reset for restart recovery without duplicating active generation', () => {
  const service = readRepoFile('entry/src/main/ets/services/AiService.ets');

  assert.match(service, /private static readonly activeClarificationRuns: Set<string>/);
  assert.match(service, /AiService\.activeClarificationRuns\.has\(recovery\.run\.id\)/);
  assert.match(service, /AiService\.activeClarificationRuns\.add\(recovery\.run\.id\)/);
  assert.match(service, /finally \{[\s\S]*?AiService\.activeClarificationRuns\.delete\(recovery\.run\.id\)/);
  assert.match(service, /clarification\.status === 'selected'[\s\S]*?!AiService\.activeClarificationRuns\.has\(run\.id\)/);
  assert.match(service, /await this\.restorePendingClarification\(repository, recovery\);[\s\S]*?runs\[index\] = recovery\.run/);
  assert.doesNotMatch(service, /isRecentSelection/);
});

test('context builder removes failures and controls while retaining wrapped mathematics', () => {
  const Builder = loadContextBuilder();
  const result = Builder.build(buildInput({
    inlineMaterial: '生成笔记：导数定义为函数变化率，f\'(x)=2x',
    recentMessages: [
      message('failed-math', 'assistant', '矩阵特征值为 2', 'failed', 1),
      message('network-error', 'assistant', '网络连接失败', 'completed', 2),
      message('control-only', 'user', '重新生成', 'completed', 3),
    ],
  }));

  assert.match(result.contextText, /导数定义/);
  assert.doesNotMatch(result.contextText, /网络连接失败|重新生成|矩阵特征值/);
});

test('context builder dedupes exact overlap and keeps every provenance id', () => {
  const Builder = loadContextBuilder();
  const material = '导数表示函数在一点附近的瞬时变化率，定义可以写成极限公式。';
  const result = Builder.build(buildInput({
    inlineMaterial: material,
    recentMessages: [message('message-duplicate', 'user', material, 'completed', 10)],
  }));

  assert.equal(result.bundle.fragments.length, 1);
  assert.ok(result.bundle.fragments[0].provenanceIds.includes('current:run-context-test'));
  assert.ok(result.bundle.fragments[0].provenanceIds.includes('message-duplicate'));
});

test('context builder never approximate-merges materially different formulas', () => {
  const Builder = loadContextBuilder();
  const shared = '这是关于函数求导规则的完整解释，说明幂函数求导时需要保留指数与次数关系，';
  const result = Builder.build(buildInput({
    pendingNotes: [
      pending('ocr-formula-2', `${shared}最终公式为 f'(x)=2x。`, 10),
      pending('ocr-formula-3', `${shared}最终公式为 f'(x)=3x。`, 11),
    ],
  }));

  assert.equal(result.bundle.fragments.length, 2);
  assert.match(result.contextText, /f'\(x\)=2x/);
  assert.match(result.contextText, /f'\(x\)=3x/);
});

test('mixed linear algebra and derivative material pauses, then explicit derivative intent isolates sources', () => {
  const Builder = loadContextBuilder();
  const recentMessages = [
    message('linear-source', 'user', '矩阵 A 的特征值与特征向量用于描述线性变换。', 'completed', 10),
    message('derivative-source', 'user', '函数求导使用链式法则，导数刻画瞬时变化率。', 'completed', 11),
  ];
  const mixed = Builder.build(buildInput({ recentMessages }));
  assert.equal(mixed.requiresClarification, true);
  assert.equal(mixed.topics.length, 2);

  const selected = Builder.build(buildInput({
    instruction: '只整理求导主题的笔记',
    recentMessages,
  }));
  assert.equal(selected.requiresClarification, false);
  assert.match(selected.contextText, /求导|导数/);
  assert.doesNotMatch(selected.contextText, /矩阵|特征向量/);
});

test('context budget preserves current material and safely yields zero for an impossible tiny window', () => {
  const Builder = loadContextBuilder();
  const current = '当前导数材料：' + '链式法则用于复合函数求导。'.repeat(30);
  const old = '早期导数说明：' + '这是较早且低优先级的助手讲解。'.repeat(900);
  const bounded = Builder.build(buildInput({
    inlineMaterial: current,
    recentMessages: [message('old-assistant', 'assistant', old, 'completed', 1)],
    contextWindowTokens: 20000,
  }));
  assert.ok(bounded.bundle.fragments.some((fragment) => fragment.id.startsWith('current:')));
  assert.ok(!bounded.bundle.fragments.some((fragment) => fragment.id.startsWith('old-assistant')));
  assert.ok(bounded.contextBudgetTokens <= Math.floor(20000 * 0.7));

  const impossible = Builder.build(buildInput({
    inlineMaterial: current,
    contextWindowTokens: 4096,
  }));
  assert.equal(impossible.contextBudgetTokens, 0);
  assert.equal(impossible.bundle.fragments.length, 0);
});

test('topic-card metadata survives persistence copies and selection is single-choice idempotent', () => {
  const models = loadNoteReviewEtsModule(
    'entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatModels.ets',
    { mocks: chatModelsDependencyMocks },
  );
  const clarification = {
    runId: 'conversation-clarify-1',
    instruction: '整理成笔记',
    status: 'pending',
    candidates: [
      { id: 'linear-algebra', displayName: '线性代数', sourceIds: ['linear-source'], confidence: 0.9 },
      { id: 'calculus-derivative', displayName: '微积分/求导', sourceIds: ['derivative-source'], confidence: 0.91 },
    ],
    createdAt: 100,
  };
  const message = {
    id: 10,
    role: 'ai',
    content: '请选择主题',
    ts: 100,
    streaming: false,
  };
  const withCard = models.applyNoteContextClarificationToChatMsg(message, clarification);
  const persisted = models.copyChatMsgForPersistence(withCard);
  assert.equal(persisted.noteContextClarification.status, 'pending');
  assert.equal(persisted.noteContextClarification.candidates.length, 2);

  const selected = models.selectChatMsgNoteTopic(persisted, 'calculus-derivative');
  assert.equal(selected.noteContextClarification.status, 'selected');
  assert.equal(selected.noteContextClarification.selectedTopicId, 'calculus-derivative');
  const repeated = models.selectChatMsgNoteTopic(selected, 'linear-algebra');
  assert.equal(repeated.noteContextClarification.selectedTopicId, 'calculus-derivative');

  const rolledBack = models.resetChatMsgNoteTopicSelection(
    repeated,
    'conversation-clarify-1',
    'calculus-derivative',
  );
  assert.equal(rolledBack.noteContextClarification.status, 'pending');
  assert.equal(rolledBack.noteContextClarification.selectedTopicId, undefined);
});

test('corrupt topic-card metadata degrades to no card', () => {
  const models = loadNoteReviewEtsModule(
    'entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatModels.ets',
    { mocks: chatModelsDependencyMocks },
  );
  assert.equal(models.sanitizeNoteContextClarification({
    runId: 'broken-run',
    instruction: '整理成笔记',
    status: 'pending',
    candidates: [{ id: 7 }],
    createdAt: 100,
  }), undefined);
});

test('uncertain material enters free-text clarification when semantic review is unavailable', async () => {
  const Builder = loadContextBuilder();
  const deterministic = Builder.build(buildInput({
    recentMessages: [
      message('abstract-topic', 'user', '该结构在指定运算下满足封闭性、结合律，并且存在单位元和逆元。', 'completed', 10),
    ],
  }));
  assert.equal(deterministic.topics.length, 0);
  assert.equal(deterministic.budgetDeferred, true);

  const Reviewer = loadNoteReviewEtsModule(
    'entry/src/main/ets/services/NoteContextValidityReviewer.ets',
    {
      mocks: {
        common: {
          sourceFingerprint,
          LlmGuard: class LlmGuard {},
          LlmConfig: {
            getInstance() {
              return { async isConfigured() { return false; } };
            },
          },
        },
      },
    },
  ).NoteContextValidityReviewer;
  const reviewed = await Reviewer.review(deterministic, '整理成笔记');
  assert.equal(reviewed.requiresClarification, true);
  assert.equal(reviewed.topics.length, 0);
  assert.ok(reviewed.bundle.fragments.length > 0);
});
