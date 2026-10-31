// ADR-0019 / A3：NoteCommand → NoteOutcome 契约测试（真实 Dispatcher + fake storage/LLM 边界）。
// 只验证命令/终态 seam；分支内部行为仍由 #239 golden 守门。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createRuntime, memoryStorage, draft } from './knowledge-dispatch-runtime.mjs';
import { dispatchLegacy } from './legacy-dispatch-helper.mjs';

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

// 每项两次调用：分类 → 结构化。奇数位分类、偶数位结构化。
const alternating = () => (_request, index) => (index % 2 === 1 ? CLASSIFICATION : NOTE_JSON);

const TEXT_PAYLOAD = { kind: 'text', text: '函数在一点连续。' };

// 用运行时加载的真实 CancellationToken（common barrel 由 runtime proxy 惰性解析）。
function runtimeCancellationToken() {
  const runtime = createRuntime();
  return new runtime.common.CancellationToken();
}

function captureCommand(operationId) {
  return { kind: 'capture', operationId, source: 'app', payload: TEXT_PAYLOAD };
}

test('capture command reaches a committed outcome with idempotency envelope', async () => {
  const runtime = createRuntime(alternating());
  const storage = memoryStorage();
  const outcome = await runtime.dispatcher.dispatchCommand(captureCommand('op-capture-1'), {
    dao: storage.dao,
  });
  assert.equal(outcome.kind, 'committed');
  assert.equal(outcome.route, 'D1');
  assert.ok(typeof outcome.noteId === 'string' && outcome.noteId.length > 0, 'committed 必须带 noteId');
  assert.equal(typeof outcome.version, 'number');
  assert.equal(outcome.commitKey, 'capture:' + outcome.noteId);
  assert.ok(outcome.unit !== undefined);
  assert.equal(outcome.unit.id, outcome.noteId);
  assert.equal(storage.writes.length, 1);
});

test('failed capture becomes failed(code, retryable) instead of a success-shaped object', async () => {
  const runtime = createRuntime(() => {
    throw new Error('network down');
  });
  const outcome = await runtime.dispatcher.dispatchCommand(captureCommand('op-capture-2'), {});
  assert.equal(outcome.kind, 'failed');
  assert.ok(typeof outcome.code === 'string' && outcome.code.length > 0, 'failed 必须带稳定错误码');
  assert.equal(outcome.retryable, false);
  assert.ok(typeof outcome.message === 'string');
  assert.equal(outcome.unit, undefined, '失败不得携带 data');
});

test('entry cancellation is a cancelled outcome, not a throw', async () => {
  const runtime = createRuntime(alternating());
  const token = {
    isCancelled: () => true,
    throwIfCancelled: () => {
      throw new Error('CONVERSATION_CANCELLED');
    },
  };
  const outcome = await runtime.dispatcher.dispatchCommand(captureCommand('op-capture-3'), {
    cancellationToken: token,
  });
  assert.equal(outcome.kind, 'cancelled');
  assert.equal(outcome.committed, false);
  assert.equal(outcome.noteId, undefined);
});

test('in-graph cancellation before any write is cancelled(committed=false)', async () => {
  const token = new runtimeCancellationToken();
  const runtime = createRuntime((request, index) => {
    token.cancel();
    return index % 2 === 1 ? CLASSIFICATION : NOTE_JSON;
  });
  const storage = memoryStorage();
  const outcome = await runtime.dispatcher.dispatchCommand(captureCommand('op-capture-4'), {
    cancellationToken: token,
    dao: storage.dao,
  });
  assert.equal(outcome.kind, 'cancelled');
  assert.equal(outcome.committed, false);
  assert.equal(storage.writes.length, 0);
});

test('cancellation after the write reports cancelled(committed=true) with commit envelope', async () => {
  // 写入在 dao.insert 里发生；写成功后 token 才被取消 —— 必须如实报 committed=true（ADR-0019 (e)）。
  const token = new runtimeCancellationToken();
  const runtime = createRuntime(alternating());
  const storage = memoryStorage();
  const cancellingDao = {
    async insert(value) {
      const rowId = await storage.dao.insert(value);
      token.cancel();
      return rowId;
    },
  };
  const outcome = await runtime.dispatcher.dispatchCommand(captureCommand('op-capture-5'), {
    cancellationToken: token,
    dao: cancellingDao,
  });
  assert.equal(outcome.kind, 'cancelled');
  assert.equal(outcome.committed, true);
  assert.ok(typeof outcome.noteId === 'string' && outcome.noteId.length > 0);
  assert.equal(typeof outcome.version, 'number');
  assert.equal(outcome.commitKey, 'capture:' + outcome.noteId);
  assert.equal(storage.writes.length, 1);
});

test('analysisOnly command yields a preview outcome without a committed note', async () => {
  const runtime = createRuntime(alternating());
  const outcome = await runtime.dispatcher.dispatchCommand({
    kind: 'analysisOnly',
    operationId: 'op-analysis-1',
    source: 'app',
    payload: TEXT_PAYLOAD,
  }, {});
  assert.equal(outcome.kind, 'readyPreview');
  assert.equal(outcome.noteId, undefined);
  assert.ok(outcome.classification !== undefined);
});

test('light generation command yields readyPreview with checkpoint metadata', async () => {
  const runtime = createRuntime((request) => {
    const prompt = request.messages.map((m) => m.content).join('\n');
    return prompt.includes('结构化助手')
      ? NOTE_JSON
      : draft();
  });
  const storage = memoryStorage();
  const outcome = await runtime.dispatcher.dispatchCommand({
    kind: 'generation',
    operationId: 'op-generation-1',
    generation: {
      runId: 'run-command-1',
      instruction: '保留定义',
      mode: 'create',
      route: 'light',
      sources: {
        fragments: [{ id: 'src-1', kind: 'conversation', originId: 'origin-1', sequence: 0, fingerprint: 'fp-1', text: '函数在一点连续。' }],
      },
    },
  }, { generationRepository: storage.repository });
  assert.equal(outcome.kind, 'readyPreview');
  assert.equal(outcome.runId, 'run-command-1');
  assert.ok(typeof outcome.checkpointId === 'string');
  assert.equal(outcome.noteId, undefined);
});

test('dispatchSetCommand returns per-item outcomes with aggregate counts (A3d)', async () => {
  const runtime = createRuntime(alternating());
  const storage = memoryStorage();
  const commands = [
    { kind: 'capture', operationId: 'set-0', source: 'app', payload: TEXT_PAYLOAD },
    { kind: 'capture', operationId: 'set-1', source: 'app', payload: { kind: 'text', text: '数列收敛的定义。' } },
  ];
  const batch = await runtime.dispatcher.dispatchSetCommand(commands, { dao: storage.dao });
  assert.equal(batch.total, 2);
  assert.equal(batch.committed, 2);
  assert.equal(batch.failed, 0);
  assert.equal(batch.cancelled, 0);
  assert.equal(batch.items.length, 2);
  assert.equal(batch.items[0].kind, 'committed');
  assert.equal(batch.items[1].kind, 'committed');
  assert.ok(typeof batch.items[0].noteId === 'string');
  assert.notEqual(batch.items[0].noteId, batch.items[1].noteId);
  assert.equal(storage.writes.length, 2);
});

test('A2A ingest receipt consumes NoteOutcome instead of exception text (A3d)', () => {
  const ingest = read('entry/src/main/ets/services/AgentIngestService.ets');
  const ability = read('entry/src/main/ets/agentextability/AgentExtAbility.ets');
  assert.match(ingest, /static async ingestOutcome/);
  assert.match(ingest, /service\.ingestTextOutcome/);
  assert.match(ability, /ingestOutcome\(this\.context, request\)/);
  assert.match(ability, /outcome\.kind === 'committed'/);
  assert.match(ability, /outcome\.kind === 'cancelled'/);
  assert.match(ability, /retryable/);
});

test('legacy DispatchResult appearance is reproducible from the command seam (4c migration)', async () => {
  const runtime = createRuntime(alternating());
  const storage = memoryStorage();
  const result = await dispatchLegacy(runtime, { source: 'app', payload: TEXT_PAYLOAD }, {
    persist: true,
    dao: storage.dao,
  });
  assert.equal(result.success, true);
  assert.equal(result.route, 'D1');
  assert.equal(typeof result.durationMs, 'number');

  const storage2 = memoryStorage();
  const outcome = await runtime.dispatcher.dispatchCommand({
    kind: 'capture',
    operationId: 'op-equivalence',
    source: 'app',
    payload: TEXT_PAYLOAD,
  }, { persist: true, dao: storage2.dao });
  assert.equal(outcome.kind, 'committed');
  assert.ok(outcome.noteId.length > 0, '命令 seam 必须返回 noteId');
  assert.ok(result.data.id.length > 0, 'adapter 还原的 data.id 必须存在');
  assert.equal(result.data.title.length > 0, true, 'adapter 还原的 data 保留标题（旧外观）');
});

test('AiService capture and confirm paths use the command seam', () => {
  const ai = read('entry/src/main/ets/services/AiService.ets');
  const commit = read('entry/src/main/ets/services/ai/DraftCommitService.ets');
  const mapper = read('agents/src/main/ets/core/dispatch/NoteOutcomeMapper.ets');
  // 调用方：文本/A2A capture 走 AiService，确认提交走 DraftCommitService（AiService 切片 3）。
  const capture = read('entry/src/main/ets/services/ai/CapturePipeline.ets');
  assert.match(capture, /dispatchCommand\(command/);
  assert.match(ai, /new DraftCommitService\(/);
  assert.ok((commit.match(/outcome\.kind !== 'committed'/g) ?? []).length >= 1);
  assert.match(commit, /kind: 'preparedCandidate'/);
  // mapper：错误码 / retryable / 终态判别集中在一处。
  // A4 4c Step3：旧 DispatchResult 与 toOutcome 已下线；mapper 只保留命令→请求/选项。
  assert.ok(!mapper.includes('static toOutcome('), 'toOutcome 必须已下线');
  assert.match(mapper, /static toRequest\(/);
  assert.match(mapper, /static toOptions\(/);
  const dispatcherSource = read('agents/src/main/ets/core/Dispatcher.ets');
  assert.match(dispatcherSource, /normalizeInvokedOutcome/, 'committed 信封归一化在 Dispatcher 内');
});

test('AiService analysis / generation / regenerate consumers use the command seam (A3c)', () => {
  const ai = read('entry/src/main/ets/services/AiService.ets');
  const pipeline = read('entry/src/main/ets/services/ai/DraftPipeline.ets');
  assert.match(read('entry/src/main/ets/services/ai/CapturePipeline.ets'), /kind: 'analysisOnly'/);
  assert.match(pipeline, /kind: 'generation'/);
  assert.match(pipeline, /kind: 'regenerate'/);
  const capture = read('entry/src/main/ets/services/ai/CapturePipeline.ets');
  assert.ok((capture.match(/dispatchCommand\(command/g) ?? []).length >= 1, 'capture/analyze 在 CapturePipeline');
  assert.ok((pipeline.match(/dispatchCommand\(command/g) ?? []).length >= 2, 'draft/regenerate 在 DraftPipeline');
  assert.ok(((capture + pipeline).match(/outcome\.kind !== 'readyPreview'/g) ?? []).length >= 3);
});
