// #238 切片 A1/A2：PersistNode 走 NoteWritePort 的节点级契约测试。
// 装载真实 PersistNode 源码；端口用 fake，不碰 RDB。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');

class NotePortError extends Error {
  constructor(code, message, retryable) {
    super(message);
    this.name = 'NotePortError';
    this.code = code;
    this.retryable = retryable;
  }
}

const mod = loadNoteReviewEtsModule('agents/src/main/ets/graph/nodes/PersistNode.ets', {
  mocks: { common: { NotePortError } },
});
const PersistNodeFactory = mod.PersistNodeFactory;

function state(overrides = {}) {
  return {
    captureText: '',
    source: 'manual',
    currentStep: 'truth_check',
    persist: true,
    analysisOnly: false,
    subjectVocabulary: [],
    ...overrides,
  };
}

function unit() {
  return { id: 'note-1', title: 't', summary: 's', content: 'c', tags: [], subject: '数学', category: '计算题', chapter: '极限', difficulty: 2, source: 'manual', createdAt: 1, updatedAt: 2, reviewStatus: 'new', nextReviewAt: 0, intervalDays: 0, easeFactor: 2.5, repetitions: 0, prerequisites: [], related: [], embedding: [], userId: 'local', version: 1 };
}

function outcome(overrides = {}) {
  return { noteId: 'note-1', version: 1, commitKey: 'capture:note-1', duplicate: false, committed: true, cancelled: false, ...overrides };
}

function portOf(behaviour) {
  const calls = [];
  return {
    calls,
    commit: async (u, command) => {
      calls.push({ unit: u, command });
      if (behaviour === 'throw') {
        throw new NotePortError('VERSION_CONFLICT', 'race lost', false);
      }
      return outcome({ commitKey: command.commitKey, duplicate: behaviour === 'duplicate' });
    },
  };
}

test('persist=false skips the port entirely', async () => {
  const port = portOf('ok');
  const node = PersistNodeFactory.createWithWritePort(port);
  const result = await node(state({ persist: false, knowledgeUnit: unit() }));
  assert.equal(port.calls.length, 0);
  assert.equal(result.state.error, undefined);
});

test('missing knowledgeUnit fails with PERSIST_NO_UNIT before calling the port', async () => {
  const port = portOf('ok');
  const node = PersistNodeFactory.createWithWritePort(port);
  const result = await node(state());
  assert.equal(result.state.error.kind, 'PERSIST_NO_UNIT');
  assert.equal(result.state.error.retriable, false);
  assert.equal(port.calls.length, 0);
});

test('plain capture synthesises a stable commitKey and reports success', async () => {
  const port = portOf('ok');
  const node = PersistNodeFactory.createWithWritePort(port);
  const result = await node(state({ knowledgeUnit: unit() }));
  assert.equal(port.calls.length, 1);
  assert.equal(port.calls[0].command.commitKey, 'capture:note-1');
  assert.equal(result.state.commitResult.success, true);
  assert.equal(result.state.commitResult.duplicate, false);
});

test('preparedCandidate carries commitKey, expectedVersion and run metadata', async () => {
  const port = portOf('ok');
  const node = PersistNodeFactory.createWithWritePort(port);
  const result = await node(state({
    knowledgeUnit: unit(),
    preparedCandidate: {
      runId: 'run-9',
      checkpointId: 'cp-1',
      candidateHash: 'hash-1',
      commitKey: 'commit-9',
      pendingSourceIds: ['src-1'],
      expectedVersion: 3,
      updateExisting: true,
    },
  }));
  const command = port.calls[0].command;
  assert.equal(command.commitKey, 'commit-9');
  assert.equal(command.expectedVersion, 3);
  assert.equal(command.runId, 'run-9');
  assert.equal(command.checkpointId, 'cp-1');
  assert.deepEqual(Array.from(command.sourceIds), ['src-1']);
  assert.equal(result.state.commitResult.duplicate, false);
});

test('duplicate replay surfaces in commitResult', async () => {
  const port = portOf('duplicate');
  const node = PersistNodeFactory.createWithWritePort(port);
  const result = await node(state({ knowledgeUnit: unit() }));
  assert.equal(result.state.commitResult.duplicate, true);
});

test('NotePortError maps to a structured node error with retryable preserved', async () => {
  const port = portOf('throw');
  const node = PersistNodeFactory.createWithWritePort(port);
  const result = await node(state({ knowledgeUnit: unit() }));
  assert.equal(result.state.error.kind, 'VERSION_CONFLICT');
  assert.equal(result.state.error.retriable, false);
  assert.equal(result.state.error.step, 'persist');
});

// ==================== A2：preparedCandidate 写路径接端口 ====================

test('PreparedBranch accepts and prefers noteWritePort (A2, 2026-10-31 抽出)', () => {
  const dispatcher = read('agents/src/main/ets/core/Dispatcher.ets');
  const branch = read('agents/src/main/ets/core/dispatch/PreparedBranch.ets');
  assert.match(dispatcher, /PreparedBranch\.dispatch\(\s*req, prepared, options, startedAt/);
  assert.match(branch, /static buildGraph\(dao\?: NoteDaoInterface, noteWritePort\?: NoteWritePort\)/);
  assert.match(branch, /PersistNodeFactory\.createWithWritePort\(noteWritePort\)/);
});

test('AiService wires the port on capture, captureSet and prepared dispatch (A1+A2)', () => {
  const aiService = read('entry/src/main/ets/services/AiService.ets');
  // 2026-10-31：端口装配抽到 services/ai/AiServicePorts（AiService 拆分切片 2）。
  const ports = read('entry/src/main/ets/services/ai/AiServicePorts.ets');
  const commit = read('entry/src/main/ets/services/ai/DraftCommitService.ets');
  const capture = read('entry/src/main/ets/services/ai/CapturePipeline.ets');
  const wired = capture.match(/noteWritePort: await AiServicePorts\.buildNoteWritePort\(/g) ?? [];
  const wiredCommit = commit.match(/noteWritePort: await AiServicePorts\.buildNoteWritePort\(/g) ?? [];
  assert.equal(Array.from(wired).length, 2, 'capture / captureSet 两处注入端口（preparedCandidate 在 DraftCommitService）');
  assert.equal(Array.from(wiredCommit).length, 1, 'preparedCandidate 注入端口');
  assert.match(ports, /NoteWritePortFactory\.create\(/);
  assert.doesNotMatch(aiService, /new NoteDao\(|from ['"]\.\.\/database/);
});
