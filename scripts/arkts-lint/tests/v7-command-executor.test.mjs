// 路径: scripts/arkts-lint/tests/v7-command-executor.test.mjs
// 职责: spec 039 S1 —— CommandExecutor 的 run 生命周期（run.started/terminal、runId=operationId、
//       settle 一次、异常→五终态）与 workflow 接线契约。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createRuntime, memoryStorage } from './knowledge-dispatch-runtime.mjs';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

const TEXT_PAYLOAD = { kind: 'text', text: '函数在一点连续。' };

function captureCommand(operationId) {
  return { kind: 'capture', operationId, source: 'app', payload: TEXT_PAYLOAD };
}

function recordingSink() {
  const events = [];
  const settled = [];
  return {
    events,
    settled,
    sink: {
      async emit(runId, event) { events.push({ runId, kind: event.kind }); },
      async settle(runId, outcome) { settled.push({ runId, kind: outcome.kind }); },
    },
  };
}

test('capture：committed + run.started 先于 run.terminal + runId=operationId + settle 一次', async () => {
  const runtime = createRuntime((_request, index) => (index % 2 === 1
    ? { category: '概念', subject: '数学分析', chapter: '连续性', confidence: 0.95, cleaned_text: '函数在一点连续。' }
    : {
      category: '概念', subject: '数学分析', chapter: '连续性', title: '连续函数',
      tags: ['连续'], difficulty: 1, importance: 3,
      fields: [{ key: 'definition', label: '定义', value: '函数在一点连续。' }],
    }));
  const recorder = recordingSink();
  const outcome = await runtime.dispatcher.dispatchCommand(captureCommand('op-exec-1'), {
    dao: memoryStorage().dao,
    runEventSink: recorder.sink,
  });
  assert.equal(outcome.kind, 'committed');
  const kinds = recorder.events.map((event) => event.kind);
  assert.equal(kinds[0], 'dispatch.start');
  assert.equal(kinds[kinds.length - 1], 'dispatch.terminal');
  assert.ok(kinds.includes('commit.committed'));
  assert.ok(kinds.includes('node.ended'));
  assert.equal(recorder.events[0].runId, 'op-exec-1');
  assert.equal(recorder.events[recorder.events.length - 1].runId, 'op-exec-1');
  assert.equal(recorder.settled.length, 1);
  assert.equal(recorder.settled[0].runId, 'op-exec-1');
});

test('异常：workflow 抛错 → failed 终态（不向外抛）且 terminal/settle 照常', async () => {
  const runtime = createRuntime(() => { throw new Error('LLM_DOWN'); });
  const recorder = recordingSink();
  const outcome = await runtime.dispatcher.dispatchCommand(captureCommand('op-exec-2'), {
    dao: memoryStorage().dao,
    runEventSink: recorder.sink,
  });
  assert.equal(outcome.kind, 'failed');
  assert.equal(typeof outcome.code, 'string');
  assert.equal(typeof outcome.retryable, 'boolean');
  assert.equal(recorder.events[0].kind, 'dispatch.start');
  assert.equal(recorder.events[recorder.events.length - 1].kind, 'dispatch.terminal');
  assert.equal(recorder.settled.length, 1);
  assert.equal(recorder.settled[0].kind, 'failed');
});

test('取消：pre-cancelled 令牌 → cancelled 终态，仍发 terminal/settle（ADR-0019）', async () => {
  const runtime = createRuntime(() => { throw new Error('should not reach LLM'); });
  const token = new runtime.common.CancellationToken();
  token.cancel();
  const recorder = recordingSink();
  const outcome = await runtime.dispatcher.dispatchCommand(captureCommand('op-exec-3'), {
    dao: memoryStorage().dao,
    cancellationToken: token,
    runEventSink: recorder.sink,
  });
  assert.equal(outcome.kind, 'cancelled');
  assert.equal(recorder.events.length, 2);
  assert.equal(recorder.settled.length, 1);
  assert.equal(recorder.settled[0].kind, 'cancelled');
});

test('可选 sink：不注入 sink 也能正常提交（sink 是可选观测）', async () => {
  const runtime = createRuntime((_request, index) => (index % 2 === 1
    ? { category: '概念', subject: '数学分析', chapter: '连续性', confidence: 0.95, cleaned_text: '函数在一点连续。' }
    : {
      category: '概念', subject: '数学分析', chapter: '连续性', title: '连续函数',
      tags: ['连续'], difficulty: 1, importance: 3,
      fields: [{ key: 'definition', label: '定义', value: '函数在一点连续。' }],
    }));
  const outcome = await runtime.dispatcher.dispatchCommand(captureCommand('op-exec-4'), {
    dao: memoryStorage().dao,
  });
  assert.equal(outcome.kind, 'committed');
});

test('dispatchSetCommand：一个 set 一个 run，逐项终态聚合并发事件', async () => {
  const runtime = createRuntime((_request, index) => (index % 2 === 1
    ? { category: '概念', subject: '数学分析', chapter: '连续性', confidence: 0.95, cleaned_text: '函数在一点连续。' }
    : {
      category: '概念', subject: '数学分析', chapter: '连续性', title: '连续函数',
      tags: ['连续'], difficulty: 1, importance: 3,
      fields: [{ key: 'definition', label: '定义', value: '函数在一点连续。' }],
    }));
  const batch = await runtime.dispatcher.dispatchSetCommand(
    [captureCommand('op-exec-b1'), captureCommand('op-exec-b2')],
    { dao: memoryStorage().dao },
  );
  assert.equal(batch.total, 2);
  assert.equal(batch.committed, 2);
  assert.equal(batch.items.length, 2);
  assert.equal(batch.items.every((item) => item.kind === 'committed'), true);
});

test('接线：executor 只通过 CommandRouter + workflow 执行，不直接 import 分支/图', () => {
  const source = read('agents/src/main/ets/core/CommandExecutor.ets');
  assert.match(source, /this\.router\.preflight\(command, options\)/);
  assert.match(source, /this\.router\.resolve\(command\)/);
  assert.match(source, /workflowFor\(/);
  assert.match(source, /CommandExecutor\.verifyOutcome\(outcome\)/);
  assert.match(source, /CommandExecutor\.settleRun\(/);
  assert.doesNotMatch(source, /import[^;]*CaptureGraph/);
  assert.doesNotMatch(source, /import[^;]*DispatchGraph/);
  assert.doesNotMatch(source, /new KnowledgeModel/);
  assert.doesNotMatch(source, /private buildGraph/);
});

test('五个 workflow 都实现统一契约且不互相 import', () => {
  const files = [
    'agents/src/main/ets/workflows/NoteCaptureWorkflow.ets',
    'agents/src/main/ets/workflows/NoteGenerationWorkflow.ets',
    'agents/src/main/ets/workflows/NoteRegenerateWorkflow.ets',
    'agents/src/main/ets/workflows/NotePreparedWorkflow.ets',
  ];
  for (const file of files) {
    const source = read(file);
    assert.match(source, /implements NoteWorkflow/);
    assert.match(source, /async run\(command: NoteCommand, context: WorkflowContext\): Promise<NoteOutcome>/);
    assert.doesNotMatch(source, /from '\.\/Note(?!.*WorkflowContext)/);
  }
});
