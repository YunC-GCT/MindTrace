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

const dispatcher = read('agents/src/main/ets/core/Dispatcher.ets');
const captureChain = read('common/src/main/ets/models/CaptureChain.ets');
const aiService = read('entry/src/main/ets/services/AiService.ets');
const ocrNode = read('agents/src/main/ets/graph/nodes/OcrNode.ets');
const convWorkflow = read('entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets');
const convState = read('entry/src/main/ets/workflows/conversation/ConversationState.ets');
const memService = read('entry/src/main/ets/services/AgentMemoryService.ets');

// === Legacy tests preserved ===

test('image payload maps to camera_capture source in the capture flow', () => {
  assert.match(dispatcher, /payload\.kind === 'image'/);
  assert.match(dispatcher, /return 'camera_capture'/);
});

test('generation pipeline always synthesizes a text payload from the source bundle', () => {
  const genPayloadBlock = dispatcher.match(
    /const generationPayload: DispatchRequest = \{[\s\S]*?payload: \{ kind: 'text', text: this\.bundleText\(bundle\) \}/,
  );
  assert.ok(genPayloadBlock !== null, 'dispatchGeneration must replace image payload with synthesized text');
});

test('light route generation state uses synthesized text and persist=false', () => {
  const lightStateBlock = dispatcher.match(
    /const initial: AgentState = \{[\s\S]*?captureText: this\.bundleText\(bundle\)[\s\S]*?source: 'note_generation'[\s\S]*?persist: false/,
  );
  assert.ok(lightStateBlock !== null, 'light route must set persist=false');
});

test('AiService.generateNoteDraftWithSources dispatches with persist=false', () => {
  assert.match(aiService, /generateNoteDraftWithSources[\s\S]*?persist: false/);
});

test('AiService.confirmDraft dispatches with persist=true and a DAO', () => {
  assert.match(aiService, /confirmDraft[\s\S]*?persist: true/);
  assert.match(aiService, /confirmDraft[\s\S]*?dao:/);
});

test('CaptureChain defines ImagePayload with imageUri and optional userText', () => {
  assert.match(captureChain, /interface ImagePayload/);
  assert.match(captureChain, /imageUri: string/);
  assert.match(captureChain, /userText\?: string/);
});

test('OcrNode reads input.payload for image kind but does not run in the generation graph', () => {
  assert.match(ocrNode, /input\.payload/);
  assert.match(dispatcher, /buildGenerationGraph/);
  const genBlock = dispatcher.match(/private.*buildGenerationGraph[\s\S]*?return graph/);
  assert.ok(genBlock !== null, 'buildGenerationGraph must exist and return');
  assert.doesNotMatch(genBlock[0], /OcrNode/);
});

test('image source does not leak into generation candidate evaluation truth check', () => {
  const evalBlock = dispatcher.match(/buildPreparedGraph[\s\S]*?captureText: this\.bundleText\(bundle\)/);
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
  assert.match(convWorkflow, /this\.generateNoteDraft\(\s*runId,\s*noteInstruction,\s*conversation,\s*pendingSources,\s*route,/);
});

// AC-IMG-02: saveOcrResult returns the pending material source id to the
// workflow, so later draft generation can bind to exactly this image.
test('ConversationWorkflow returns the saveOcrResult source id (AC-IMG-02)', () => {
  assert.match(convWorkflow, /return await this\.getMemory\(\)\.saveOcrResult\(/);
  assert.match(memService, /async saveOcrResult\([\s\S]*?\): Promise<string>/);
});

// AC-IMG-03: image source must only read current-source pending, not all pending records
test('ConversationWorkflow generateNoteFromConversation reads pending only for current source scope (AC-IMG-03)', () => {
  const pendingRead = convWorkflow.match(/getPendingNoteMaterials/);
  assert.ok(pendingRead !== null, 'getPendingNoteMaterials is called for note generation');
  const fullScan = convWorkflow.match(/queryAll.*pending|loadAll.*pending|getAll.*pending/);
  assert.ok(fullScan === null, 'must not read all pending records indiscriminately');
});

// AC-IMG-04: empty OCR result must not crash the workflow; persist:false must not write
test('ConversationWorkflow handleImageReply handles empty OCR text gracefully (AC-IMG-04)', () => {
  const hasOcrFallback = convWorkflow.match(/ocrText.*\|\|.*''|result\.ocrText.*trim\(\).*length === 0|未识别/);
  assert.ok(hasOcrFallback !== null, 'handleImageReply has fallback for empty OCR text');
});

test('AiService.analyzeImage dispatches with persist:false and analysisOnly:true (no write)', () => {
  assert.match(aiService, /analyzeImage[\s\S]*?persist: false/);
  assert.match(aiService, /analyzeImage[\s\S]*?analysisOnly: true/);
});

// ConversationStep must include image_reply
test('ConversationState defines image_reply step', () => {
  assert.match(convState, /'image_reply'/);
});
