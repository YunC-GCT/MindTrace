// 路径: scripts/arkts-lint/tests/v7-golden-dispatch.test.mjs
// 职责: #239 为 Dispatcher.dispatch 的四条路径 × ADR-0019 五终态录制/比对 golden 快照。
//       快照只记录 dispatch seam 上可观察的语义（终态、错误码、分类、落库计数、传输预算），
//       不落盘耗时、时间戳或随机 id；记录模式写 raw/<case>.json，默认模式读文件做字段级 diff。
// Why: ADR-0019 把 capture / generation / regenerate / preparedCandidate / analysisOnly 五型命令
//      与 needsInput / readyPreview / committed / failed / cancelled 五终态固定为契约。#241 迁移
//      NoteAgent 时必须逐字段保持这里的现状，因此快照如实锁定旧外观——capture 入口取消抛错、
//      capture 图内取消仍抛错、hash 不匹配无 errorCode、commitKey 重放不再写第二条笔记——
//      而不是把目标态提前写成现状。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRuntime, generationRequest, draft, memoryStorage } from './knowledge-dispatch-runtime.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(HERE, '..', '..', '..');
const RAW_DIR = join(REPO_ROOT, 'docs', 'specs', 'execution', 'v7-architecture-contracts', 'raw');
const TEST_FILE = 'scripts/arkts-lint/tests/v7-golden-dispatch.test.mjs';
const RECORD = process.env.V7_GOLDEN === 'record';

// ─────────────────────────────────────────────────────────────────────────────
// Fixtures: the LLM boundary is the only thing faked; the real Dispatcher,
// CaptureGraph, nodes, KnowledgeModel and common normalizers are loaded by the
// runtime harness. Keep these objects byte-stable: snapshots are recorded from
// them and replayed on every default-mode run.
// ─────────────────────────────────────────────────────────────────────────────

const CLASSIFICATION = {
  category: '概念',
  subject: '数学分析',
  chapter: '连续性',
  confidence: 0.95,
  cleaned_text: '函数在一点连续。',
};

const CAPTURE_JSON = {
  category: '概念',
  subject: '数学分析',
  chapter: '连续性',
  title: '连续函数',
  tags: ['连续'],
  difficulty: 1,
  importance: 3,
  fields: [{ key: 'definition', label: '定义', value: '函数在一点连续。' }],
};

function standardResponse() {
  const value = draft();
  delete value.sections[0].sourceIds;
  return {
    outline: {
      schemaVersion: 'mm-note-outline-v1',
      sections: [{ id: 'sec-1', label: '定义', order: 0, mustInclude: [] }],
    },
    draft: value,
  };
}

function deepResponse(request) {
  const prompt = request.messages[0].content;
  if (prompt.includes('read-only independent note verifier')) {
    return { status: 'supported', issues: [], evidenceStatuses: ['supported', 'supported'] };
  }
  const label = prompt.match(/section label=([^\n]+)/)[1];
  const value = draft(label.includes('公式') ? '公式：$\\pi$。' : '定义：\\(f(x)\\) 在一点连续。');
  value.sections[0].label = label;
  value.sections[0].sourceIds = [];
  return value;
}

function standardVerifier() {
  return { status: 'supported', issues: [], evidenceStatuses: ['supported'] };
}

// ─────────────────────────────────────────────────────────────────────────────
// normalize(x): pure, key-sorted projection. Applied to every record before it
// is written or compared, so a second recording is byte-identical.
// ─────────────────────────────────────────────────────────────────────────────

const TIMING_KEY = /(?:duration|elapsed|cost)ms$/i;
const TIMESTAMP_13 = /^\d{13}$/;
const ISO_TIMESTAMP = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/;
const ID_PATTERNS = [
  /^note-/i,
  /^unit-/i,
  /^src-/i,
  /^KB-/i,
  /^[0-9a-f]{8,}$/i,
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
];
const STRUCTURED_ID_KEYS = new Set(['commitKey', 'commitKeys', 'checkpointId', 'bestCheckpointId', 'runId']);

function isTimestamp(value) {
  if (typeof value === 'number') {
    return value > 1e12 && value < 1e13;
  }
  if (typeof value === 'string') {
    return TIMESTAMP_13.test(value) || ISO_TIMESTAMP.test(value);
  }
  return false;
}

function isIdString(value) {
  return ID_PATTERNS.some(pattern => pattern.test(value));
}

// Keep the shape of composite keys (e.g. "<id>:0", "<id>:<id>:<id>") while
// replacing every id-like segment. Numeric iteration suffixes and the literal
// "incremental" checkpoint suffix stay readable.
function normalizeStructuredId(value) {
  if (typeof value !== 'string') {
    return value;
  }
  return value.split(':').map(segment => {
    if (/^\d+$/.test(segment)) {
      return segment;
    }
    if (segment === 'incremental') {
      return segment;
    }
    return '<id>';
  }).join(':');
}

function normalize(value, key = '') {
  if (Array.isArray(value)) {
    return value.map(item => normalize(item, key));
  }
  if (value !== null && typeof value === 'object') {
    const sorted = {};
    for (const childKey of Object.keys(value).sort()) {
      if (TIMING_KEY.test(childKey)) {
        continue;
      }
      sorted[childKey] = normalize(value[childKey], childKey);
    }
    return sorted;
  }
  if (typeof value === 'number') {
    return isTimestamp(value) ? '<ts>' : value;
  }
  if (typeof value === 'string') {
    if (isTimestamp(value)) {
      return '<ts>';
    }
    if (STRUCTURED_ID_KEYS.has(key)) {
      return normalizeStructuredId(value);
    }
    if (isIdString(value)) {
      return '<id>';
    }
  }
  return value;
}

// ─────────────────────────────────────────────────────────────────────────────
// Seam projection: record the terminal outcome and storage facts, not the full
// transcript. readyPreview cases record an empty issueCodes list on purpose:
// soft verifier text is not part of the ADR-0019 terminal-state contract.
// ─────────────────────────────────────────────────────────────────────────────

function summarizeResult(result) {
  if (result === undefined || result === null) {
    return null;
  }
  const generation = result.generation;
  return {
    success: result.success,
    route: result.route,
    errorCode: result.errorCode ?? null,
    errorMessage: result.errorMessage ?? null,
    data: result.data === undefined || result.data === null ? null : {
      id: result.data.id,
      title: result.data.title,
      subject: result.data.subject,
      category: result.data.category,
      chapter: result.data.chapter,
      difficulty: result.data.difficulty,
      version: result.data.version,
      source: result.data.source,
    },
    classification: result.classification === undefined || result.classification === null ? null : {
      type: result.classification.type,
      subject: result.classification.subject,
      chapter: result.classification.chapter,
      confidence: result.classification.confidence,
      ocrText: result.classification.ocrText ?? null,
      ocrTextQuality: result.classification.ocrTextQuality ?? null,
    },
    generation: generation === undefined ? null : {
      runId: generation.runId,
      route: generation.route,
      status: generation.status,
      stopReason: generation.stopReason ?? null,
      bestCheckpointId: generation.bestCheckpointId ?? null,
      issueCodes: generation.status === 'ready-preview'
        ? []
        : (generation.issues ?? []).map(issue => issue.code),
      questions: generation.questions ?? [],
    },
  };
}

function summarizeStorage(storage) {
  const writes = storage?.writes ?? [];
  const commits = storage?.commits ?? [];
  return {
    noteCount: new Set(writes.map(write => write.id)).size,
    versions: writes.map(write => write.version),
    commitKeys: Array.from(new Set(commits.map(commit => commit.commitKey))),
  };
}

function summarizeRequests(requests) {
  return requests.map(request => ({
    maxTokens: request.maxTokens,
    enableThinking: request.enableThinking ?? null,
  }));
}

async function dispatch(runtime, request, options) {
  try {
    return { result: await runtime.dispatcher.dispatch(request, options) };
  } catch (error) {
    return { error };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Case matrix. Each case declares the serializable input/options descriptor and
// an executable fixture; observe() turns the executable result into the record
// that is written to raw/<case>.json.
// ─────────────────────────────────────────────────────────────────────────────

const captureInput = {
  source: 'app',
  payload: { kind: 'text', text: '函数在一点连续。' },
};

const emptyCaptureInput = {
  source: 'app',
  payload: { kind: 'text', text: '' },
};

const captureClassifyAndStructure = (_request, index) => index === 1 ? CLASSIFICATION : CAPTURE_JSON;

function lightInput() {
  return generationRequest('light');
}

function deepInput() {
  const request = generationRequest('deep');
  request.generation.sources.fragments.push({
    id: 'src-2',
    kind: 'conversation',
    originId: 'origin-2',
    sequence: 1,
    fingerprint: 'fp-2',
    text: '$$\n\\pi\n$$',
  });
  return request;
}

function needsInputRequest() {
  const request = generationRequest('light');
  request.generation.sources.fragments = [];
  return request;
}

function regenerateInput() {
  const request = generationRequest();
  request.generation.mode = 'regenerate';
  request.generation.targetNoteId = 'note-1';
  request.generation.baseVersion = 1;
  return request;
}

function regenerateRepository(baseVersion) {
  return async () => baseVersion === undefined ? undefined : {
    baseVersion,
    unit: { id: 'note-1', title: '连续性', content: '## 定义\n函数在一点连续。' },
    manifest: { noteId: 'note-1', baseVersion, sections: [], sourceIds: [], createdAt: 0 },
    sources: { fragments: [] },
  };
}

const mismatchCandidate = {
  id: 'note-1',
  title: '连续性',
  content: '## 定义\n函数在一点连续。',
  summary: '函数在一点连续。',
  tags: [],
  subject: '数学分析',
  category: '概念',
  chapter: '连续性',
  difficulty: 1,
  source: 'note_generation',
  createdAt: 0,
  updatedAt: 0,
  reviewStatus: 'new',
  nextReviewAt: 0,
  intervalDays: 1,
  easeFactor: 2.5,
  repetitions: 0,
  prerequisites: [],
  related: [],
  embedding: [],
  userId: '',
  version: 1,
};

const preparedInput = {
  source: 'text',
  payload: { kind: 'text', text: '函数在一点连续。' },
  preparedCandidate: {
    runId: 'baseline-run',
    checkpointId: 'baseline-run:0',
    candidateHash: '0000000000000000',
    commitKey: 'golden-commit',
    candidate: { title: '连续性', version: 1 },
  },
};

const CASES = [
  {
    name: 'capture-success',
    clause: 'ADR-0019 (a) capture / (b) committed',
    input: captureInput,
    options: { includeRawText: true, dao: true },
    zeroWrite: false,
    async run() {
      const runtime = createRuntime(captureClassifyAndStructure);
      const storage = memoryStorage();
      const outcome = await dispatch(runtime, captureInput, { includeRawText: true, dao: storage.dao });
      return { runtime, storage, ...outcome };
    },
    assert(obs) {
      assert.equal(obs.result.success, true);
      assert.equal(obs.result.route, 'D1');
      assert.equal(obs.result.data.version, 1);
      assert.equal(obs.storage.writes.length, 1);
      assert.equal(obs.storage.commits.length, 0);
    },
  },
  {
    name: 'capture-analysis-only',
    clause: 'ADR-0019 (a) analysisOnly / no persist',
    input: captureInput,
    options: { analysisOnly: true, includeRawText: true, dao: true },
    zeroWrite: true,
    async run() {
      const runtime = createRuntime(captureClassifyAndStructure);
      const storage = memoryStorage();
      const outcome = await dispatch(runtime, captureInput, {
        analysisOnly: true,
        includeRawText: true,
        dao: storage.dao,
      });
      return { runtime, storage, ...outcome };
    },
    assert(obs) {
      assert.equal(obs.result.success, true);
      assert.equal(obs.result.data, undefined);
      assert.equal(obs.storage.writes.length, 0);
    },
  },
  {
    name: 'capture-model-unavailable',
    clause: 'ADR-0019 (a) capture / (b) failed (MODEL_UNAVAILABLE target)',
    input: captureInput,
    options: { dao: true },
    zeroWrite: true,
    async run() {
      let runtime;
      runtime = createRuntime(() => {
        throw new runtime.common.LlmError('model unavailable', 'API_ERROR');
      });
      const storage = memoryStorage();
      const outcome = await dispatch(runtime, captureInput, { dao: storage.dao });
      return { runtime, storage, ...outcome };
    },
    assert(obs) {
      assert.equal(obs.result.success, false);
      assert.equal(obs.result.errorCode, undefined);
      assert.equal(obs.result.data, undefined);
      assert.equal(obs.storage.writes.length, 0);
    },
  },
  {
    name: 'capture-empty-input',
    clause: 'ADR-0019 (a) capture / (b) failed (input validation gap)',
    input: emptyCaptureInput,
    options: { dao: true },
    zeroWrite: true,
    async run() {
      const runtime = createRuntime();
      const storage = memoryStorage();
      const outcome = await dispatch(runtime, emptyCaptureInput, { dao: storage.dao });
      return { runtime, storage, ...outcome };
    },
    assert(obs) {
      assert.equal(obs.result.success, false);
      assert.equal(obs.storage.writes.length, 0);
    },
  },
  {
    name: 'capture-cancel-entry',
    clause: 'ADR-0019 (e) entry cancel / (c) CANCELLED',
    input: captureInput,
    options: { cancellation: 'entry', dao: true },
    zeroWrite: true,
    async run() {
      const runtime = createRuntime();
      const storage = memoryStorage();
      const token = new runtime.common.CancellationToken();
      token.cancel();
      const outcome = await dispatch(runtime, captureInput, { cancellationToken: token, dao: storage.dao });
      return { runtime, storage, ...outcome };
    },
    assert(obs) {
      assert.match(obs.error.message, /CONVERSATION_CANCELLED/);
      assert.equal(obs.runtime.requests.length, 0);
      assert.equal(obs.storage.writes.length, 0);
    },
  },
  {
    name: 'capture-cancel-in-graph',
    clause: 'ADR-0019 (e) in-graph cancel / (c) CANCELLED (现状：capture 仍抛错)',
    input: captureInput,
    options: { cancellation: 'in-graph', dao: true },
    zeroWrite: true,
    async run() {
      let token;
      const runtime = createRuntime(() => {
        token.cancel();
        return CLASSIFICATION;
      });
      token = new runtime.common.CancellationToken();
      const storage = memoryStorage();
      const outcome = await dispatch(runtime, captureInput, { cancellationToken: token, dao: storage.dao });
      return { runtime, storage, ...outcome };
    },
    assert(obs) {
      // The node observes the cancel (CaptureGraph rewrites it to NODE_ERROR),
      // but Dispatcher re-checks the token after graph.run and throws again.
      // For capture the NODE_ERROR kind is therefore not visible at the seam.
      assert.match(obs.error.message, /CONVERSATION_CANCELLED/);
      assert.equal(obs.runtime.requests.length, 1);
      assert.equal(obs.storage.writes.length, 0);
    },
  },
  {
    name: 'generation-light',
    clause: 'ADR-0019 (a) generation(light) / (b) readyPreview',
    input: lightInput(),
    options: { generationRepository: true, dao: true },
    zeroWrite: true,
    async run() {
      const runtime = createRuntime(() => draft());
      const storage = memoryStorage();
      const request = generationRequest('light');
      const outcome = await dispatch(runtime, request, {
        generationRepository: storage.repository,
        dao: storage.dao,
      });
      return { runtime, storage, ...outcome };
    },
    assert(obs) {
      assert.equal(obs.result.success, true);
      assert.equal(obs.result.generation.status, 'ready-preview');
      assert.equal(obs.storage.writes.length, 0);
    },
  },
  {
    name: 'generation-standard',
    clause: 'ADR-0019 (a) generation(standard) / (b) readyPreview',
    input: generationRequest('standard'),
    options: { generationRepository: true, dao: true },
    zeroWrite: true,
    async run() {
      const runtime = createRuntime(request => request.messages[0].content.includes('read-only independent note verifier')
        ? standardVerifier()
        : standardResponse());
      const storage = memoryStorage();
      const request = generationRequest('standard');
      const outcome = await dispatch(runtime, request, {
        generationRepository: storage.repository,
        dao: storage.dao,
      });
      return { runtime, storage, ...outcome };
    },
    assert(obs) {
      assert.equal(obs.result.success, true);
      assert.equal(obs.result.generation.status, 'ready-preview');
      assert.equal(obs.storage.writes.length, 0);
    },
  },
  {
    name: 'generation-deep',
    clause: 'ADR-0019 (a) generation(deep) / (b) readyPreview',
    input: deepInput(),
    options: { generationRepository: true, dao: true },
    zeroWrite: true,
    async run() {
      const runtime = createRuntime(deepResponse);
      const storage = memoryStorage();
      const request = generationRequest('deep');
      request.generation.sources.fragments.push({
        id: 'src-2',
        kind: 'conversation',
        originId: 'origin-2',
        sequence: 1,
        fingerprint: 'fp-2',
        text: '$$\n\\pi\n$$',
      });
      const outcome = await dispatch(runtime, request, {
        generationRepository: storage.repository,
        dao: storage.dao,
      });
      return { runtime, storage, ...outcome };
    },
    assert(obs) {
      assert.equal(obs.result.success, true);
      assert.equal(obs.result.generation.route, 'deep');
      assert.equal(obs.result.generation.status, 'ready-preview');
      assert.equal(obs.storage.writes.length, 0);
    },
  },
  {
    name: 'generation-needs-input',
    clause: 'ADR-0019 (a) generation / (b) needsInput / (c) MISSING_SOURCE',
    input: needsInputRequest(),
    options: {},
    zeroWrite: true,
    async run() {
      const runtime = createRuntime();
      const storage = memoryStorage();
      const request = needsInputRequest();
      const outcome = await dispatch(runtime, request, {});
      return { runtime, storage, ...outcome };
    },
    assert(obs) {
      assert.equal(obs.result.success, false);
      assert.equal(obs.result.generation.status, 'needs-input');
      assert.ok(obs.result.generation.issues.some(issue => issue.code.startsWith('MISSING_')));
      assert.equal(obs.runtime.requests.length, 0);
      assert.equal(obs.storage.writes.length, 0);
    },
  },
  {
    name: 'regenerate-version-conflict',
    clause: 'ADR-0019 (a) regenerate / (b) failed / (c) VERSION_CONFLICT',
    input: regenerateInput(),
    options: { generationRepository: true },
    zeroWrite: true,
    async run() {
      const runtime = createRuntime();
      const storage = memoryStorage();
      const repository = { ...storage.repository, getRegenerationBase: regenerateRepository(2) };
      const request = regenerateInput();
      const outcome = await dispatch(runtime, request, { generationRepository: repository });
      return { runtime, storage, ...outcome };
    },
    assert(obs) {
      assert.equal(obs.result.success, false);
      assert.equal(obs.result.errorCode, 'VERSION_CONFLICT');
      assert.equal(obs.storage.writes.length, 0);
    },
  },
  {
    name: 'regenerate-note-missing',
    clause: 'ADR-0019 (a) regenerate / (b) failed / (c) NOTE_NOT_FOUND',
    input: regenerateInput(),
    options: { generationRepository: true },
    zeroWrite: true,
    async run() {
      const runtime = createRuntime();
      const storage = memoryStorage();
      const repository = { ...storage.repository, getRegenerationBase: regenerateRepository(undefined) };
      const request = regenerateInput();
      const outcome = await dispatch(runtime, request, { generationRepository: repository });
      return { runtime, storage, ...outcome };
    },
    assert(obs) {
      assert.equal(obs.result.success, false);
      assert.equal(obs.result.errorCode, 'NOTE_NOT_FOUND');
      assert.equal(obs.storage.writes.length, 0);
    },
  },
  {
    name: 'prepared-candidate-hash-mismatch',
    clause: 'ADR-0019 (a) preparedCandidate / (b) failed / (c) APPROVAL_HASH_MISMATCH (现状无码)',
    input: preparedInput,
    options: {},
    zeroWrite: true,
    async run() {
      const runtime = createRuntime();
      const storage = memoryStorage();
      const request = {
        source: 'text',
        payload: { kind: 'text', text: '函数在一点连续。' },
        preparedCandidate: {
          runId: 'baseline-run',
          checkpointId: 'baseline-run:0',
          candidateHash: '0000000000000000',
          commitKey: 'golden-commit',
          candidate: mismatchCandidate,
        },
      };
      const outcome = await dispatch(runtime, request, {});
      return { runtime, storage, ...outcome };
    },
    assert(obs) {
      assert.equal(obs.result.success, false);
      assert.equal(obs.result.errorCode, undefined);
      assert.match(obs.result.errorMessage, /候选内容已变化/);
      assert.equal(obs.storage.writes.length, 0);
    },
  },
  {
    name: 'prepared-candidate-commit-and-replay',
    clause: 'ADR-0019 (a) preparedCandidate / (b) committed / (c) commitKey idempotency',
    input: preparedInput,
    options: { generationRepository: true, dao: true },
    zeroWrite: false,
    async run() {
      const runtime = createRuntime(() => draft());
      const storage = memoryStorage();
      const options = { generationRepository: storage.repository, dao: storage.dao };
      const preview = await runtime.dispatcher.dispatch(generationRequest('light'), options);
      const checkpoint = storage.checkpoints[0];
      const request = {
        ...generationRequest('light'),
        generation: undefined,
        preparedCandidate: {
          runId: 'baseline-run',
          checkpointId: checkpoint.id,
          candidate: preview.data,
          candidateHash: checkpoint.candidateHash,
          commitKey: 'golden-commit',
        },
      };
      const first = await runtime.dispatcher.dispatch(request, options);
      const replay = await runtime.dispatcher.dispatch(request, options);
      return { runtime, storage, result: first, replay };
    },
    assert(obs) {
      assert.equal(obs.result.success, true);
      assert.equal(obs.replay.success, true);
      assert.equal(obs.replay.data.id, obs.result.data.id);
      assert.equal(obs.storage.writes.length, 1);
      assert.ok(obs.storage.commits.length >= 1);
    },
  },
  {
    name: 'generation-cancel-in-graph',
    clause: 'ADR-0019 (e) in-graph cancel / (b) failed / (c) CANCELLED (light)',
    input: lightInput(),
    options: { cancellation: 'in-graph' },
    zeroWrite: true,
    async run() {
      let token;
      const runtime = createRuntime(() => {
        token.cancel();
        return draft();
      });
      token = new runtime.common.CancellationToken();
      const storage = memoryStorage();
      const request = generationRequest('light');
      const outcome = await dispatch(runtime, request, { cancellationToken: token });
      return { runtime, storage, ...outcome };
    },
    assert(obs) {
      assert.equal(obs.result.success, false);
      assert.equal(obs.result.generation.issues[0].code, 'CANCELLED');
      assert.equal(obs.storage.writes.length, 0);
    },
  },
];

const REQUIRED_CASES = [
  'capture-success',
  'capture-analysis-only',
  'capture-model-unavailable',
  'capture-empty-input',
  'capture-cancel-entry',
  'capture-cancel-in-graph',
  'generation-light',
  'generation-standard',
  'generation-deep',
  'generation-needs-input',
  'regenerate-version-conflict',
  'regenerate-note-missing',
  'prepared-candidate-hash-mismatch',
  'prepared-candidate-commit-and-replay',
];

// ─────────────────────────────────────────────────────────────────────────────
// Record / compare
// ─────────────────────────────────────────────────────────────────────────────

async function observe(caseDef) {
  const obs = await caseDef.run();
  const record = normalize({
    case: caseDef.name,
    clause: caseDef.clause,
    input: caseDef.input,
    options: caseDef.options,
    result: summarizeResult(obs.result),
    storage: summarizeStorage(obs.storage),
    requests: summarizeRequests(obs.runtime.requests),
    throws: obs.error ? { name: obs.error.name, message: obs.error.message } : null,
  });
  return { record, obs };
}

function snapshotPath(name) {
  return join(RAW_DIR, `${name}.json`);
}

function relativeSnapshotPath(name) {
  return `docs/specs/execution/v7-architecture-contracts/raw/${name}.json`;
}

function fieldDiff(expected, actual, prefix = '') {
  if (Object.is(expected, actual)) {
    return [];
  }
  if (Array.isArray(expected) || Array.isArray(actual)) {
    if (!Array.isArray(expected) || !Array.isArray(actual)) {
      return [`${prefix}: expected ${JSON.stringify(expected)}, actual ${JSON.stringify(actual)}`];
    }
    const lines = [];
    const length = Math.max(expected.length, actual.length);
    for (let index = 0; index < length; index += 1) {
      const child = `${prefix}[${index}]`;
      if (index >= expected.length) {
        lines.push(`${child}: expected <missing>, actual ${JSON.stringify(actual[index])}`);
      } else if (index >= actual.length) {
        lines.push(`${child}: expected ${JSON.stringify(expected[index])}, actual <missing>`);
      } else {
        lines.push(...fieldDiff(expected[index], actual[index], child));
      }
    }
    return lines;
  }
  if (expected !== null && actual !== null && typeof expected === 'object' && typeof actual === 'object') {
    const lines = [];
    const keys = Array.from(new Set([...Object.keys(expected), ...Object.keys(actual)])).sort();
    for (const key of keys) {
      const child = prefix.length === 0 ? key : `${prefix}.${key}`;
      if (!(key in expected)) {
        lines.push(`${child}: expected <missing>, actual ${JSON.stringify(actual[key])}`);
      } else if (!(key in actual)) {
        lines.push(`${child}: expected ${JSON.stringify(expected[key])}, actual <missing>`);
      } else {
        lines.push(...fieldDiff(expected[key], actual[key], child));
      }
    }
    return lines;
  }
  return [`${prefix}: expected ${JSON.stringify(expected)}, actual ${JSON.stringify(actual)}`];
}

for (const caseDef of CASES) {
  test(caseDef.name, async () => {
    const { record, obs } = await observe(caseDef);
    if (caseDef.assert !== undefined) {
      caseDef.assert(obs);
    }
    if (caseDef.zeroWrite === true) {
      assert.equal(obs.storage.writes.length, 0, `${caseDef.name} must not write a note`);
    }
    if (RECORD) {
      mkdirSync(RAW_DIR, { recursive: true });
      writeFileSync(snapshotPath(caseDef.name), `${JSON.stringify(record, null, 2)}\n`, 'utf8');
      return;
    }
    const file = snapshotPath(caseDef.name);
    assert.ok(existsSync(file), `Missing golden snapshot ${relativeSnapshotPath(caseDef.name)}. `
      + `Record it with: V7_GOLDEN=record node --test ${TEST_FILE}`);
    const expected = JSON.parse(readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
    const lines = fieldDiff(expected, record);
    if (lines.length > 0) {
      assert.fail(`Golden snapshot mismatch for ${caseDef.name} (${relativeSnapshotPath(caseDef.name)}):\n`
        + lines.join('\n'));
    }
  });
}

test('golden matrix covers every required ADR-0019 case', () => {
  const names = new Set(CASES.map(caseDef => caseDef.name));
  for (const required of REQUIRED_CASES) {
    assert.ok(names.has(required), `missing required case: ${required}`);
  }
  assert.ok(CASES.length >= 14, `expected at least 14 cases, found ${CASES.length}`);
});

test('normalize is byte-stable across two runs of the idempotent commit case', async () => {
  const caseDef = CASES.find(item => item.name === 'prepared-candidate-commit-and-replay');
  assert.ok(caseDef, 'prepared-candidate-commit-and-replay case must exist');
  const first = await observe(caseDef);
  const second = await observe(caseDef);
  assert.equal(JSON.stringify(first.record), JSON.stringify(second.record));
});

test('normalize removes timing fields and maps timestamps plus ids', () => {
  const normalized = normalize({
    durationMs: 1,
    elapsedMs: 2,
    costMs: 3,
    createdAt: 1700000000000,
    iso: '2026-10-27T00:00:00Z',
    id: 'src-1',
    hash: 'deadbeef',
    note: { id: 'KB-abc', updatedAt: 1700000000000 },
    checkpointId: 'baseline-run:0',
    runId: 'baseline-run',
    commitKey: 'baseline-run:baseline-run:0:deadbeef',
    commitKeys: ['baseline-run:baseline-run:0:deadbeef'],
  });
  assert.deepEqual(normalized, {
    createdAt: '<ts>',
    iso: '<ts>',
    id: '<id>',
    hash: '<id>',
    note: { id: '<id>', updatedAt: '<ts>' },
    checkpointId: '<id>:0',
    runId: '<id>',
    commitKey: '<id>:<id>:0:<id>',
    commitKeys: ['<id>:<id>:0:<id>'],
  });
});
