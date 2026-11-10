// ADR-0019 (d) / v18：HITL 审批哈希落位守卫（schema + 模型 + 仓储 + 分支 + 写端口）。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

test('schema v18 adds note_generation_checkpoint.approved_at', () => {
  const db = read('common/src/main/ets/DatabaseHelper.ets');
  assert.match(db, /DB_SCHEMA_VERSION: number = 23/);
  assert.match(db, /SQL_MIGRATE_CHECKPOINT_APPROVED/);
  assert.match(db, /ALTER TABLE note_generation_checkpoint ADD COLUMN approved_at INTEGER NOT NULL DEFAULT 0/);
  assert.match(db, /hasColumn\(store, "note_generation_checkpoint", "approved_at"\)/);
});

test('checkpoint model and repository persist the approval marker', () => {
  const models = read('common/src/main/ets/models/NoteGenerationModels.ets');
  const repo = read('entry/src/main/ets/database/NoteGenerationRepository.ets');
  assert.match(models, /approvedAt\?: number/);
  assert.match(repo, /'approved_at': checkpoint\.approvedAt \?\? 0/);
  assert.match(repo, /approvedAt: NoteGenerationRepository\.readOptionalNumber\(rs, 'approved_at'\)/);
  assert.match(repo, /async markCheckpointApproved\(runId: string, checkpointId: string, candidateHash: string, approvedAt: number\)/);
  assert.match(repo, /async getCheckpoint\(runId: string, checkpointId: string\)/);
});

test('HITL confirm marks approval before building the prepared candidate', () => {
  const commit = read('entry/src/main/ets/services/ai/DraftCommitService.ets');
  assert.match(commit, /markCheckpointApproved\(event\.runId, checkpoint\.id, approvedHash, Date\.now\(\)\)/);
  const approvedIdx = commit.indexOf('markCheckpointApproved');
  const preparedIdx = commit.indexOf('const prepared: PreparedCandidate');
  assert.ok(approvedIdx >= 0 && preparedIdx > approvedIdx, 'approval must be marked before the prepared candidate is built');
});

test('prepared branch forwards the approval hash to the port', () => {
  const node = read('agents/src/main/ets/graph/nodes/PersistNode.ets');
  assert.match(node, /command\.approvedCheckpointHash = candidate\.candidateHash/);
});

test('write store rejects mismatched or unapproved checkpoints', () => {
  const store = read('entry/src/main/ets/database/KnowledgeUnitNoteWriteStore.ets');
  assert.match(store, /async validateApproval\(command: NoteWriteCommand\)/);
  assert.match(store, /APPROVAL_HASH_MISMATCH/);
  assert.match(store, /approvedAt <= 0 \|\| checkpoint\.candidateHash !== hash/);
  const insertIdx = store.indexOf('await this.validateApproval(command);');
  assert.ok(insertIdx >= 0);
});


test('getCheckpoint queries an explicit column list and logs mismatches (device-safe)', () => {
  const repo = read('entry/src/main/ets/database/NoteGenerationRepository.ets');
  assert.match(repo, /const columns: string\[\] = \[/);
  assert.match(repo, /'approved_at',/);
  assert.doesNotMatch(repo, /store\.query\(predicates, \[\]\)/);
  const store = read('entry/src/main/ets/database/KnowledgeUnitNoteWriteStore.ets');
  assert.match(store, /approval mismatch runId=/);
});


test('unedited draft approves the generation checkpoint in place (design fix)', () => {
  const commit = read('entry/src/main/ets/services/ai/DraftCommitService.ets');
  assert.match(commit, /if \(previous\.candidateHash === editedHash\) \{\s*return previous;/);
});

test('edited draft creates a hash-keyed checkpoint row (re-edit safe)', () => {
  const commit = read('entry/src/main/ets/services/ai/DraftCommitService.ets');
  assert.match(commit, /id: event\.runId \+ ':user-edit:' \+ editedHash\.substring\(0, 8\)/);
});

test('markCheckpointApproved reads the row first, then updates by id+run_id', () => {
  const repo = read('entry/src/main/ets/database/NoteGenerationRepository.ets');
  assert.match(repo, /const checkpoint: NoteGenerationCheckpoint \| null = await this\.getCheckpoint\(runId, checkpointId\)/);
  assert.match(repo, /checkpoint\.candidateHash !== candidateHash/);
  assert.match(repo, /predicates\.equalTo\('id', checkpointId\)\.and\(\)\.equalTo\('run_id', runId\)/);
});

test('markCheckpointApproved fails loudly when no row matches', () => {
  const repo = read('entry/src/main/ets/database/NoteGenerationRepository.ets');
  assert.match(repo, /markCheckpointApproved matched no checkpoint row/);
  assert.match(repo, /const updatedRows: number = await this\.store\.update\(bucket, predicates\)/);
});


test('main graph preflight enforces approval before write (A4 4e)', () => {
  const router = read('agents/src/main/ets/core/CommandRouter.ets');
  assert.match(router, /private static async preflightApproval\(/);
  assert.match(router, /await CommandRouter\.preflightApproval\(command, options\)/);
  assert.match(router, /PREPARED_CHECKPOINT_MISSING/);
  assert.match(router, /'APPROVAL_HASH_MISMATCH'/);
  assert.match(router, /approvedAt !== undefined && approvedAt <= 0/);
});

test('A2A ingest records a receipt and reports the count (P4)', () => {
  const controller = [
    read('entry/src/main/ets/services/A2AController.ets'),
    read('entry/src/main/ets/services/A2AIngestHandler.ets'),
    read('entry/src/main/ets/services/A2AConstants.ets'),
    read('entry/src/main/ets/services/A2AAnswerHandler.ets'),
    read('entry/src/main/ets/services/A2ASession.ets'),
  ].join('\n');
  assert.match(controller, /recordA2aIngestReceipt\(\): void/);
  assert.match(controller, /source: 'a2a'/);
  assert.match(controller, /本次整理 1 条/);
  const receipt = read('entry/src/main/ets/services/CaptureReceipt.ets');
  assert.match(receipt, /本次整理 ' \+ receipt\.total\.toString\(\) \+ ' 条/);
});
