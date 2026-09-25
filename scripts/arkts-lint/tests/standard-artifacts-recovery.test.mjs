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
  assert.match(knowledgeModel, /parseStandardResultAtDepth\(nested, sources, depth \+ 1\)/);
  assert.match(knowledgeModel, /require draft; keys=' \+ Object\.keys\(parsed\)\.join\(','\)/);
});

test('standard generation degrades missing outline and evidence when draft is present', () => {
  assert.match(knowledgeModel, /parseOptionalOutline\(outlineValue, draft\)/);
  assert.match(knowledgeModel, /evidence:\s*evidenceValue === undefined \? \[\] : this\.parseEvidence\(evidenceValue\)/);
  assert.match(knowledgeModel, /outlineFromDraft\(draft\)/);
  assert.match(models, /EVIDENCE_OPTIONAL/);
  assert.match(models, /FORMULA_EVIDENCE_OPTIONAL/);
});

test('standard generation keeps draft previewable when optional evidence or sourceIds are absent', () => {
  assert.match(knowledgeModel, /if \(result\.evidence\.length === 0\) \{\s*modelVerification = this\.relaxEmptyEvidenceVerification\(modelVerification\);\s*\}/);
  assert.match(knowledgeModel, /private relaxEmptyEvidenceVerification/);
  assert.match(knowledgeModel, /ensureOutlineSourceMapping\(normalizeOutline\(result\.outline, sourceIds\), sourceIds\)/);
  assert.match(knowledgeModel, /section\.sourceIds\.length > 0[\s\S]*?outlineSection === undefined \? sourceIds\.slice\(0\) : outlineSection\.sourceIds\.slice\(0\)/);
  assert.match(models, /MUST_INCLUDE_UNMAPPED_OPTIONAL/);
});

test('standard schema describes nested outline, evidence, and draft fields', () => {
  assert.match(models, /requiredKeys: string\[\]/);
  assert.match(models, /buildJsonSchema\(/);
  assert.match(models, /NOTE_STANDARD_JSON_SCHEMA: string = buildJsonSchema/);
});
