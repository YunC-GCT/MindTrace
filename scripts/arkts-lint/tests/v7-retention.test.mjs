// 路径: scripts/arkts-lint/tests/v7-retention.test.mjs
// 职责: A2A 上下文文件（7 天）与 run/job 历史（30 天）的保留清理接线。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

test('A2A context files are pruned after 7 days', () => {
  const conversation = read('entry/src/main/ets/services/A2AConversationStore.ets');
  assert.match(conversation, /static prune\(context: common\.Context, maxAgeMs: number\): number/);
  const image = read('entry/src/main/ets/services/A2AImageContextStore.ets');
  assert.match(image, /static prune\(context: common\.Context, maxAgeMs: number\): number/);
  const plan = read('entry/src/main/ets/services/A2APlanStore.ets');
  assert.match(plan, /static prune\(context: common\.Context, maxAgeMs: number\): number/);
  const cleanup = read('entry/src/main/ets/services/A2AContextCleanup.ets');
  assert.match(cleanup, /A2A_CONTEXT_MAX_AGE_MS: number = 7 \* 24 \* 60 \* 60 \* 1000/);
  assert.match(cleanup, /A2AConversationStore\.prune/);
  assert.match(cleanup, /A2AImageContextStore\.prune/);
  assert.match(cleanup, /A2APlanStore\.prune/);
  const controller = [
    read('entry/src/main/ets/services/A2AController.ets'),
    read('entry/src/main/ets/services/A2AIngestHandler.ets'),
    read('entry/src/main/ets/services/A2AConstants.ets'),
  ].join('\n');
  assert.match(controller, /A2AContextCleanup\.run\(this\.context\)/);
});

test('DB run records and terminal jobs are pruned after 30 days', () => {
  const db = read('common/src/main/ets/DatabaseHelper.ets');
  assert.match(db, /idx_run_event_created_at ON run_event\(created_at\)/);
  assert.match(db, /idx_run_store_created_at ON run_store\(created_at\)/);
  assert.match(db, /idx_agent_job_updated ON agent_job\(status, updated_at\)/);
  const service = read('entry/src/main/ets/services/DataRetentionService.ets');
  assert.match(service, /RETENTION_DAYS: number = 30/);
  assert.match(service, /deleteOlder/);
  assert.match(service, /deleteTerminalOlder/);
  assert.match(service, /RUN_TERMINAL_STATUSES/);
  assert.match(service, /JOB_TERMINAL_STATUSES/);
  const entry = read('entry/src/main/ets/entryability/EntryAbility.ets');
  assert.match(entry, /DataRetentionService\.run\(this\.context\)/);
});
