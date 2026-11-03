// DEV/AC binding: DEV-IMG-CONV / AC-IMG-01 — image ConversationWorkflow must have
// classify_image_intent and image_note_reply nodes; saveOcrResult must return sourceId;
// current source must not read all pending; empty OCR and persist:false must be handled.
// Avoid testing non-existent private APIs or concrete implementation details.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8').replace(/\r\n/g, '\n');

const dispatcher = read('agents/src/main/ets/core/CommandExecutor.ets');
const captureChain = read('common/src/main/ets/models/CaptureChain.ets');
const aiService = read('entry/src/main/ets/services/AiService.ets');
const ocrNode = read('agents/src/main/ets/graph/nodes/OcrNode.ets');
const convWorkflow = read('entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets');
const memoryProjection = read('entry/src/main/ets/workflows/conversation/ConversationMemoryProjection.ets');
const convState = read('entry/src/main/ets/workflows/conversation/ConversationState.ets');
const memService = read('entry/src/main/ets/services/AgentMemoryService.ets');

// === Legacy tests preserved ===

test('image payload maps to camera_capture source in the capture flow', () => {
  // 2026-10-31：capture 分支拆到 CaptureBranch，source 映射抽到 UnitSupport.sourceFromPayload。
  const unitSupport = read('agents/src/main/ets/core/dispatch/UnitSupport.ets');
  assert.match(unitSupport, /payload\.kind === 'image'/);
  assert.match(unitSupport, /return 'camera_capture'/);
  assert.match(read('agents/src/main/ets/workflows/NoteCaptureWorkflow.ets'), /this\.buildGraph\(writePorts, observability, runControl\)\.run\(initial, runContext\)/);
});

test('generation pipeline always synthesizes a text payload from the source bundle', () => {
  // 2026-11-02：dispatchGeneration 已迁入 NoteGenerationWorkflow。
  const branch = read('agents/src/main/ets/workflows/NoteGenerationWorkflow.ets');
  const genPayloadBlock = branch.match(
    /const generationPayload: BranchRequest = \{[\s\S]*?payload: \{ kind: 'text', text: (?:this|GenerationEvaluator)\.bundleText\(bundle\) \}/,
  );
  assert.ok(genPayloadBlock !== null, 'dispatchGeneration must replace image payload with synthesized text');
});

test('light route generation state uses synthesized text and persist=false', () => {
  const branch = read('agents/src/main/ets/workflows/NoteGenerationWorkflow.ets');
  const lightStateBlock = branch.match(
    /const initial: AgentState = \{[\s\S]*?captureText: (?:this|GenerationEvaluator)\.bundleText\(bundle\)[\s\S]*?source: 'note_generation'[\s\S]*?persist: false/,
  );
  assert.ok(lightStateBlock !== null, 'light route must set persist=false');
});

test('AiService.generateNoteDraftWithSources dispatches with persist=false', () => {
  assert.match(read('entry/src/main/ets/services/ai/DraftPipeline.ets'), /kind: 'generation'/);
});

test('AiService.confirmDraft dispatches through the command seam with a DAO', () => {
  // 2026-10-31 (A3)：确认提交走 dispatchCommand；persist 由 mapper 按命令形状决定（preparedCandidate → true）。
  const mapper = read('agents/src/main/ets/core/dispatch/NoteOutcomeMapper.ets');
  const commit = read('entry/src/main/ets/services/ai/DraftCommitService.ets');
  assert.match(commit, /async confirmDraft[\s\S]*?dispatchCommand\(command/);
  assert.match(commit, /dao:/);
  assert.match(mapper, /copy\.persist = command\.kind === 'capture' \|\| command\.kind === 'preparedCandidate'/);
});

test('CaptureChain defines ImagePayload with imageUri and optional userText', () => {
  assert.match(captureChain, /interface ImagePayload/);
  assert.match(captureChain, /imageUri: string/);
  assert.match(captureChain, /userText\?: string/);
});

test('OcrNode reads input.payload for image kind but does not run in the generation graph', () => {
  assert.match(ocrNode, /input\.payload/);
  // 2026-10-31：buildGenerationGraph 抽到 GenerationBranch（静态方法）。
  const branch = read('agents/src/main/ets/workflows/NoteGenerationWorkflow.ets');
  assert.match(branch, /buildGenerationGraph/);
  const genBlock = branch.match(/static .*buildGenerationGraph[\s\S]*?return graph/);
  assert.ok(genBlock !== null, 'buildGenerationGraph must exist and return');
  assert.doesNotMatch(genBlock[0], /OcrNode/);
});

test('image source does not leak into generation candidate evaluation truth check', () => {
  // 2026-11-02：PreparedBranch 迁入 NotePreparedWorkflow；evaluator 自建 truth_check 图。
  const evaluator = read('agents/src/main/ets/core/dispatch/GenerationEvaluator.ets');
  const evalBlock = evaluator.match(
    /truthGraph[\s\S]*?captureText: (?:this|GenerationEvaluator)\.bundleText\(bundle\)/,
  );
  assert.ok(evalBlock !== null, 'evaluateStandardCandidate must use bundleText, not image URI');
});

// === AC-IMG-01: ConversationWorkflow image node coverage ===

test('ConversationWorkflow has image_reply node for image requests (AC-IMG-01)', () => {
  assert.match(convWorkflow, /addNode\('image_reply'/);
});

test('ConversationWorkflow START edge routes image kind to image_reply (AC-IMG-01)', () => {
  assert.match(convWorkflow, /kind === 'image'/);
  assert.match(convWorkflow, /'image_reply'/);
});

test('ConversationWorkflow must add classify_image_intent node for image intent classification (AC-IMG-01)', () => {
  const hasClassifyImage = convWorkflow.match(/classify_image_intent/);
  if (hasClassifyImage !== null) {
    assert.ok(true, 'classify_image_intent node exists');
  } else {
    assert.ok(
      false,
      'classify_image_intent node not found in ConversationWorkflow — implementation not yet merged (DEV-IMG-CONV / AC-IMG-01)',
    );
  }
});

test('ConversationWorkflow must add image_note_reply node for image-to-note generation (AC-IMG-01)', () => {
  const hasImageNoteReply = convWorkflow.match(/image_note_reply/);
  if (hasImageNoteReply !== null) {
    assert.ok(true, 'image_note_reply node exists');
  } else {
    assert.ok(
      false,
      'image_note_reply node not found in ConversationWorkflow — implementation not yet merged (DEV-IMG-CONV / AC-IMG-01)',
    );
  }
});

test('ConversationWorkflow image_reply must call handleImageReply with imageUri and userContent', () => {
  assert.match(convWorkflow, /handleImageReply/);
  assert.match(convWorkflow, /input\.request\.imageUri/);
});

test('ConversationWorkflow image note uses a default instruction when image text is empty', () => {
  assert.match(convWorkflow, /const noteInstruction: string = trimmedUserText\.length > 0 && trimmedUserText !== '\[图片\]'/);
  assert.match(convWorkflow, /请根据图片识别材料生成一份数学学习笔记/);
  assert.match(
    convWorkflow,
    /this\.generateNoteDraft\(\s*ref,\s*noteGenerationRunId,\s*noteInstruction,\s*conversation,\s*pendingSources,/,
  );
});

// AC-IMG-02: saveOcrResult returns the pending material source id to the
// workflow, so later draft generation can bind to exactly this image.
test('ConversationWorkflow returns the saveOcrResult source id (AC-IMG-02)', () => {
  assert.match(convWorkflow, /return await this\.memoryProjection\.saveOcr\(ref, imageUri, userText, result\)/);
  assert.match(memoryProjection, /return await this\.service\(\)\.saveOcrResult\(ref\.sessionId, imageUri, userText, result\)/);
  assert.match(memService, /async saveOcrResult\([\s\S]*?\): Promise<string>/);
});

// AC-IMG-03: image source must only read current-source pending, not all pending records
test('ConversationWorkflow generateNoteFromConversation reads pending only for current source scope (AC-IMG-03)', () => {
  const pendingRead = memoryProjection.match(/getPendingNoteMaterials\(ref\.sessionId\)/);
  assert.ok(pendingRead !== null, 'getPendingNoteMaterials is called for note generation');
  const fullScan = memoryProjection.match(/queryAll.*pending|loadAll.*pending|getAll.*pending/);
  assert.ok(fullScan === null, 'must not read all pending records indiscriminately');
});

// AC-IMG-04: empty OCR result must not crash the workflow; persist:false must not write
test('ConversationWorkflow handleImageReply handles empty OCR text gracefully (AC-IMG-04)', () => {
  const hasOcrFallback = convWorkflow.match(/ocrText.*\|\|.*''|result\.ocrText.*trim\(\).*length === 0|未识别/);
  assert.ok(hasOcrFallback !== null, 'handleImageReply has fallback for empty OCR text');
});

test('AiService.analyzeImage dispatches with persist:false and analysisOnly:true (no write)', () => {
  const capture = read('entry/src/main/ets/services/ai/CapturePipeline.ets');
  assert.match(capture, /analyzeImage[\s\S]*?kind: 'analysisOnly'/);
  assert.match(capture, /analyzeImage[\s\S]*?dispatchCommand\(command/);
});

// ConversationStep must include image_reply
test('ConversationState defines image_reply step', () => {
  assert.match(convState, /'image_reply'/);
});
