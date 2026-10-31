import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const inputViewModel = readFileSync(
  resolve(root, 'entry/src/main/ets/viewmodels/AgentInputViewModel.ets'),
  'utf8',
);
const conversation = readFileSync(
  resolve(root, 'entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets'),
  'utf8',
);
const aiService = readFileSync(resolve(root, 'entry/src/main/ets/services/AiService.ets'), 'utf8');

test('photo send enters captureReply instead of text-only streaming', () => {
  assert.match(inputViewModel, /if \(uri\.length > 0\)/);
  assert.match(inputViewModel, /this\.service\.captureReply\(sessionId, uri, msg\)/);
  assert.match(inputViewModel, /else \{\s*this\.service\.realReplyStream\(sessionId, msg\)/);
});

test('photo conversation performs analysis only and stores OCR material', () => {
  assert.match(conversation, /this\.capturePort\.analyzeImage\([\s\S]*?imageUri,[\s\S]*?userText/);
  assert.match(conversation, /safeSaveOcrResult\(ref, imageUri, userText, result\)/);
  assert.match(aiService, /kind: 'analysisOnly'/);
});

test('explicit conversation note generation creates a persistence-disabled draft', () => {
  assert.match(conversation, /\.generateNoteDraft\(/);
  assert.match(readFileSync(resolve(root, 'entry/src/main/ets/services/ai/DraftPipeline.ets'), 'utf8'), /generation: request/);
  const mapper = readFileSync(resolve(root, 'agents/src/main/ets/core/dispatch/NoteOutcomeMapper.ets'), 'utf8'); assert.match(mapper, /copy\.persist = command\.kind === 'capture'/);
});
