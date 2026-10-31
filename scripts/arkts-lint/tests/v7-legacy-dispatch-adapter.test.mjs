// A4 4c Step1/2：NoteOutcome → 旧 DispatchResult 过渡适配器契约测试（纯映射，不碰 RDB/LLM）。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { toLegacyDispatchResult } from './legacy-dispatch-helper.mjs';

const UNIT = { id: 'note-1', title: 't', version: 2 };

test('committed outcome maps to success + data', () => {
  const result = toLegacyDispatchResult({
    kind: 'committed', operationId: 'op', route: 'D1', durationMs: 5,
    noteId: 'note-1', version: 2, commitKey: 'capture:note-1', unit: UNIT,
  });
  assert.equal(result.success, true);
  assert.equal(result.route, 'D1');
  assert.equal(result.durationMs, 5);
  assert.equal(result.data.id, 'note-1');
  assert.equal(result.errorCode, undefined);
});

test('readyPreview maps to success + draft data + generation', () => {
  const result = toLegacyDispatchResult({
    kind: 'readyPreview', operationId: 'op', route: 'D1', durationMs: 7,
    runId: 'run-1', checkpointId: 'run-1:0', draft: UNIT,
    generation: { runId: 'run-1', route: 'light', status: 'ready-preview' },
  });
  assert.equal(result.success, true);
  assert.equal(result.data.id, 'note-1');
  assert.equal(result.generation.runId, 'run-1');
});

test('failed maps to errorCode + errorMessage + retryable', () => {
  const result = toLegacyDispatchResult({
    kind: 'failed', operationId: 'op', route: 'D1', durationMs: 3,
    code: 'OCR_FAILED', message: 'ocr down', retryable: true,
  });
  assert.equal(result.success, false);
  assert.equal(result.errorCode, 'OCR_FAILED');
  assert.equal(result.errorMessage, 'ocr down');
  assert.equal(result.errorRetryable, true);
});

test('needsInput maps to failure with reason message', () => {
  const result = toLegacyDispatchResult({
    kind: 'needsInput', operationId: 'op', route: 'D1', durationMs: 3,
    reason: '需要先选主题', issues: [],
  });
  assert.equal(result.success, false);
  assert.equal(result.errorMessage, '需要先选主题');
});

test('cancelled maps to CANCELLED code and preserves committed envelope', () => {
  const result = toLegacyDispatchResult({
    kind: 'cancelled', operationId: 'op', route: 'D1', durationMs: 2,
    committed: true, noteId: 'note-1', version: 2, commitKey: 'capture:note-1',
  });
  assert.equal(result.success, false);
  assert.equal(result.errorCode, 'CANCELLED');
  assert.equal(result.cancelledCommitted, true);
  assert.equal(result.cancelledNoteId, 'note-1');
  assert.equal(result.cancelledVersion, 2);
  assert.equal(result.cancelledCommitKey, 'capture:note-1');
});
