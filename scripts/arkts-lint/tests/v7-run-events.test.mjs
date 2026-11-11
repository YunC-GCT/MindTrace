// 路径: scripts/arkts-lint/tests/v7-run-events.test.mjs
// 职责: spec 039 S3 —— run 事件树：runId 贯通、node/commit/approval 事件、payload 不落正文、顺序稳定。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createRuntime, memoryStorage } from './knowledge-dispatch-runtime.mjs';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

const TEXT_PAYLOAD = { kind: 'text', text: '函数在一点连续。' };

const captureAnswer = (_request, index) => (index % 2 === 1
  ? { category: '概念', subject: '数学分析', chapter: '连续性', confidence: 0.95, cleaned_text: '函数在一点连续。' }
  : {
    category: '概念', subject: '数学分析', chapter: '连续性', title: '连续函数',
    tags: ['连续'], difficulty: 1, importance: 3,
    fields: [{ key: 'definition', label: '定义', value: '函数在一点连续。' }],
  });

function captureCommand(operationId) {
  return { kind: 'capture', operationId, source: 'app', payload: TEXT_PAYLOAD };
}

function recordingSink() {
  const events = [];
  return {
    events,
    sink: {
      async emit(runId, event) { events.push({ runId, kind: event.kind, payload: event.payloadJson }); },
      async settle() {},
    },
  };
}

test('committed：事件树包含 dispatch.start → node.ended×N → commit.committed → dispatch.terminal', async () => {
  const runtime = createRuntime(captureAnswer);
  const recorder = recordingSink();
  const outcome = await runtime.dispatcher.dispatchCommand(captureCommand('op-evt-1'), {
    dao: memoryStorage().dao,
    runEventSink: recorder.sink,
  });
  assert.equal(outcome.kind, 'committed');
  const kinds = recorder.events.map((event) => event.kind);
  assert.equal(kinds[0], 'dispatch.start');
  assert.equal(kinds[kinds.length - 1], 'dispatch.terminal');
  assert.ok(kinds.includes('commit.committed'));
  assert.ok(kinds.filter((kind) => kind === 'node.ended').length >= 4, 'capture 图节点应有 node.ended 事件');
  assert.ok(kinds.indexOf('commit.committed') < kinds.indexOf('dispatch.terminal'));
});

test('runId 贯通：所有事件都等于 command.operationId', async () => {
  const runtime = createRuntime(captureAnswer);
  const recorder = recordingSink();
  await runtime.dispatcher.dispatchCommand(captureCommand('op-evt-2'), {
    dao: memoryStorage().dao,
    runEventSink: recorder.sink,
  });
  assert.ok(recorder.events.length > 2);
  assert.equal(recorder.events.every((event) => event.runId === 'op-evt-2'), true);
});

test('payload 不落正文：node/commit 事件字段里没有捕获文本或笔记内容', async () => {
  const runtime = createRuntime(captureAnswer);
  const recorder = recordingSink();
  await runtime.dispatcher.dispatchCommand(captureCommand('op-evt-3'), {
    dao: memoryStorage().dao,
    runEventSink: recorder.sink,
  });
  for (const event of recorder.events) {
    assert.doesNotMatch(event.payload, /函数在一点连续/);
    assert.doesNotMatch(event.payload, /连续函数/);
  }
  const nodeEvent = recorder.events.find((event) => event.kind === 'node.ended');
  assert.match(nodeEvent.payload, /"step":/);
  assert.match(nodeEvent.payload, /"durationMs":/);
  const commitEvent = recorder.events.find((event) => event.kind === 'commit.committed');
  assert.match(commitEvent.payload, /"noteId":/);
  assert.match(commitEvent.payload, /"commitKey":/);
});

test('failed：无 commit.committed 事件，terminal 为失败终态', async () => {
  const runtime = createRuntime(() => { throw new Error('LLM_DOWN'); });
  const recorder = recordingSink();
  const outcome = await runtime.dispatcher.dispatchCommand(captureCommand('op-evt-4'), {
    dao: memoryStorage().dao,
    runEventSink: recorder.sink,
  });
  assert.equal(outcome.kind, 'failed');
  const kinds = recorder.events.map((event) => event.kind);
  assert.ok(kinds.includes('dispatch.terminal'));
  assert.equal(kinds.includes('commit.committed'), false);
});

test('approval.rejected：preparedCandidate 检查点缺失 → 拒绝事件 + 拒绝终态，无 terminal', async () => {
  const runtime = createRuntime(() => { throw new Error('should not reach LLM'); });
  const recorder = recordingSink();
  const command = {
    kind: 'preparedCandidate',
    operationId: 'op-evt-appr',
    source: 'app',
    preparedCandidate: { runId: 'run-a', checkpointId: 'cp-a', candidateHash: 'hash-a', commitKey: 'ck-a' },
  };
  const outcome = await runtime.dispatcher.dispatchCommand(command, {
    generationRepository: { restore: async () => undefined },
    runEventSink: recorder.sink,
  });
  assert.equal(outcome.kind, 'failed');
  assert.equal(outcome.code, 'PREPARED_CHECKPOINT_MISSING');
  const kinds = recorder.events.map((event) => event.kind);
  assert.ok(kinds.includes('approval.rejected'));
  assert.equal(kinds.includes('dispatch.terminal'), false);
});

test('scheduler-report 解析 run_event 行（S3 观测出口）', () => {
  const report = read('scripts/quality/scheduler-report.mjs');
  assert.match(report, /run_event kind=/);
  assert.match(report, /runEvents/);
  const executor = read('agents/src/main/ets/core/CommandExecutor.ets');
  assert.match(executor, /run_event kind=/);
  assert.match(executor, /RUN_EVENT_NODE_ENDED/);
  assert.match(executor, /RUN_EVENT_COMMIT_COMMITTED/);
  assert.match(executor, /RUN_EVENT_APPROVAL_REJECTED/);
});
