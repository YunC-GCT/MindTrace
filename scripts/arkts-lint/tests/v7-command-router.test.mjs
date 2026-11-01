// 路径: scripts/arkts-lint/tests/v7-command-router.test.mjs
// 职责: spec 039 S1 —— CommandRouter 的路由表与 preflight（取消 / 审批哈希前置）契约。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');
const mod = loadNoteReviewEtsModule('agents/src/main/ets/core/CommandRouter.ets', {
  mocks: { common: { isRetryableNoteErrorCode: () => false, NOTE_CANCELLED_MESSAGE: 'CONVERSATION_CANCELLED' } },
});
const { CommandRouter } = mod;

const command = (kind, extra = {}) => ({ kind, operationId: 'op-' + kind, source: 'app', ...extra });

test('路由表：五种 NoteCommand.kind 映射到四条 workflow', async () => {
  const router = new CommandRouter();
  assert.equal(router.resolve(command('capture')), 'capture');
  assert.equal(router.resolve(command('analysisOnly')), 'capture');
  assert.equal(router.resolve(command('generation', { generation: { mode: 'create' } })), 'generation');
  assert.equal(router.resolve(command('regenerate')), 'regenerate');
  assert.equal(router.resolve(command('generation', { generation: { mode: 'regenerate' } })), 'regenerate');
  assert.equal(router.resolve(command('preparedCandidate', {
    preparedCandidate: { runId: 'r', checkpointId: 'c', candidateHash: 'h' },
  })), 'prepared');
});

test('preflight：已取消令牌 → cancelled 终态，不进入 workflow', async () => {
  const router = new CommandRouter();
  const result = await router.preflight(command('capture'), {
    cancellationToken: { isCancelled: () => true },
  });
  assert.equal(result.outcome.kind, 'cancelled');
  assert.equal(result.errorCode, undefined);
});

test('preflight：普通命令放行', async () => {
  const router = new CommandRouter();
  const result = await router.preflight(command('capture'), {});
  assert.equal(result.outcome, undefined);
  assert.equal(result.errorCode, undefined);
});

test('preflight：preparedCandidate 检查点缺失 → PREPARED_CHECKPOINT_MISSING', async () => {
  const router = new CommandRouter();
  const result = await router.preflight(command('preparedCandidate', {
    preparedCandidate: { runId: 'run-1', checkpointId: 'cp-1', candidateHash: 'hash-1' },
  }), {
    generationRepository: { restore: async () => undefined },
  });
  assert.equal(result.errorCode, 'PREPARED_CHECKPOINT_MISSING');
  assert.equal(result.retryable, false);
});

test('preflight：preparedCandidate 哈希不符 → APPROVAL_HASH_MISMATCH', async () => {
  const router = new CommandRouter();
  const result = await router.preflight(command('preparedCandidate', {
    preparedCandidate: { runId: 'run-1', checkpointId: 'cp-1', candidateHash: 'hash-1' },
  }), {
    generationRepository: {
      restore: async () => ({ checkpoints: [{ id: 'cp-1', candidateHash: 'hash-other', approvedAt: 1 }] }),
    },
  });
  assert.equal(result.errorCode, 'APPROVAL_HASH_MISMATCH');
});

test('preflight：未审批检查点 → APPROVAL_HASH_MISMATCH；已审批放行', async () => {
  const router = new CommandRouter();
  const repository = {
    restore: async () => ({ checkpoints: [{ id: 'cp-1', candidateHash: 'hash-1', approvedAt: 0 }] }),
  };
  const denied = await router.preflight(command('preparedCandidate', {
    preparedCandidate: { runId: 'run-1', checkpointId: 'cp-1', candidateHash: 'hash-1' },
  }), { generationRepository: repository });
  assert.equal(denied.errorCode, 'APPROVAL_HASH_MISMATCH');
  repository.restore = async () => ({ checkpoints: [{ id: 'cp-1', candidateHash: 'hash-1', approvedAt: 99 }] });
  const allowed = await router.preflight(command('preparedCandidate', {
    preparedCandidate: { runId: 'run-1', checkpointId: 'cp-1', candidateHash: 'hash-1' },
  }), { generationRepository: repository });
  assert.equal(allowed.errorCode, undefined);
  assert.equal(allowed.outcome, undefined);
});

test('边界：router 不 import DAO / 写端口 / workflow 实现', () => {
  const source = read('agents/src/main/ets/core/CommandRouter.ets');
  assert.doesNotMatch(source, /NoteDaoInterface/);
  assert.doesNotMatch(source, /KnowledgeUnitWriteService/);
  assert.doesNotMatch(source, /workflows\//);
  assert.match(source, /resolve\(command: NoteCommand\): NoteWorkflowId/);
});
