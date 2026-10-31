// A4 切片 3：DispatchGraph 主图骨架的推进语义测试（纯 handler，不碰 RDB/LLM）。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const mod = loadNoteReviewEtsModule('agents/src/main/ets/core/dispatch/DispatchGraph.ets');
const DispatchGraph = mod.DispatchGraph;
const DispatchGraphError = mod.DispatchGraphError;
const ORDER = mod.DISPATCH_STAGE_ORDER;

const COMMAND = { kind: 'capture', operationId: 'op-graph-1', source: 'app', payload: { kind: 'text', text: 'x' } };

function outcome(kind) {
  return { kind, operationId: 'op-graph-1', route: 'D1', durationMs: 1 };
}

function handlersOf(log, terminals) {
  const make = (stage) => async (context) => {
    log.push(stage);
    assert.equal(context.stage, stage);
    if (terminals[stage] !== undefined) {
      return { outcome: terminals[stage] };
    }
    return { next: ORDER[ORDER.indexOf(stage) + 1] };
  };
  return {
    preflight: make('preflight'),
    route: make('route'),
    invoke: make('invoke'),
    verify: make('verify'),
    hitl: make('hitl'),
    publish: make('publish'),
  };
}

function fallback(code, message, retryable) {
  return { kind: 'failed', operationId: 'op-graph-1', route: 'D1', durationMs: 0, code, message, retryable };
}

test('main graph advances through all six stages and returns the terminal outcome', async () => {
  const log = [];
  const terminal = outcome('committed');
  const result = await DispatchGraph.run(COMMAND, handlersOf(log, { publish: terminal }), Date.now(), fallback);
  assert.deepEqual(Array.from(log), ['preflight', 'route', 'invoke', 'verify', 'hitl', 'publish']);
  assert.equal(result.kind, 'committed');
});

test('a stage outcome short-circuits remaining stages', async () => {
  const log = [];
  const terminal = outcome('needsInput');
  const result = await DispatchGraph.run(COMMAND, handlersOf(log, { verify: terminal }), Date.now(), fallback);
  assert.deepEqual(Array.from(log), ['preflight', 'route', 'invoke', 'verify']);
  assert.equal(result.kind, 'needsInput');
});

test('a stage error becomes the fallback failed outcome', async () => {
  const log = [];
  const handlers = handlersOf(log, {});
  handlers.invoke = async () => ({ errorCode: 'OCR_FAILED', errorMessage: 'ocr down', retryable: true });
  const result = await DispatchGraph.run(COMMAND, handlers, Date.now(), fallback);
  assert.equal(result.kind, 'failed');
  assert.equal(result.code, 'OCR_FAILED');
  assert.equal(result.retryable, true);
});

test('illegal stage jumps and missing terminals are rejected', async () => {
  const log = [];
  const skip = handlersOf(log, {});
  skip.preflight = async () => ({ next: 'invoke' });
  await assert.rejects(DispatchGraph.run(COMMAND, skip, Date.now(), fallback), (error) => {
    assert.equal(error instanceof DispatchGraphError, true);
    assert.equal(error.code, 'INVALID_DISPATCH_STAGE');
    return true;
  });

  const stall = handlersOf(log, {});
  stall.publish = async () => ({ next: undefined });
  await assert.rejects(DispatchGraph.run(COMMAND, stall, Date.now(), fallback), (error) => {
    assert.equal(error.code, 'DISPATCH_GRAPH_NO_TERMINAL');
    return true;
  });
});

test('stage order constant matches the A4 contract', () => {
  assert.deepEqual(Array.from(ORDER), ['preflight', 'route', 'invoke', 'verify', 'hitl', 'publish']);
});
