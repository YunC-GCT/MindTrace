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
  assert.match(db, /DB_SCHEMA_VERSION: number = 20/);
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
  assert.ok((write.match(/this\.finalizeWrite\(/g) ?? []).length >= 4,
    '四条写路径（create/update + commitKey 变体）统一走 finalizeWrite');
  assert.match(write, /NoteFtsIndex\.upsert\(unit\), INDEX_SYNC_TIMEOUT_MS/);
  assert.match(write, /writeSection\.runExclusive/);
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


test('evidence search prefers local FTS recall and falls back to note.search', () => {
  const evidence = read('entry/src/main/ets/services/RagNoteEvidenceSearch.ets');
  assert.match(evidence, /RagRetrievalService\.search\(store, query, topK\)/);
  assert.match(evidence, /private async queryHitsByFts\(/);
  assert.match(evidence, /queryLiveRows\(store, ids\)/);
  assert.match(evidence, /matchedFields: \['content'\]/);
  // fallback：FTS 不可用/无命中时仍走既有 note.search 工具
  assert.match(evidence, /EVIDENCE_TOOL_NAME/);
});


test('note generation injects related existing_note fragments (R4)', () => {
  const draft = read('entry/src/main/ets/services/ai/DraftPipeline.ets');
  assert.match(draft, /private async relatedNoteFragments\(query: string, cancellationToken\?: CancellationToken\)/);
  assert.match(draft, /RagRetrievalService\.search\(store, trimmed, 2\)/);
  assert.match(draft, /buildSourceId\('existing_note', hit\.unitId, i\)/);
  assert.match(draft, /const related: SourceFragment\[\] = await this\.relatedNoteFragments\(/);
  assert.match(draft, /body\.length > 400 \? body\.substring\(0, 400\) : body/);
});


test('rag_chunk runtime sync: deterministic chunks written on note upsert (037)', () => {
  const index = read('entry/src/main/ets/database/NoteFtsIndex.ets');
  assert.match(index, /private static async syncChunks\(/);
  assert.match(index, /private static splitChunks\(unitId: string, content: string\): ChunkRow\[\]/);
  assert.match(index, /INSERT INTO rag_chunk \(id, unit_id, chunk_index, title, content, content_hash, token_count, created_at, updated_at\)/);
  assert.match(index, /DELETE FROM rag_embedding WHERE chunk_id = \?/);
  assert.match(index, /const CHUNK_SIZE: number = 400/);
});
