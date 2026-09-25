import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');
const knowledgeModel = read('agents/src/main/ets/agents/KnowledgeModel.ets');
const models = read('common/src/main/ets/models/NoteGenerationModels.ets');

test('standard generation prompt includes the complete artifacts contract', () => {
  assert.match(knowledgeModel, /Output schema:/);
  assert.match(knowledgeModel, /outline.*evidence.*draft/);
  assert.match(knowledgeModel, /NOTE_STANDARD_JSON_SCHEMA/);
});

test('standard generation accepts a direct draft-shaped provider response', () => {
  assert.match(knowledgeModel, /parseDirectStandardArtifacts\(parsed, sources\)/);
  assert.match(models, /export function parseDirectStandardArtifacts/);
  assert.match(models, /findDirectDraftSource/);
  assert.match(models, /classifyEvidenceType/);
});

test('standard generation unwraps common provider envelope fields before failing', () => {
  assert.match(knowledgeModel, /findNestedStandardArtifacts/);
  assert.match(knowledgeModel, /preferredKeys: string\[\] = \['result', 'data', 'note', 'document', 'draftDocument', 'answer', 'content', 'output'\]/);
  assert.match(knowledgeModel, /return this\.parseStandardResult\(nested, sources\)/);
  assert.match(knowledgeModel, /require draft; keys=' \+ Object\.keys\(parsed\)\.join\(','\)/);
});

test('standard generation degrades missing outline and evidence when draft is present', () => {
  assert.match(knowledgeModel, /Evidence may be an empty array or be omitted on the first pass/);
  assert.match(knowledgeModel, /evidence = buildPipelineEvidence\(outline, bundle\)/);
  assert.match(knowledgeModel, /pipeline will fill missing mappings from the real source bundle/);
  assert.match(models, /EVIDENCE_OPTIONAL/);
  assert.match(models, /FORMULA_EVIDENCE_OPTIONAL/);
});

test('standard generation keeps draft previewable when optional evidence or sourceIds are absent', () => {
  assert.match(knowledgeModel, /if \(result\.evidence\.length === 0\) \{\s*modelVerification = this\.relaxEmptyEvidenceVerification\(modelVerification\);\s*\}/);
  assert.match(knowledgeModel, /private relaxEmptyEvidenceVerification/);
  assert.match(knowledgeModel, /const outline: NoteGenerationOutline = normalizeOutline\(result\.outline, sourceIds\)/);
  assert.match(knowledgeModel, /if \(mappedSourceIds\.length === 0\)/);
  assert.match(models, /MUST_INCLUDE_UNMAPPED_OPTIONAL/);
});

test('standard schema describes nested outline, evidence, and draft fields', () => {
  assert.match(models, /requiredKeys: string\[\]/);
  assert.match(models, /buildJsonSchema\(/);
  assert.match(models, /NOTE_STANDARD_JSON_SCHEMA: string = buildJsonSchema/);
  assert.match(models, /\['outline', 'draft'\]/);
  assert.doesNotMatch(models, /\['outline', 'evidence', 'draft'\]/);
});
