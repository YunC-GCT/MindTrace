// DEV/AC binding: DEV-SRC-ISO / AC-SRC-01 — source isolation with image ConversationWorkflow
// coverage; classify_image_intent, image_note_reply, saveOcrResult sourceId return,
// current-source-only pending read, empty OCR, persist:false; no private API testing.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8').replace(/\r\n/g, '\n');

const models = read('common/src/main/ets/models/NoteGenerationModels.ets');
const dispatcher = read('agents/src/main/ets/core/CommandExecutor.ets');
const aiService = read('entry/src/main/ets/services/AiService.ets');
const repoImpl = read('entry/src/main/ets/database/NoteGenerationRepository.ets');
const convWorkflow = read('entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets');
const memoryProjection = read('entry/src/main/ets/workflows/conversation/ConversationMemoryProjection.ets');
const memService = read('entry/src/main/ets/services/AgentMemoryService.ets');

// === Legacy source isolation tests ===

test('SourceFragment has id, kind, originId, sequence, fingerprint, text', () => {
  assert.match(models, /interface SourceFragment/);
  assert.match(models, /id: string/);
  assert.match(models, /kind: SourceKind/);
  assert.match(models, /originId: string/);
  assert.match(models, /sequence: number/);
  assert.match(models, /fingerprint: string/);
  assert.match(models, /text: string/);
});

test('NoteGenerationRun carries sourceIds and pendingSourceIds arrays', () => {
  assert.match(models, /interface NoteGenerationRun[\s\S]*?sourceIds\?: string\[\]/);
  assert.match(models, /pendingSourceIds\?: string\[\]/);
});

test('Dispatcher builds sourceIds from bundle fragments in generation run', () => {
  // 2026-11-02：生成逻辑已迁入 NoteGenerationWorkflow。
  const branch = read('agents/src/main/ets/workflows/NoteGenerationWorkflow.ets');
  assert.match(branch, /sourceIds: bundle\.fragments\.map\(\(fragment\): string => fragment\.id\)/);
});

test('buildSourceId creates stable composite IDs from kind, originId, sequence', () => {
  assert.match(models, /export function buildSourceId/);
  assert.match(models, /kind.*originId.*sequence/);
});

test('normalizeBundle re-sequences fragments and fills missing IDs', () => {
  // 2026-11-02：normalizeBundle 已迁入 NoteGenerationWorkflow（静态方法）。
  const branch = read('agents/src/main/ets/workflows/NoteGenerationWorkflow.ets');
  assert.match(branch, /static normalizeBundle/);
  assert.match(branch, /fragment\.id\.length > 0 \? fragment\.id : buildSourceId/);
});

test('standard and deep generation receive the normalized source bundle', () => {
  // 2026-11-02：withTokenBudget 仍在 GenerationEvaluator（静态方法），调用点在 NoteGenerationWorkflow。
  const evaluator = read('agents/src/main/ets/core/dispatch/GenerationEvaluator.ets');
  const branch = read('agents/src/main/ets/workflows/NoteGenerationWorkflow.ets');
  const calls = branch.match(
    /withTokenBudget\(\s*request,\s*budget\.maxTokens,\s*bundle,\s*requirement,\s*\)/g,
  ) ?? [];
  assert.equal(calls.length, 2);
  assert.match(evaluator, /static withTokenBudget\([\s\S]*?bundle: SourceBundle[\s\S]*?sources: bundle/);
  assert.match(evaluator, /static withTokenBudget\([\s\S]*?requirement: NoteGenerationRequirement[\s\S]*?requirement: requirement/);
  assert.doesNotMatch(evaluator, /static withTokenBudget\([\s\S]*?sources: request\.sources/);
});

test('incremental generation concatenates base and new sources', () => {
  // 2026-11-02：增量逻辑已迁入 NoteRegenerateWorkflow。
  const incrementalWorkflow = read('agents/src/main/ets/workflows/NoteRegenerateWorkflow.ets');
  assert.match(incrementalWorkflow, /base\.sources\.fragments\.concat\(request\.sources\.fragments\)/);
  assert.match(incrementalWorkflow, /base\.manifest\.sourceIds\.concat\(plan\.newSourceIds\)/);
});

test('NoteGenerationRepository persists each SourceFragment in a separate table', () => {
  assert.match(repoImpl, /note_generation_source/);
  assert.match(repoImpl, /source_id/);
  assert.match(repoImpl, /origin_id/);
});

test('NoteGenerationRepository restore reconstructs fragments ordered by sequence', () => {
  assert.match(repoImpl, /orderByAsc\('sequence'\)/);
});

test('referencedPendingSourceIds tracks which pending sources appear in draft sections', () => {
  const branch = read('agents/src/main/ets/workflows/NoteGenerationWorkflow.ets');
  assert.match(branch, /static referencedPendingSourceIds/);
  assert.match(branch, /draft\.sections/);
  assert.match(branch, /pendingSourceIds/);
});

test('validateSourceBundle checks fragment IDs and text for structural validity', () => {
  assert.match(models, /export function validateSourceBundle/);
  assert.match(models, /fragments/);
});

// === AC-SRC-01: Image ConversationWorkflow source coverage ===

test('ConversationWorkflow classify_image_intent node must exist for image intent routing (AC-SRC-01)', () => {
  const hasNode = convWorkflow.match(/classify_image_intent/);
  if (hasNode !== null) {
    assert.ok(true, 'classify_image_intent node exists');
  } else {
    assert.ok(
      false,
      'classify_image_intent node not found — implementation not yet merged (DEV-SRC-ISO / AC-SRC-01)',
    );
  }
});

test('ConversationWorkflow image_note_reply node must exist for image-to-note source binding (AC-SRC-01)', () => {
  const hasNode = convWorkflow.match(/image_note_reply/);
  if (hasNode !== null) {
    assert.ok(true, 'image_note_reply node exists');
  } else {
    assert.ok(
      false,
      'image_note_reply node not found — implementation not yet merged (DEV-SRC-ISO / AC-SRC-01)',
    );
  }
});

// AC-SRC-02: source identity is returned by the memory boundary and written
// into ConversationState for current-source-only draft generation.
test('ConversationWorkflow returns saveOcrResult source id (AC-SRC-02)', () => {
  assert.match(convWorkflow, /return await this\.memoryProjection\.saveOcr\(/);
  assert.match(memoryProjection, /return await this\.service\(\)\.saveOcrResult\(ref\.sessionId/);
  assert.match(memService, /async saveOcrResult\([\s\S]*?\): Promise<string>/);
});

// AC-SRC-03: current source must not read all pending materials
test('ConversationWorkflow only reads pending for the current session source scope (AC-SRC-03)', () => {
  const usesSessionPending = memoryProjection.match(/getPendingNoteMaterials\(ref\.sessionId\)/);
  assert.ok(usesSessionPending !== null, 'uses session-scoped pending read');
  const noFullScan = memoryProjection.match(/queryAll|loadAll.*pending|getAll.*pending/);
  assert.ok(noFullScan === null, 'must not read all pending indiscriminately');
});

// AC-SRC-04: empty OCR and persist:false handling
test('ConversationWorkflow handleImageReply handles empty OCR text without crash (AC-SRC-04)', () => {
  const hasFallback = convWorkflow.match(/ocrText.*\|\||未识别到|result\.ocrText.*trim/);
  assert.ok(hasFallback !== null, 'has empty OCR fallback');
});

test('AiService.analyzeImage uses persist:false — no database write on image recognition only (AC-SRC-04)', () => {
  assert.match(read('entry/src/main/ets/services/ai/CapturePipeline.ets'), /analyzeImage[\s\S]*?kind: 'analysisOnly'/);
});

// SourceFragment kind must support 'ocr' for image-originated sources
test('SourceKind type includes ocr variant for image-originated source fragments', () => {
  const hasOcrKind = models.match(/'ocr'|ocr.*SourceKind/);
  assert.ok(hasOcrKind !== null, "SourceKind must include 'ocr'");
});

// ConversationWorkflow maps OCR pending to SourceFragment correctly
test('ConversationWorkflow maps OCR pending records to SourceFragment with kind ocr (AC-SRC-01)', () => {
  assert.match(convWorkflow, /kind: 'ocr'/);
  assert.match(convWorkflow, /pendingSources/);
});
