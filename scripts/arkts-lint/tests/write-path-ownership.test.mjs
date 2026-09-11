import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

const validator = read('entry/src/main/ets/services/WritePathValidator.ets');
const noteAdapter = read('entry/src/main/ets/adapters/NoteDaoAdapter.ets');
const noteWriteService = read('entry/src/main/ets/services/KnowledgeUnitWriteService.ets');
const memoryService = read('entry/src/main/ets/services/AgentMemoryService.ets');
const planService = read('entry/src/main/ets/services/StudyPlanService.ets');
const planViewModel = read('entry/src/main/ets/viewmodels/StudyPlanViewModel.ets');

test('AI write domains share one explicit validation gate', () => {
  assert.match(validator, /export class WritePathValidator/);
  assert.match(validator, /validateKnowledgeUnit/);
  assert.match(validator, /validateStudyPlanItem/);
  assert.match(validator, /validateChatMessage/);
  assert.match(validator, /validateAgentMemory/);
});

test('Capture persistence delegates through the unified KnowledgeUnit write service', () => {
  assert.match(noteAdapter, /KnowledgeUnitWriteService/);
  assert.match(noteAdapter, /await this\.service\.create\(unit, 'capture_graph'\)/);
  assert.match(noteAdapter, /return result\.rowId/);
  assert.match(noteWriteService, /WritePathValidator\.validateKnowledgeUnit\(unit\)/);
  assert.doesNotMatch(noteAdapter, /KnowledgeUnitExt|category: ext\.type|difficulty: ext\.difficulty/);
});

test('AgentMemoryService owns validated chat and memory inserts', () => {
  assert.match(memoryService, /private async insertMessageRecord/);
  assert.match(memoryService, /private async insertMemoryRecord/);
  assert.match(memoryService, /WritePathValidator\.validateChatMessage\(record\)/);
  assert.match(memoryService, /WritePathValidator\.validateAgentMemory\(record\)/);
  assert.equal((memoryService.match(/ChatMessageDao\(store\)\.insert/g) || []).length, 1);
  assert.equal((memoryService.match(/AgentMemoryDao\(store\)\.insert/g) || []).length, 1);
});

test('StudyPlanService owns AI generation and persistence without ViewModel dual write', () => {
  assert.match(planService, /generateAndPersist/);
  assert.match(planService, /WritePathValidator\.validateStudyPlanItem\(item\)/);
  assert.match(planService, /dao\.insert\(item\)/);
  assert.match(planViewModel, /StudyPlanService\.generateAndPersist\(knownTitles, this\.dao\)/);
  const generatePlan = planViewModel.match(/async generatePlan[\s\S]*?\n  }/);
  assert.ok(generatePlan);
  assert.doesNotMatch(generatePlan[0], /this\.dao\.insert/);
});
