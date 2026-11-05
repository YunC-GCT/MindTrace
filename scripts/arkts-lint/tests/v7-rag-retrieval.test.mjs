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
const planTermQuery = planModule.planTermQuery;
const planShortTermQuery = planModule.planShortTermQuery;

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

test('term fallback: long terms use FTS OR, short terms fall back to LIKE', () => {
  const fts = planTermQuery(['加法计算', '9+9'], 5);
  assert.equal(fts.mode, 'fts');
  assert.equal(fts.bindValues[0], '"加法计算" OR "9+9"');
  assert.equal(fts.bindValues[1], 5);
  const like = planTermQuery(['导数'], 5);
  assert.equal(like.mode, 'like');
  assert.ok(like.sql.includes('(content LIKE ? OR title LIKE ?)'));
  assert.deepEqual(Array.from(like.bindValues), ['%导数%', '%导数%', 5]);
  assert.equal(planTermQuery([], 5), null);
  const quoted = planTermQuery(['a"b'], 5);
  assert.equal(quoted.bindValues[0], '"a""b"');
});

test('short-term fallback: only sub-3-char terms use LIKE', () => {
  const plan = planShortTermQuery(['数列极限', '定义'], 5);
  assert.equal(plan.mode, 'like');
  assert.deepEqual(Array.from(plan.bindValues), ['%定义%', '%定义%', 5]);
  assert.equal(planShortTermQuery(['数列极限'], 5), null);
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

test('note_fts is written inside the note transaction on create/update/delete', () => {
  const index = read('entry/src/main/ets/database/NoteFtsIndex.ets');
  assert.match(index, /static async applyToTransaction\(transaction: relationalStore\.Transaction, unit: KnowledgeUnit\)/);
  assert.match(index, /static async removeFromTransaction\(transaction: relationalStore\.Transaction, unitId: string\)/);
  assert.match(index, /DELETE FROM note_fts WHERE unit_id = \?/);
  const dao = read('entry/src/main/ets/database/NoteDao.ets');
  assert.ok((dao.match(/await NoteFtsIndex\.applyToTransaction\(transaction, /g) ?? []).length >= 4,
    '四条写路径（create/update + commitKey 变体）都在事务内同步索引');
  assert.match(dao, /await NoteFtsIndex\.removeFromTransaction\(transaction, id\)/);
  const write = read('entry/src/main/ets/services/KnowledgeUnitWriteService.ets');
  assert.equal(/INDEX_SYNC_TIMEOUT_MS/.test(write), false, '索引不再走提交后异步同步 + 超时降级');
  assert.match(write, /writeSection\.runExclusive/);
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


test('rag_chunk runtime sync: deterministic chunks written in the note transaction (037)', () => {
  const index = read('entry/src/main/ets/database/NoteFtsIndex.ets');
  assert.match(index, /private static async syncChunksInTransaction\(transaction: relationalStore\.Transaction/);
  assert.match(index, /private static splitChunks\(unitId: string, content: string\): ChunkRow\[\]/);
  assert.match(index, /INSERT INTO rag_chunk \(id, unit_id, chunk_index, title, content, content_hash, token_count, created_at, updated_at\)/);
  assert.match(index, /DELETE FROM rag_embedding WHERE chunk_id IN/);
  assert.match(index, /const CHUNK_SIZE: number = 400/);
});
