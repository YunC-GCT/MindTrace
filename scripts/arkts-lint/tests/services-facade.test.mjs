import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const structure = readFileSync(resolve(root, 'agents/src/main/ets/agents/StructureService.ets'), 'utf8');
const truthCheck = readFileSync(resolve(root, 'agents/src/main/ets/agents/TruthCheckService.ets'), 'utf8');
const prompt = readFileSync(resolve(root, 'agents/src/main/ets/agents/PromptBuilder.ets'), 'utf8');

test('StructureService is the entity: structure and structureWithClassification implemented', () => {
  assert.match(structure, /class StructureService/);
  assert.match(structure, /async structure\(\n?\s*ocrText: string,/);
  assert.match(structure, /async structureWithClassification\(/);
});

test('TruthCheckService facade exposes check(input)', () => {
  assert.match(truthCheck, /class TruthCheckService/);
  assert.match(truthCheck, /check\(input: string\): MvpTruthCheckResult/);
});

test('PromptBuilder facade exposes build(input)', () => {
  assert.match(prompt, /class PromptBuilder/);
  assert.match(prompt, /build\(input: string\): string/);
});

test('Façade contract per split stage (spec 015): all three are entities, KM deleted', () => {
  // PR3 已实体化: StructureService 持有编排/调用/校验实现, 不再依赖 KnowledgeModel
  assert.match(structure, /async structure\(/);
  assert.match(structure, /AI 结构化失败/);
  assert.doesNotMatch(structure, /this\.model\./);
  assert.doesNotMatch(structure, /from '\.\/KnowledgeModel'/);
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
