// A4 第一片：RunEventSink seam 契约测试（真实 Dispatcher + fake sink/LLM 边界）。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createRuntime, memoryStorage } from './knowledge-dispatch-runtime.mjs';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');

const CLASSIFICATION = {
  category: '概念',
  subject: '数学分析',
  chapter: '连续性',
  confidence: 0.95,
  cleaned_text: '函数在一点连续。',
};

const NOTE_JSON = {
  category: '概念',
  subject: '数学分析',
  chapter: '连续性',
  title: '连续函数',
  tags: ['连续'],
  difficulty: 1,
  importance: 3,
  fields: [{ key: 'definition', label: '定义', value: '函数在一点连续。' }],
};

const alternating = () => (_request, index) => (index % 2 === 1 ? CLASSIFICATION : NOTE_JSON);
const TEXT_PAYLOAD = { kind: 'text', text: '函数在一点连续。' };

function captureCommand(operationId) {
  return { kind: 'capture', operationId, source: 'app', payload: TEXT_PAYLOAD };
}

test('dispatchCommand emits start + terminal run events through the sink', async () => {
  const runtime = createRuntime(alternating());
  const storage = memoryStorage();
  const events = [];
  const sink = {
    async emit(runId, event) {
      events.push({ runId, kind: event.kind, payloadJson: event.payloadJson });
    },
  };
  const outcome = await runtime.dispatcher.dispatchCommand(captureCommand('op-sink-1'), {
    dao: storage.dao,
    runEventSink: sink,
  });
  assert.equal(outcome.kind, 'committed');
  assert.equal(events.length, 2);
  assert.equal(events[0].kind, 'dispatch.start');
  assert.equal(events[1].kind, 'dispatch.terminal');
  assert.equal(events[0].runId, 'op-sink-1');
  const start = JSON.parse(events[0].payloadJson);
  assert.equal(start.commandKind, 'capture');
  const terminal = JSON.parse(events[1].payloadJson);
  assert.equal(terminal.outcomeKind, 'committed');
  assert.equal(terminal.noteId.length > 0, true);
  assert.equal(typeof terminal.durationMs, 'number');
});

test('a throwing sink never fails the command (observability is best-effort)', async () => {
  const runtime = createRuntime(alternating());
  const storage = memoryStorage();
  const sink = {
    async emit() {
      throw new Error('sink down');
    },
  };
  const outcome = await runtime.dispatcher.dispatchCommand(captureCommand('op-sink-2'), {
    dao: storage.dao,
    runEventSink: sink,
  });
  assert.equal(outcome.kind, 'committed');
});

test('RunEventSink seam stays in the dispatch layer and is optional', () => {
  const sinkContract = read('agents/src/main/ets/core/dispatch/RunEventSink.ets');
  const options = read('agents/src/main/ets/core/dispatch/DispatchOptions.ets');
  assert.match(sinkContract, /export interface RunEventSink/);
  assert.match(sinkContract, /DISPATCH_EVENT_START/);
  assert.match(sinkContract, /DISPATCH_EVENT_TERMINAL/);
  assert.match(options, /runEventSink\?: RunEventSink/);
  assert.match(read('agents/src/main/ets/core/Dispatcher.ets'), /emitRunEvent\(options, command\.operationId/);
});
