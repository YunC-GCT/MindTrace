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

test('standard schema describes nested outline, evidence, and draft fields', () => {
  assert.match(models, /requiredKeys: string\[\]/);
  assert.match(models, /buildJsonSchema\(/);
  assert.match(models, /NOTE_STANDARD_JSON_SCHEMA: string = buildJsonSchema/);
  assert.match(models, /\['outline', 'draft'\]/);
  assert.doesNotMatch(models, /\['outline', 'evidence', 'draft'\]/);
});
