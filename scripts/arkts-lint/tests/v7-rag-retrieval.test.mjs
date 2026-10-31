// 路径: scripts/arkts-lint/tests/v7-rag-retrieval.test.mjs
// 职责: 037 RAG 一期契约——查询规划（纯函数）+ schema v19 note_fts + 写路径同步守卫。
// Why: trigram 要求 ≥3 字查询；<3 字必须走 LIKE；索引写入/删除必须跟知识库主写一致（失败只降级不阻塞）。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

const planModule = loadNoteReviewEtsModule('entry/src/main/ets/services/RagQueryPlan.ets');
const planRagQuery = planModule.planRagQuery;

test('queries with 3+ characters use FTS5 MATCH with rank ordering', () => {
  const plan = planRagQuery('连续性');
  assert.equal(plan.mode, 'fts');
  assert.ok(plan.sql.includes('note_fts MATCH ?'));
  assert.ok(plan.sql.includes('ORDER BY rank'));
});

test('2-character queries fall back to LIKE substring scan', () => {
  const plan = planRagQuery('极限');
  assert.equal(plan.mode, 'like');
  assert.ok(plan.sql.includes('LIKE ?'));
  assert.ok(plan.sql.includes('title LIKE ?'));
});

test('blank query still produces a deterministic plan (caller rejects empty)', () => {
  const plan = planRagQuery('   ');
  assert.equal(plan.mode, 'like');
});

test('schema v19 creates note_fts with trigram tokenizer and backfills from knowledge_unit', () => {
  const db = read('common/src/main/ets/DatabaseHelper.ets');
  assert.match(db, /DB_SCHEMA_VERSION: number = 19/);
  assert.match(db, /CREATE VIRTUAL TABLE IF NOT EXISTS note_fts USING fts5\(/);
  assert.match(db, /tokenize='trigram'/);
  assert.match(db, /SQL_BACKFILL_NOTE_FTS/);
  assert.match(db, /INSERT INTO note_fts \(title, content, unit_id, subject, chapter\)/);
  assert.match(db, /FROM knowledge_unit/);
});

test('note_fts is kept in sync on create/update/delete, best-effort only', () => {
  const index = read('entry/src/main/ets/database/NoteFtsIndex.ets');
  assert.match(index, /static async upsert\(unit: KnowledgeUnit\)/);
  assert.match(index, /static async remove\(unitId: string\)/);
  assert.match(index, /DELETE FROM note_fts WHERE unit_id = \?/);
  const write = read('entry/src/main/ets/services/KnowledgeUnitWriteService.ets');
  assert.ok((write.match(/await NoteFtsIndex\.upsert\(persisted\.unit\)/g) ?? []).length >= 2,
    'create 与 update 都要同步索引');
  const dao = read('entry/src/main/ets/database/NoteDao.ets');
  assert.match(dao, /await NoteFtsIndex\.remove\(id\)/);
});

test('RagRetrievalService.search uses the plan and returns empty on failure', () => {
  const service = read('entry/src/main/ets/services/RagRetrievalService.ets');
  assert.match(service, /static async search\(store: relationalStore\.RdbStore, query: string, topK: number\): Promise<RagHit\[\]>/);
  assert.match(service, /const plan: RagQueryPlan = planRagQuery\(trimmed\)/);
  assert.match(service, /plan\.mode === 'fts'/);
  assert.match(service, /return \[\];/);
});


test('NoteEvidenceService prefers local FTS recall and falls back to note.search', () => {
  const evidence = read('entry/src/main/ets/services/NoteEvidenceService.ets');
  assert.match(evidence, /RagRetrievalService\.search\(store, query, topK\)/);
  assert.match(evidence, /private async queryHitsByFts\(/);
  assert.match(evidence, /queryLiveRows\(store, ids\)/);
  assert.match(evidence, /matchedFields: \['content'\]/);
  // fallback：FTS 不可用/无命中时仍走既有 note.search 工具
  assert.match(evidence, /EVIDENCE_TOOL_NAME/);
});
