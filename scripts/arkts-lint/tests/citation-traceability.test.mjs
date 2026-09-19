// DEV/AC binding: DEV-CITATION / AC-CITE-01 — NoteEvidenceModels/Service must carry
// noteId/version/excerpt, accepted graph relation, no-hit/graph-failed degradation,
// fabricated citation washing. If files don't exist in baseline, tests will pass
// once implementation merges.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => {
  try {
    return readFileSync(resolve(root, p), 'utf8').replace(/\r\n/g, '\n');
  } catch (e) {
    return '';
  }
};

const models = read('common/src/main/ets/models/NoteGenerationModels.ets');
const dispatcher = read('agents/src/main/ets/core/Dispatcher.ets');
const aiService = read('entry/src/main/ets/services/AiService.ets');
const noteGenRepo = read('entry/src/main/ets/database/NoteGenerationRepository.ets');
const relationDao = read('entry/src/main/ets/database/KnowledgeRelationDao.ets');
const relationService = read('entry/src/main/ets/services/KnowledgeRelationService.ets');

const evidenceModels = read('common/src/main/ets/models/NoteEvidenceModels.ets');
const evidenceService = read('entry/src/main/ets/services/NoteEvidenceService.ets');

// === Legacy citation traceability tests (must still pass) ===

test('NoteDraftSection carries sourceIds array for citation tracking', () => {
  assert.match(models, /interface NoteDraftSection[\s\S]*?sourceIds: string\[\]/);
});

test('EvidenceSourceRef includes sourceId, excerpt, start, end for byte-level traceability', () => {
  assert.match(models, /interface EvidenceSourceRef[\s\S]*?sourceId: string/);
  assert.match(models, /excerpt: string/);
  assert.match(models, /start: number/);
  assert.match(models, /end: number/);
});

test('NoteGenerationEvidenceItem carries sourceRefs for each claim', () => {
  assert.match(models, /interface NoteGenerationEvidenceItem[\s\S]*?sourceRefs: EvidenceSourceRef\[\]/);
});

test('IncrementalManifest carries sourceIds as top-level provenance record', () => {
  assert.match(models, /interface IncrementalManifest[\s\S]*?sourceIds: string\[\]/);
});

test('IncrementalManifestSection preserves per-section sourceIds', () => {
  assert.match(models, /interface IncrementalManifestSection[\s\S]*?sourceIds: string\[\]/);
});

test('AiService copies draft section sourceIds into generated sections', () => {
  assert.match(aiService, /sourceIds/);
  assert.match(aiService, /draft\.sections/);
});

test('AiService builds IncrementalManifest with fragment IDs from the request', () => {
  assert.match(aiService, /request\.sources\.fragments\.map/);
  assert.match(aiService, /sourceIds:/);
});

test('NoteGenerationRepository getRegenerationBase reconstructs SourceFragments from manifest', () => {
  assert.match(noteGenRepo, /getRegenerationBase/);
  assert.match(noteGenRepo, /manifest\.sourceIds/);
  assert.match(noteGenRepo, /note_generation_source/);
});

test('checkpoint saves outline, evidence, and verification JSON for full artifact recovery', () => {
  assert.match(dispatcher, /outlineJson: JSON\.stringify\(.*outline\)/);
  assert.match(dispatcher, /evidenceJson: JSON\.stringify\(.*evidence\)/);
  assert.match(dispatcher, /verificationJson: JSON\.stringify\(.*verification\)/);
});

test('validateStandardArtifacts checks outline-evidence-draft source mapping consistency', () => {
  assert.match(models, /function validateStandardArtifacts/);
  assert.match(models, /sourceIds/);
});

// === AC-CITE-01: NoteEvidenceModels coverage ===

test('NoteEvidenceModels must define NoteEvidenceRef with noteId, version, excerpt (AC-CITE-01)', () => {
  if (evidenceModels.length === 0) {
    assert.ok(
      false,
      'NoteEvidenceModels.ets not found in baseline — implementation not yet merged (DEV-CITATION / AC-CITE-01)',
    );
    return;
  }
  const hasNoteId = evidenceModels.match(/noteId: string/);
  const hasVersion = evidenceModels.match(/version: number/);
  const hasExcerpt = evidenceModels.match(/excerpt: string/);
  assert.ok(hasNoteId !== null, 'NoteEvidenceRef must have noteId');
  assert.ok(hasVersion !== null, 'NoteEvidenceRef must have version');
  assert.ok(hasExcerpt !== null, 'NoteEvidenceRef must have excerpt');
});

test('NoteEvidenceModels must link to accepted graph relation (AC-CITE-01)', () => {
  if (evidenceModels.length === 0) {
    assert.ok(
      false,
      'NoteEvidenceModels.ets not found — implementation not yet merged (DEV-CITATION / AC-CITE-01)',
    );
    return;
  }
  const hasRelation = evidenceModels.match(/relationId|edgeId|kgEdge|graphRelation/);
  assert.ok(
    hasRelation !== null,
    'NoteEvidenceRef must reference an accepted graph relation — implementation not yet merged (AC-CITE-01)',
  );
});

// AC-CITE-02: no-hit / graph-failed degradation
test('NoteEvidenceService must degrade gracefully when no graph hit is found (AC-CITE-02)', () => {
  if (evidenceService.length === 0) {
    assert.ok(
      false,
      'NoteEvidenceService.ets not found — implementation not yet merged (DEV-CITATION / AC-CITE-02)',
    );
    return;
  }
  const hasDegradation = evidenceService.match(
    /no.?hit|graph.?failed|fallback|degrad|uncited|no.*evidence|empty.*result/,
  );
  assert.ok(
    hasDegradation !== null,
    'NoteEvidenceService must handle no-hit/graph-failed gracefully — implementation not yet merged (AC-CITE-02)',
  );
});

// AC-CITE-03: fabricated citation washing
test('NoteEvidenceService or NoteEvidenceModels must wash fabricated citations (AC-CITE-03)', () => {
  const source = evidenceService.length > 0 ? evidenceService : evidenceModels;
  if (source.length === 0) {
    assert.ok(
      false,
      'Neither NoteEvidenceService nor NoteEvidenceModels found — implementation not yet merged (DEV-CITATION / AC-CITE-03)',
    );
    return;
  }
  const hasWash = source.match(
    /fabricat|hallucin|sanitiz|clean|wash|filter.*citat|validate.*citat|verify.*source/,
  );
  assert.ok(
    hasWash !== null,
    'Must wash fabricated citations — implementation not yet merged (DEV-CITATION / AC-CITE-03)',
  );
});

// AC-CITE-04: KnowledgeRelationDao must support accepted-edge query for evidence validation
test('KnowledgeRelationDao queryAcceptedEdges provides accepted-edge data for citation validation (AC-CITE-04)', () => {
  assert.match(relationDao, /queryAcceptedEdges/);
  assert.match(relationDao, /equalTo\('status', 'accepted'\)/);
});

// AC-CITE-04: KnowledgeRelationService must provide accepted relation query for evidence
test('KnowledgeRelationService queryAcceptedRelations provides accepted edges for citation validation (AC-CITE-04)', () => {
  assert.match(relationService, /queryAcceptedRelations/);
  assert.match(relationService, /queryAcceptedEdges/);
});
