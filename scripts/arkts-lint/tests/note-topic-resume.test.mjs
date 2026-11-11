import assert from 'node:assert/strict';
import test from 'node:test';
import { createRuntime, draft } from './knowledge-dispatch-runtime.mjs';

function setup(respond) {
  let stored;
  const checkpoints = [];
  const repository = {
    async saveRun(run, sources) {
      const fragments = new Map((stored?.sources.fragments ?? []).map(item => [item.id, item]));
      for (const fragment of sources.fragments) {
        if (!fragments.has(fragment.id)) fragments.set(fragment.id, fragment);
      }
      stored = structuredClone({ run: {
        ...run,
        clarification: run.clarification ?? stored?.run.clarification,
        contextBudgetTokens: run.contextBudgetTokens ?? stored?.run.contextBudgetTokens,
      }, sources: { fragments: [...fragments.values()] } });
    },
    async restore() {
      if (stored?.run.status === 'running') {
        stored.run.status = 'incomplete';
        stored.run.stopReason = 'app_interrupted';
      }
      return stored && structuredClone({ ...stored, checkpoints, softIssueCodes: [],
        bestCheckpoint: checkpoints.find(item => item.id === stored.run.bestCheckpointId) });
    },
    async listRecoverableRuns() { return stored ? [structuredClone(stored.run)] : []; },
    async saveCheckpoint(value) { checkpoints.push(structuredClone(value)); },
    async appendLifecycleLog() {},
    async getCommitResult() { return undefined; },
    async cancelRun() { stored.run.status = 'cancelled'; },
  };
  let fail = true;
  const runtime = createRuntime(() => {
    if (respond) return respond();
    if (fail) throw new Error('MODEL_TIMEOUT');
    return draft();
  }, {
    'entry/src/main/ets/services/NoteGenerationRepositoryFactory.ets': {
      NoteGenerationRepositoryFactory: { async create() { return repository; } },
    },
    '@ohos.file.fs': {},
    '@kit.AbilityKit': {},
    '@kit.FormKit': {},
    '@kit.BasicServicesKit': {},
    // develop 在 #235 给 AiService 加了 captureLog，需要 hilog 边界
    '@kit.PerformanceAnalysisKit': {
      hilog: { info() {}, error() {}, warn() {}, debug() {}, fatal() {} },
    },
  });
  const { AiService } = runtime.load('entry/src/main/ets/services/AiService.ets');
  const ai = new AiService({});
  return { ai, runtime, succeed() { fail = false; }, restart() { return new AiService({}); } };
}

async function prepare(ai) {
  await ai.saveNoteContextClarification('topic-run', '生成笔记', { fragments: [
    { id: 'src-1', kind: 'conversation', originId: 'message-1', sequence: 0,
      fingerprint: 'fp-1', text: '函数在一点连续。' },
    { id: 'src-2', kind: 'conversation', originId: 'message-2', sequence: 1,
      fingerprint: 'fp-2', text: '矩阵的秩。' },
  ] }, [
    { id: 'continuity', displayName: '连续性', sourceIds: ['src-1'], confidence: 1 },
    { id: 'matrix', displayName: '矩阵', sourceIds: ['src-2'], confidence: 1 },
  ], [], 20000, undefined, undefined, 'light');
}

test('confirmed topic survives a generation failure and remains recoverable after restart', async () => {
  const env = setup();
  await prepare(env.ai);
  await assert.rejects(env.ai.resumeNoteContextClarification('topic-run', 'continuity'));
  assert.ok(env.runtime.requests.length > 0, 'must reach the real generation chain');
  const [run] = await env.restart().listRecoverableDrafts();
  assert.equal(run.clarification.status, 'selected');
  assert.equal(run.clarification.selectedTopicId, 'continuity');
  assert.equal(run.status, 'failed');
});

test('retry after restart generates a preview using only the confirmed topic sources', async () => {
  const env = setup();
  await prepare(env.ai);
  await assert.rejects(env.ai.resumeNoteContextClarification('topic-run', 'continuity'));
  env.succeed();
  const event = await env.restart().retryDraft('topic-run');
  assert.equal(event.result.status, 'ready-preview');
  assert.deepEqual(Array.from(event.sourceIds), ['src-1']);
  assert.match(event.candidate.content, /函数在一点连续/);
});

test('cancelled generation cannot be resumed through its previously confirmed topic', async () => {
  const env = setup();
  await prepare(env.ai);
  await assert.rejects(env.ai.resumeNoteContextClarification('topic-run', 'continuity'));
  await env.ai.cancelDraft('topic-run');
  env.succeed();
  await assert.rejects(env.ai.resumeNoteContextClarification('topic-run', 'continuity'), /cancelled|已取消/);
});

test('an invalid topic does not consume the pending human choice', async () => {
  const env = setup();
  await prepare(env.ai);
  await assert.rejects(env.ai.resumeNoteContextClarification('topic-run', 'missing'), /INVALID_SELECTION/);
  const [run] = await env.ai.listRecoverableDrafts();
  assert.equal(run.clarification.status, 'pending');
  assert.equal(run.clarification.selectedTopicId, undefined);
  assert.equal(env.runtime.requests.length, 0);
});

test('confirmed topic is an explicit generation instruction even for shared source material', async () => {
  const env = setup();
  await prepare(env.ai);
  env.succeed();
  await env.ai.resumeNoteContextClarification('topic-run', 'continuity');
  assert.ok(env.runtime.requests.some(request =>
    request.messages.some(message => message.content.includes('用户已确认主题：连续性'))));
});

test('duplicate confirmation during generation does not start another model request', async () => {
  let release;
  let entered;
  const started = new Promise(resolve => { entered = resolve; });
  const gate = new Promise(resolve => { release = resolve; });
  const env = setup(async () => { entered(); await gate; return draft(); });
  await prepare(env.ai);
  const first = env.ai.resumeNoteContextClarification('topic-run', 'continuity');
  await started;
  try {
    await assert.rejects(env.ai.resumeNoteContextClarification('topic-run', 'continuity'), /IN_PROGRESS/);
    assert.equal(env.runtime.requests.length, 1);
    const [run] = await env.ai.listRecoverableDrafts();
    assert.equal(run.clarification.status, 'selected');
    assert.equal(run.status, 'running');
  } finally { release(); }
  const event = await first;
  const repeated = await env.ai.resumeNoteContextClarification('topic-run', 'continuity');
  assert.equal(repeated.checkpointId, event.checkpointId);
  assert.equal(env.runtime.requests.length, 1);
});

test('a late model failure does not overwrite cancellation recorded during generation', async () => {
  let release;
  let entered;
  const started = new Promise(resolve => { entered = resolve; });
  const gate = new Promise(resolve => { release = resolve; });
  const env = setup(async () => { entered(); await gate; throw new Error('MODEL_TIMEOUT'); });
  await prepare(env.ai);
  const first = env.ai.resumeNoteContextClarification('topic-run', 'continuity');
  const failure = assert.rejects(first);
  await started;
  await env.ai.cancelDraft('topic-run');
  release();
  await failure;
  await assert.rejects(env.ai.resumeNoteContextClarification('topic-run', 'continuity'), /cancelled|已取消/);
});
