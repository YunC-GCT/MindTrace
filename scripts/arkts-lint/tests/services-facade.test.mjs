import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const structure = readFileSync(resolve(root, 'agents/src/main/ets/agents/StructureService.ets'), 'utf8');
const truthCheck = readFileSync(resolve(root, 'agents/src/main/ets/agents/TruthCheckService.ets'), 'utf8');
const prompt = readFileSync(resolve(root, 'agents/src/main/ets/agents/PromptBuilder.ets'), 'utf8');

test('StructureService facade delegates to KnowledgeModel structure and structureWithClassification', () => {
  assert.match(structure, /class StructureService/);
  assert.match(structure, /this\.model\.structure\(/);
  assert.match(structure, /this\.model\.structureWithClassification\(/);
});

test('TruthCheckService facade exposes check(input)', () => {
  assert.match(truthCheck, /class TruthCheckService/);
  assert.match(truthCheck, /check\(input: string\): MvpTruthCheckResult/);
});

test('PromptBuilder facade exposes build(input)', () => {
  assert.match(prompt, /class PromptBuilder/);
  assert.match(prompt, /build\(input: string\): string/);
});

test('Façade contract per split stage (spec 015): shells forward once; TruthCheck/PromptBuilder are entities', () => {
  // PR3 待做: StructureService 仍是转发壳 (恰好一次 this.model.*)
  assert.equal((structure.match(/this\.model\.structure\(/g) || []).length, 1);
  assert.equal((structure.match(/this\.model\.structureWithClassification\(/g) || []).length, 1);
  // PR2 已实体化: PromptBuilder 持有 buildPrompt 实现, 不再依赖 KnowledgeModel
  assert.match(prompt, /buildPrompt\(ocrText: string\): string/);
  assert.match(prompt, /你是数学学习笔记结构化助手/);
  assert.doesNotMatch(prompt, /this\.model\./);
  assert.doesNotMatch(prompt, /from '\.\/KnowledgeModel'/);
  // PR1 已实体化: TruthCheckService 持有真实现, 不再依赖 KnowledgeModel
  assert.match(truthCheck, /return this\.truthCheck\(input\);/);
  assert.doesNotMatch(truthCheck, /legacy\.truthCheck\(/);
  assert.doesNotMatch(truthCheck, /from '\.\/KnowledgeModel'/);
});
