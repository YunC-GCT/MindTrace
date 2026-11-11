// 路径: scripts/arkts-lint/tests/v7-write-job.test.mjs
// 职责: 写入工作调度器契约（spec 038 T1–T4）——队列优先级/FIFO、信号量、双通道调度、flag 接入守卫。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');
const arr = (value) => Array.from(value);

const queueMod = loadNoteReviewEtsModule('entry/src/main/ets/services/WriteJobQueueCore.ets');
const semMod = loadNoteReviewEtsModule('entry/src/main/ets/services/AsyncSemaphore.ets');
const schedulerMod = loadNoteReviewEtsModule('entry/src/main/ets/services/WriteJobScheduler.ets');
const { WriteJobQueueCore } = queueMod;
const { AsyncSemaphore } = semMod;
const { WriteJobScheduler, WriteJobFlags } = schedulerMod;

const job = (id, priority) => ({
  jobId: id, kind: 'text_ingest', priority, payloadText: id, status: 'queued', createdAt: Date.now(),
});

test('T1 队列：interactive 优先、同级 FIFO、空队列 undefined', () => {
  const queue = new WriteJobQueueCore();
  assert.equal(queue.dequeue(), undefined);
  queue.enqueue(job('b1', 'background'));
  queue.enqueue(job('i1', 'interactive'));
  queue.enqueue(job('b2', 'background'));
  queue.enqueue(job('i2', 'interactive'));
  assert.deepEqual(['i1', 'i2', 'b1', 'b2'], [
    queue.dequeue().jobId, queue.dequeue().jobId, queue.dequeue().jobId, queue.dequeue().jobId,
  ]);
  assert.equal(queue.size(), 0);
});

test('T2 信号量：容量上限、FIFO 唤醒、release 后可继续', async () => {
  const sem = new AsyncSemaphore(2);
  const events = [];
  await sem.acquire(); events.push('a');
  await sem.acquire(); events.push('b');
  assert.equal(sem.available(), 0);
  let thirdAcquired = false;
  const third = sem.acquire().then(() => { thirdAcquired = true; events.push('c'); });
  await new Promise((r) => setTimeout(r, 20));
  assert.equal(thirdAcquired, false);
  sem.release();
  await third;
  assert.equal(thirdAcquired, true);
  assert.equal(sem.available(), 0);
  sem.release(); sem.release();
  assert.equal(sem.available(), 2);
});

test('T3 调度器：双通道并发、interactive 不等 background 队列、统计齐备', async () => {
  const started = [];
  const finish = [];
  const scheduler = new WriteJobScheduler({
    interactiveConcurrency: 1,
    backgroundConcurrency: 1,
    log: () => {},
  });
  const run = (name, ms) => async () => {
    started.push(name);
    await new Promise((r) => setTimeout(r, ms));
    finish.push(name);
    return name;
  };
  const p1 = scheduler.submit('background', 'bg1', run('bg1', 60));
  const p2 = scheduler.submit('background', 'bg2', run('bg2', 20));
  const p3 = scheduler.submit('interactive', 'int1', run('int1', 20));
  const results = await Promise.all([p1, p2, p3]);
  assert.deepEqual(results, ['bg1', 'bg2', 'int1']);
  const stats = scheduler.stats();
  assert.equal(stats.submitted, 3);
  assert.equal(stats.completed, 3);
  assert.equal(stats.failed, 0);
  assert.equal(stats.maxConcurrent, 2);
  assert.equal(stats.queueDepth, 0);
  assert.ok(started.includes('int1'));
  assert.ok(stats.lastWaitMs >= 0 && stats.lastRunMs >= 0);
});

test('T3b 调度器：executor 失败向上抛且统计 failed', async () => {
  const scheduler = new WriteJobScheduler({ interactiveConcurrency: 1, backgroundConcurrency: 1, log: () => {} });
  await assert.rejects(() => scheduler.submit('interactive', 'bad', async () => { throw new Error('boom'); }), /boom/);
  const stats = scheduler.stats();
  assert.equal(stats.failed, 1);
  assert.equal(stats.queueDepth, 0);
});

test('T4 flag 与接入点：默认关闭、关闭走直连、开启走调度器', () => {
  assert.equal(WriteJobFlags.isEnabled(), false);
  const ingest = read('entry/src/main/ets/services/AgentIngestService.ets');
  assert.ok(ingest.includes('WriteJobFlags.isEnabled()'));
  assert.ok(ingest.includes('WriteJobScheduler.shared().submit('));
  assert.ok(ingest.includes('ingestSingleTextDirect'));
  const inbox = read('entry/src/main/ets/services/A2AInboxIngestService.ets');
  assert.ok(inbox.includes('IngestGateway.ingestText('));
  assert.ok(inbox.includes('INGEST_MODE_BACKGROUND'));
  const gateway = read('entry/src/main/ets/services/IngestGateway.ets');
  assert.ok(gateway.includes("AgentIngestService.ingestSingleText(context, text, 'background')"));
  assert.ok(gateway.includes('INGEST_MODE_BACKGROUND'));
  const scheduler = read('entry/src/main/ets/services/WriteJobScheduler.ets');
  assert.ok(scheduler.includes('[WriteJob]'));
});


test('T3c executor 同步抛错不占死 lane，后续任务仍可跑', async () => {
  const scheduler = new WriteJobScheduler({ interactiveConcurrency: 1, backgroundConcurrency: 1, log: () => {} });
  await assert.rejects(
    () => scheduler.submit('interactive', 'sync-boom', () => { throw new Error('sync-boom'); }),
    /sync-boom/,
  );
  assert.equal(scheduler.stats().failed, 1);
  assert.equal(scheduler.stats().queueDepth, 0);
  const after = await scheduler.submit('interactive', 'after', async () => 'ok');
  assert.equal(after, 'ok');
  assert.equal(scheduler.stats().completed, 1);
});

test('T6 日志格式：enqueued/started/done 带 priority/kind/chars/runMs/waitMs', async () => {
  const lines = [];
  const scheduler = new WriteJobScheduler({ interactiveConcurrency: 1, backgroundConcurrency: 1, log: (l) => lines.push(l) });
  await scheduler.submit('interactive', 'log-text', async () => 'v');
  assert.ok(lines.length >= 3);
  assert.ok(lines.some((l) => l.startsWith('[WriteJob] enqueued id=') && l.includes('priority=interactive')
    && l.includes('kind=text_ingest') && l.includes('chars=8') && l.includes('depth=')));
  assert.ok(lines.some((l) => l.startsWith('[WriteJob] started id=') && l.includes('priority=interactive')
    && l.includes('waitMs=') && l.includes('active=')));
  assert.ok(lines.some((l) => l.startsWith('[WriteJob] done id=') && l.includes('priority=interactive')
    && l.includes('runMs=') && l.includes('waitMs=')));
});

test('T4b executor 注入点：包装函数经调度器返回 executor 结果', async () => {
  const scheduler = new WriteJobScheduler({ interactiveConcurrency: 1, backgroundConcurrency: 1, log: () => {} });
  let calls = 0;
  const wrapped = async (text) => {
    calls += 1;
    return await scheduler.submit('interactive', text, async () => 'result:' + text);
  };
  assert.equal(await wrapped('a'), 'result:a');
  assert.equal(calls, 1);
});


test('T7 事件 sink：enqueued/started/done 字段齐全', async () => {
  const events = [];
  const scheduler = new WriteJobScheduler({ interactiveConcurrency: 1, backgroundConcurrency: 1, log: () => {} });
  scheduler.setEventSink((event) => events.push(event));
  await scheduler.submit('interactive', 'event-text', async () => 'v');
  assert.deepEqual(events.map((e) => e.phase), ['enqueued', 'started', 'done']);
  assert.equal(events[0].priority, 'interactive');
  assert.equal(events[0].kind, 'text_ingest');
  assert.ok(events[0].queueDepth >= 0);
  assert.ok(events[1].waitMs >= 0);
  assert.ok(events[2].runMs >= 0);
});

test('T7b sink 抛错不影响任务完成', async () => {
  const scheduler = new WriteJobScheduler({ interactiveConcurrency: 1, backgroundConcurrency: 1, log: () => {} });
  scheduler.setEventSink(() => { throw new Error('sink-boom'); });
  const value = await scheduler.submit('interactive', 'x', async () => 'ok');
  assert.equal(value, 'ok');
});

test('T8 S2 接线：UI 进程灰度 + run_event recorder + stress e2e', () => {
  const entry = read('entry/src/main/ets/entryability/EntryAbility.ets');
  assert.ok(entry.includes('WRITE_JOB_UI_ENABLED'));
  assert.ok(entry.includes('WriteJobScheduler.shared().setEventSink(WriteJobEventRecorder.create())'));
  const config = read('entry/src/main/ets/services/WriteJobConfig.ets');
  // 只断言声明存在（值为 true/false 都允许，回滚改 false 不应让 gate 变红）
  assert.ok(config.includes('WRITE_JOB_UI_ENABLED: boolean'));
  const recorder = read('entry/src/main/ets/services/WriteJobEventRecorder.ets');
  assert.ok(recorder.includes('WRITE_JOB_RUN_PREFIX + event.phase'));
  assert.ok(recorder.includes('WRITE_JOB_RUN_PREFIX + event.jobId'));
  assert.ok(recorder.includes('appendEvent'));
  const runner = [
    read('entry/src/main/ets/debug/DebugCaptureRunner.ets'),
    read('entry/src/main/ets/debug/DebugSchedulerProbes.ets'),
    read('entry/src/main/ets/debug/DebugAgentProbes.ets'),
  ].join('\n');
  assert.ok(runner.includes('runSchedulerStress'));
  const ability = read('entry/src/main/ets/entryability/EntryAbility.ets');
  assert.ok(ability.includes("mode === 'schedulerStress'"));
  // 扩展进程（适配器 + 控制器）不得读 UI 灰度配置；A2A 走内联路径
  const ext = read('entry/src/main/ets/agentextability/AgentExtAbility.ets');
  const controller = [
    read('entry/src/main/ets/services/A2AController.ets'),
    read('entry/src/main/ets/services/A2AIngestHandler.ets'),
    read('entry/src/main/ets/services/A2AConstants.ets'),
    read('entry/src/main/ets/services/A2AAnswerHandler.ets'),
    read('entry/src/main/ets/services/A2ASession.ets'),
  ].join('\n');
  assert.ok(!ext.includes('WriteJobFlags.setEnabled(true)'));
  assert.ok(!controller.includes('WriteJobFlags.setEnabled(true)'));
  assert.ok(!ext.includes('WRITE_JOB_UI_ENABLED'));
  assert.ok(!controller.includes('WRITE_JOB_UI_ENABLED'));
});


test('T3d 失败相事件：phase=failed + error，统计 failed', async () => {
  const events = [];
  const scheduler = new WriteJobScheduler({ interactiveConcurrency: 1, backgroundConcurrency: 1, log: () => {} });
  scheduler.setEventSink((event) => events.push(event));
  await assert.rejects(() => scheduler.submit('interactive', 'bad', async () => { throw new Error('phase-boom'); }), /phase-boom/);
  assert.deepEqual(events.map((e) => e.phase), ['enqueued', 'started', 'failed']);
  assert.equal(events[2].error, 'phase-boom');
  assert.equal(scheduler.stats().failed, 1);
});

test('T8b S2 复查接线：inbox e2e、终态 DAO、report 解析 stress', () => {
  const runner = [
    read('entry/src/main/ets/debug/DebugCaptureRunner.ets'),
    read('entry/src/main/ets/debug/DebugSchedulerProbes.ets'),
    read('entry/src/main/ets/debug/DebugAgentProbes.ets'),
  ].join('\n');
  assert.ok(runner.includes('runSchedulerInbox'));
  assert.ok(runner.includes('A2AInboxIngestService.consume'));
  assert.ok(runner.includes('countRecordsByRunPrefixAndStatus'));
  const dao = read('entry/src/main/ets/database/RunStoreDao.ets');
  assert.ok(dao.includes('countRecordsByRunPrefixAndStatus'));
  const report = read('scripts/quality/scheduler-report.mjs');
  assert.ok(report.includes('e2e-schedulerStress-'));
  assert.ok(report.includes('terminalCommitted'));
  const ability = read('entry/src/main/ets/entryability/EntryAbility.ets');
  assert.ok(ability.includes("mode === 'schedulerInbox'"));
});
