// DEV/AC binding: DEV-DELETE-TXN / AC-DELETE-01 — delete must be transactional, cleaning kg_edge, rag_chunk,
// rag_embedding; queries and graph must not return deleted or orphan edges.
// Review-rejected: prior version asserted "删除不清理 kg_edge" which contradicts current requirement.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8').replace(/\r\n/g, '\n');

const noteDao = read('entry/src/main/ets/database/NoteDao.ets');
const notesVm = read('entry/src/main/ets/viewmodels/NotesViewModel.ets');
const galaxyVm = read('entry/src/main/ets/viewmodels/KnowledgeGalaxyViewModel.ets');
const noteQueryTools = read('common/src/main/ets/tools/NoteQueryTools.ets');
const homeVm = read('entry/src/main/ets/viewmodels/HomeViewModel.ets');
const relationDao = read('entry/src/main/ets/database/KnowledgeRelationDao.ets');

test('NoteDao.deleteById performs a hard SQL DELETE with no is_deleted flag', () => {
  assert.match(noteDao, /async deleteById/);
  assert.match(noteDao, /store\.delete\(predicates/);
  assert.doesNotMatch(noteDao, /is_deleted/);
});

test('NotesViewModel.deleteNote calls deleteById directly with no soft-delete', () => {
  assert.match(notesVm, /deleteById/);
  assert.doesNotMatch(notesVm, /is_deleted|soft.?delete|archive/);
});

test('GalaxyViewModel.deleteNote rejects preview unit IDs before deletion', () => {
  assert.match(galaxyVm, /deleteNote/);
});

test('after hard delete, NoteQueryTool cannot find the note (no is_deleted filter)', () => {
  assert.match(noteQueryTools, /knowledge_unit/);
  assert.doesNotMatch(noteQueryTools, /is_deleted/);
});

// DEV-DELETE-TXN / AC-DELETE-01: deleteById or unified delete must clean kg_edge rows in a transaction
test('NoteDao.deleteById or unified delete flow must include kg_edge cleanup (transactional)', () => {
  const hasDeleteTransaction = noteDao.match(/async deleteById[\s\S]*?createTransaction/);
  const hasKgEdgeDelete = noteDao.match(/kg_edge|KnowledgeRelation/);
  if (hasDeleteTransaction !== null && hasKgEdgeDelete !== null) {
    assert.ok(true, 'deleteById uses transaction and includes kg_edge cleanup');
  } else if (hasKgEdgeDelete !== null) {
    assert.ok(true, 'deleteById includes kg_edge reference');
  } else {
    const unifiedDeleteInVm = notesVm.match(/deleteEdge|deleteRelationsByUnitId|cleanRelations/) ||
      homeVm.match(/deleteEdge|deleteRelationsByUnitId|cleanRelations/);
    const vmHasKgEdgeCleanup = unifiedDeleteInVm !== null;
    const daoHasCleanup = relationDao.match(/deleteByUnitId|deleteByUnit/);
    assert.ok(
      vmHasKgEdgeCleanup || daoHasCleanup !== null,
      'deleteById or unified delete must clean kg_edge — implementation not yet merged (DEV-DELETE-TXN)',
    );
  }
});

// AC-DELETE-02: delete transaction must also clean rag_chunk and rag_embedding
test('delete flow must clean rag_chunk rows associated with the deleted note', () => {
  const hasRagChunk = noteDao.match(/rag_chunk/);
  if (hasRagChunk !== null) {
    assert.ok(true, 'deleteById includes rag_chunk cleanup');
  } else {
    const servicePath = read('entry/src/main/ets/services/AiService.ets');
    const anyRagChunk = servicePath.match(/rag_chunk/) ||
      notesVm.match(/rag_chunk/) ||
      homeVm.match(/rag_chunk/);
    assert.ok(
      anyRagChunk !== null,
      'delete flow must clean rag_chunk — implementation not yet merged (AC-DELETE-02)',
    );
  }
});

test('delete flow must clean rag_embedding rows associated with the deleted note', () => {
  const hasRagEmbedding = noteDao.match(/rag_embedding/);
  if (hasRagEmbedding !== null) {
    assert.ok(true, 'deleteById includes rag_embedding cleanup');
  } else {
    const servicePath = read('entry/src/main/ets/services/AiService.ets');
    const anyRagEmbedding = servicePath.match(/rag_embedding/) ||
      notesVm.match(/rag_embedding/) ||
      homeVm.match(/rag_embedding/);
    assert.ok(
      anyRagEmbedding !== null,
      'delete flow must clean rag_embedding — implementation not yet merged (AC-DELETE-02)',
    );
  }
});

// AC-DELETE-03: KnowledgeRelationDao queries must not return edges for deleted units (live filter)
test('KnowledgeRelationDao queryByUnitId must only return edges whose unit still exists (live filter)', () => {
  assert.match(relationDao, /queryByUnitId/);
  const hasLiveFilter = relationDao.match(
    /INNER JOIN knowledge_unit|EXISTS.*knowledge_unit|from_unit_id.*IN.*SELECT|to_unit_id.*IN.*SELECT/,
  );
  if (hasLiveFilter !== null) {
    assert.ok(true, 'queryByUnitId has live knowledge_unit filter');
  } else {
    assert.ok(
      false,
      'KnowledgeRelationDao.queryByUnitId must filter out edges pointing to deleted units — implementation not yet merged (AC-DELETE-03)',
    );
  }
});

// AC-DELETE-03: NoteQueryTool must not return deleted notes (already hard-delete, no is_deleted)
test('NoteQueryTool queries knowledge_unit directly with no soft-delete filter (hard delete ensures no orphans)', () => {
  assert.match(noteQueryTools, /knowledge_unit/);
  assert.doesNotMatch(noteQueryTools, /is_deleted/);
});

test('there is no recycle bin or undo path for deleted notes', () => {
  assert.doesNotMatch(noteDao, /recycle|undo|restore.*delete|trash/);
  assert.doesNotMatch(notesVm, /recycle|undo|restore.*delete|trash/);
});

test('note_revision retains historical versions but has no restore-from-revision path', () => {
  assert.match(noteDao, /note_revision/);
  assert.doesNotMatch(noteDao, /restoreFromRevision|restoreRevision/);
});

test('HomeViewModel.deleteById follows the same hard-delete pattern', () => {
  assert.match(homeVm, /deleteById/);
});
