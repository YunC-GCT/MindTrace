import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, '../../..');

function readRepoFile(path) {
  return readFileSync(join(REPO_ROOT, path), 'utf8');
}

test('database schema creates kg_edge as an empty relation table', () => {
  const source = readRepoFile('common/src/main/ets/DatabaseHelper.ets');
  assert.match(source, /const DB_SCHEMA_VERSION: number = 12;/);
  assert.match(source, /CREATE TABLE IF NOT EXISTS kg_edge/);
  assert.match(source, /from_unit_id TEXT NOT NULL/);
  assert.match(source, /to_unit_id TEXT NOT NULL/);
  assert.match(source, /relation_type TEXT NOT NULL/);
  assert.match(source, /source TEXT NOT NULL DEFAULT 'manual'/);
  assert.match(source, /status TEXT NOT NULL DEFAULT 'accepted'/);
  assert.match(source, /confidence REAL NOT NULL DEFAULT 1\.0/);
  assert.match(source, /CREATE UNIQUE INDEX IF NOT EXISTS uq_kg_edge_relation/);
  assert.doesNotMatch(source, /INSERT\s+(OR\s+IGNORE\s+)?INTO\s+kg_edge/i);
});

test('database schema reserves RAG chunk and embedding tables with JSON vector storage', () => {
  const source = readRepoFile('common/src/main/ets/DatabaseHelper.ets');
  assert.match(source, /CREATE TABLE IF NOT EXISTS rag_chunk/);
  assert.match(source, /CREATE TABLE IF NOT EXISTS rag_embedding/);
  assert.match(source, /vector_json TEXT NOT NULL DEFAULT '\[\]'/);
  assert.match(source, /CREATE INDEX IF NOT EXISTS idx_rag_chunk_unit/);
  assert.match(source, /CREATE INDEX IF NOT EXISTS idx_rag_embedding_chunk/);
});

test('knowledge relation model and DAO expose graph-specific relation queries', () => {
  const modelSource = readRepoFile('common/src/main/ets/models/KnowledgeGraphModels.ets');
  const daoSource = readRepoFile('entry/src/main/ets/database/KnowledgeRelationDao.ets');
  assert.match(modelSource, /export interface KnowledgeRelation/);
  assert.match(modelSource, /fromUnitId: string/);
  assert.match(modelSource, /toUnitId: string/);
  assert.match(modelSource, /source: KnowledgeRelationSource/);
  assert.match(modelSource, /status: KnowledgeRelationStatus/);
  assert.match(daoSource, /async queryAcceptedEdges\(\): Promise<KnowledgeRelation\[]>/);
  assert.match(daoSource, /async queryByUnitId\(unitId: string\): Promise<KnowledgeRelation\[]>/);
  assert.match(daoSource, /async queryPendingRelations\(\): Promise<KnowledgeRelation\[]>/);
});

test('relation persistence and evidence expansion share KnowledgeRelationDao', () => {
  const daoSource = readRepoFile('entry/src/main/ets/database/KnowledgeRelationDao.ets');
  const evidenceSource = readRepoFile('entry/src/main/ets/services/NoteEvidenceService.ets');
  assert.match(daoSource, /async saveRelation\(relation: KnowledgeRelation\): Promise<KnowledgeRelation>/);
  assert.match(daoSource, /async acceptRelation\(id: string\): Promise<boolean>/);
  assert.match(daoSource, /async rejectRelation\(id: string\): Promise<boolean>/);
  assert.match(daoSource, /status: relation\.status/);
  assert.match(daoSource, /async expandAcceptedNeighborhood\(/);
  assert.match(evidenceSource, /new KnowledgeRelationDao\(store\)/);
  assert.match(evidenceSource, /dao\.expandAcceptedNeighborhood\(seeds, limits\)/);
});

test('knowledge galaxy uses graph metadata and accepted kg_edge relations', () => {
  const noteDaoSource = readRepoFile('entry/src/main/ets/database/NoteDao.ets');
  const viewModelSource = readRepoFile('entry/src/main/ets/viewmodels/KnowledgeGalaxyViewModel.ets');
  assert.match(noteDaoSource, /async queryAllGraphMetadata\(\): Promise<KnowledgeUnit\[]>/);
  assert.match(viewModelSource, /queryAllGraphMetadata\(\)/);
  assert.match(viewModelSource, /new KnowledgeRelationDao\(store\)\.queryAcceptedEdges\(\)/);
  assert.match(viewModelSource, /private buildLinks\(bundles: UnitBundle\[], relations: KnowledgeRelation\[]\)/);
  assert.doesNotMatch(viewModelSource, /bundle\.unit\.prerequisites/);
  assert.doesNotMatch(viewModelSource, /bundle\.unit\.related/);
});

test('RAG demo DAO stores vectors as JSON text without lifecycle logic', () => {
  const source = readRepoFile('entry/src/main/ets/database/RagEmbeddingDao.ets');
  assert.match(source, /saveDemoEmbedding/);
  assert.match(source, /vectorJson: RagEmbeddingDao\.stringifyVector\(vector\)/);
  assert.match(source, /JSON\.stringify\(value\)/);
  assert.doesNotMatch(source, /stale/i);
  assert.doesNotMatch(source, /retry/i);
  assert.doesNotMatch(source, /cosineSimilarity/i);
});
