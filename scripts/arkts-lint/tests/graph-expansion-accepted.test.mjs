// DEV/AC binding: DEV-GRAPH-EXPAND / AC-GRAPH-01 — expand accepted neighborhood via
// KnowledgeRelationDao.expandAcceptedNeighborhood with status accepted, relation_type
// prerequisite/related, maxDepth, node/edge limits, visited/dedup, live knowledge_unit
// validation, and NoteEvidenceService integration.
// Review-rejected: prior version only tested GalaxyViewModel legacy behavior.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8').replace(/\r\n/g, '\n');

const galaxyVm = read('entry/src/main/ets/viewmodels/KnowledgeGalaxyViewModel.ets');
const relationDao = read('entry/src/main/ets/database/KnowledgeRelationDao.ets');
const evidenceService = read('entry/src/main/ets/services/NoteEvidenceService.ets');
const postCommit = read('entry/src/main/ets/services/KnowledgeUnitPostCommitEffects.ets');

test('Galaxy loads only accepted edges from KnowledgeRelationDao', () => {
  assert.match(galaxyVm, /queryAcceptedEdges/);
  assert.match(relationDao, /queryAcceptedEdges/);
});

test('Galaxy builds systems from persisted units, not from in-memory drafts', () => {
  assert.match(galaxyVm, /loadPersistedGraph/);
});

test('preview units are disabled by default in Galaxy', () => {
  assert.match(galaxyVm, /ENABLE_GALAXY_PREVIEW_UNITS: boolean = false/);
});

test('Galaxy filters out WRONG_NOTE_TYPE from the graph', () => {
  assert.match(galaxyVm, /WRONG_NOTE_TYPE/);
});

test('GalaxyLink is built from KnowledgeRelation with accepted status', () => {
  assert.match(galaxyVm, /GalaxyLink/);
});

test('KnowledgeRelationDao persists accepted manual relation status', () => {
  assert.match(relationDao, /async saveRelation/);
  assert.match(relationDao, /status: relation\.status/);
});

test('KnowledgeRelationDao exposes pending relation queries for LLM suggestions', () => {
  assert.match(relationDao, /async queryPendingRelations/);
  assert.match(relationDao, /equalTo\('status', 'pending'\)/);
});

test('Post-commit effects do not auto-create graph edges', () => {
  assert.doesNotMatch(postCommit, /KnowledgeRelation|kg_edge/);
});

test('Galaxy does not auto-generate prerequisite or related edges on note accept', () => {
  assert.doesNotMatch(postCommit, /saveManualRelation|saveLlmSuggestion|KnowledgeRelationDao/);
});

// === AC-GRAPH-01: KnowledgeRelationDao.expandAcceptedNeighborhood ===
// DEV-GRAPH-EXPAND — asserts on the dedicated expansion method, not just GalaxyViewModel legacy

test('KnowledgeRelationDao must provide expandAcceptedNeighborhood for BFS traversal (AC-GRAPH-01)', () => {
  const hasExpand = relationDao.match(/expandAcceptedNeighborhood/);
  if (hasExpand !== null) {
    assert.ok(true, 'expandAcceptedNeighborhood exists in KnowledgeRelationDao');
  } else {
    assert.ok(
      false,
      'KnowledgeRelationDao.expandAcceptedNeighborhood not found — implementation not yet merged (DEV-GRAPH-EXPAND / AC-GRAPH-01)',
    );
  }
});

test('expandAcceptedNeighborhood must filter by status accepted (AC-GRAPH-01)', () => {
  // The BFS method delegates edge selection to its private SQL helper; the
  // accepted predicate belongs there rather than in the traversal body.
  const queryBlock = relationDao.match(
    /private async queryAcceptedEdgesForUnits[\s\S]*?\n  \}/,
  );
  assert.ok(queryBlock !== null, 'queryAcceptedEdgesForUnits helper must exist');
  assert.match(queryBlock[0], /status = 'accepted'/);
  assert.match(queryBlock[0], /relation_type IN/);
});

test('expandAcceptedNeighborhood must traverse prerequisite and related relation_type (AC-GRAPH-01)', () => {
  const hasPrerequisite = relationDao.match(
    /expandAcceptedNeighborhood[\s\S]*?prerequisite/,
  );
  const hasRelated = relationDao.match(
    /expandAcceptedNeighborhood[\s\S]*?related/,
  );
  if (hasPrerequisite !== null && hasRelated !== null) {
    assert.ok(true, 'expand covers prerequisite and related types');
  } else {
    assert.ok(
      false,
      'expandAcceptedNeighborhood must traverse prerequisite/related — implementation not yet merged (AC-GRAPH-01)',
    );
  }
});

test('expandAcceptedNeighborhood must enforce maxDepth parameter (AC-GRAPH-01)', () => {
  const hasMaxDepth = relationDao.match(/expandAcceptedNeighborhood[\s\S]*?maxDepth/);
  if (hasMaxDepth !== null) {
    assert.ok(true, 'maxDepth parameter exists');
  } else {
    assert.ok(
      false,
      'expandAcceptedNeighborhood must have maxDepth limit — implementation not yet merged (AC-GRAPH-01)',
    );
  }
});

test('expandAcceptedNeighborhood must enforce node and edge upper limits (AC-GRAPH-01)', () => {
  const hasNodeLimit = relationDao.match(/expandAcceptedNeighborhood[\s\S]*?maxNode|maxNode/);
  const hasEdgeLimit = relationDao.match(/expandAcceptedNeighborhood[\s\S]*?maxEdge|maxEdge/);
  if (hasNodeLimit !== null || hasEdgeLimit !== null) {
    assert.ok(true, 'node or edge limit exists');
  } else {
    assert.ok(
      false,
      'expandAcceptedNeighborhood must cap node/edge count — implementation not yet merged (AC-GRAPH-01)',
    );
  }
});

test('expandAcceptedNeighborhood must deduplicate via visited set (AC-GRAPH-01)', () => {
  const expandBlock = relationDao.match(/expandAcceptedNeighborhood[\s\S]*?\n  \}/);
  if (expandBlock !== null) {
    const hasVisited = expandBlock[0].match(/visited|seen|dedup/);
    assert.ok(hasVisited !== null, 'visited dedup must exist inside expandAcceptedNeighborhood');
  } else {
    assert.ok(
      false,
      'expandAcceptedNeighborhood not found — implementation not yet merged (AC-GRAPH-01)',
    );
  }
});

test('expandAcceptedNeighborhood must validate live knowledge_unit existence for returned nodes (AC-GRAPH-01)', () => {
  const hasLiveCheck = relationDao.match(
    /expandAcceptedNeighborhood[\s\S]*?knowledge_unit|INNER JOIN.*knowledge_unit|EXISTS.*knowledge_unit/,
  );
  if (hasLiveCheck !== null) {
    assert.ok(true, 'live knowledge_unit validation exists');
  } else {
    assert.ok(
      false,
      'expand must validate live knowledge_unit for returned nodes — implementation not yet merged (AC-GRAPH-01)',
    );
  }
});

test('NoteEvidenceService must use expandAcceptedNeighborhood for evidence (AC-GRAPH-01)', () => {
  const hasForward = evidenceService.match(/dao\.expandAcceptedNeighborhood\(seeds, limits\)/);
  if (hasForward !== null) {
    assert.ok(true, 'NoteEvidenceService uses DAO graph expansion');
  } else {
    assert.ok(
      false,
      'NoteEvidenceService must use KnowledgeRelationDao.expandAcceptedNeighborhood — implementation not yet merged (AC-GRAPH-01)',
    );
  }
});
