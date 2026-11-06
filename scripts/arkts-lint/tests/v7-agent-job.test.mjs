// 路径: scripts/arkts-lint/tests/v7-agent-job.test.mjs
// 职责: spec 040 P0 —— agent_job 持久队列的模型纯函数、schema v20 与 DAO 契约守卫。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');
const models = loadNoteReviewEtsModule('common/src/main/ets/models/AgentJobModels.ets');

test('P0 模型：终态集合 / 优先级 / 恢复判定', () => {
  assert.equal(models.isTerminalAgentJobStatus('done'), true);
  assert.equal(models.isTerminalAgentJobStatus('failed'), true);
  assert.equal(models.isTerminalAgentJobStatus('cancelled'), true);
  assert.equal(models.isTerminalAgentJobStatus('queued'), false);
  assert.equal(models.isTerminalAgentJobStatus('running'), false);
  assert.equal(models.agentJobPriorityRank('interactive'), 0);
  assert.equal(models.agentJobPriorityRank('background'), 1);
  assert.equal(models.shouldRecoverAgentJob('queued', 0, 100), true);
  assert.equal(models.shouldRecoverAgentJob('running', 50, 100), true);
  assert.equal(models.shouldRecoverAgentJob('running', 150, 100), false);
  assert.equal(models.shouldRecoverAgentJob('done', 0, 100), false);
});

test('P0 schema：v20 新增 agent_job 表/索引且为 additive', () => {
  const db = read('common/src/main/ets/DatabaseHelper.ets');
  assert.match(db, /const DB_SCHEMA_VERSION: number = 22/);
  assert.match(db, /CREATE TABLE IF NOT EXISTS agent_job \(/);
  for (const column of ['job_id', 'kind', 'priority', 'payload_text', 'source', 'status',
    'attempt', 'fingerprint', 'lease_owner', 'lease_expires_at', 'error', 'created_at', 'updated_at']) {
    assert.match(db, new RegExp('\\b' + column + '\\b'));
  }
  assert.match(db, /CREATE INDEX IF NOT EXISTS idx_agent_job_pick/);
  assert.match(db, /CREATE UNIQUE INDEX IF NOT EXISTS idx_agent_job_active_fp/);
  assert.match(db, /WHERE status IN \('queued', 'running'\)/);
  assert.match(db, /SQL_CREATE_AGENT_JOB,/);
  assert.match(db, /SQL_INDEX_AGENT_JOB_ACTIVE_FP,/);
  assert.doesNotMatch(db, /DROP TABLE IF EXISTS agent_job/);
});

test('P0 DAO：入队按 fingerprint 去重（queued/running）', () => {
  const dao = read('entry/src/main/ets/database/AgentJobDao.ets');
  assert.match(dao, /async enqueue\(input: AgentJobEnqueueInput\): Promise<AgentJobEnqueueResult>/);
  assert.match(dao, /findActiveByFingerprint/);
  assert.match(dao, /status IN \('queued', 'running'\)/);
  assert.match(dao, /reused: true/);
  assert.match(dao, /唯一索引|部分唯一/);
});

test('P0 DAO：claim 事务内条件更新 + 租约', () => {
  const dao = read('entry/src/main/ets/database/AgentJobDao.ets');
  assert.match(dao, /async claim\(owner: string, leaseMs: number\): Promise<AgentJob \| null>/);
  assert.match(dao, /createTransaction/);
  assert.match(dao, /ORDER BY CASE priority WHEN 'interactive' THEN 0 ELSE 1 END, created_at ASC/);
  assert.match(dao, /predicates\.equalTo\('status', 'queued'\)/);
  assert.match(dao, /'lease_expires_at': now \+ leaseMs/);
  assert.match(dao, /rows === 0/);
  assert.match(dao, /transaction\.rollback\(\)/);
});

test('P0 DAO：恢复过期租约（attempt+1 / 达上限 failed）与终态回写', () => {
  const dao = read('entry/src/main/ets/database/AgentJobDao.ets');
  assert.match(dao, /async recoverExpired\(now: number, maxAttempt: number = MAX_ATTEMPT\): Promise<number>/);
  assert.match(dao, /attempt = attempt \+ 1/);
  assert.match(dao, /CASE WHEN attempt \+ 1 >= \? THEN 'failed' ELSE 'queued' END/);
  assert.match(dao, /WHERE status = 'running' AND lease_expires_at > 0 AND lease_expires_at < \?/);
  assert.match(dao, /async markDone/);
  assert.match(dao, /async markFailed/);
  assert.match(dao, /async markCancelled/);
  assert.match(dao, /async countByStatus/);
  assert.match(dao, /async queryJob/);
});

test('P0 边界：DAO 不在 common（受 Kit 限制）、调度器不直接写 SQL', () => {
  const dao = read('entry/src/main/ets/database/AgentJobDao.ets');
  assert.match(dao, /from '@kit\.ArkData'/);
  const scheduler = read('entry/src/main/ets/services/WriteJobScheduler.ets');
  assert.doesNotMatch(scheduler, /CREATE TABLE|INSERT INTO agent_job|SELECT .* agent_job/);
});
