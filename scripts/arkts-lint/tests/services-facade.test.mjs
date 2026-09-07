import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const km = readFileSync(resolve(root, 'agents/src/main/ets/agents/KnowledgeModel.ets'), 'utf8');
const truthCheck = readFileSync(resolve(root, 'agents/src/main/ets/agents/TruthCheckService.ets'), 'utf8');
const prompt = readFileSync(resolve(root, 'agents/src/main/ets/agents/PromptBuilder.ets'), 'utf8');

test('KnowledgeModel is the orchestrating agent: structure and structureWithClassification implemented', () => {
  assert.match(km, /export class KnowledgeModel {/);
  assert.match(km, /async structure\(\n?\s*ocrText: string,/);
  assert.match(km, /async structureWithClassification\(/);
});

test('TruthCheckService exposes check(input)', () => {
  assert.match(truthCheck, /class TruthCheckService/);
  assert.match(truthCheck, /check\(input: string\): MvpTruthCheckResult/);
});

test('PromptBuilder exposes build(input)', () => {
  assert.match(prompt, /class PromptBuilder/);
  assert.match(prompt, /build\(input: string\): string/);
});

test('Collaborator contract (spec 015): three services extracted, KnowledgeModel orchestrates', () => {
  // KnowledgeModel 保留为编排 agent, 不再内联提示词/真值检查实现
  assert.match(km, /async structure\(/);
  assert.match(km, /AI 结构化失败/);
  assert.match(km, /this\.truthCheckService\.check\(ocrText\)/, 'truth check delegated to TruthCheckService');
  assert.match(km, /this\.promptBuilder\.buildPrompt\(ocrText\)/, 'prompt delegated to PromptBuilder');
  assert.doesNotMatch(km, /你是数学学习笔记结构化助手/, 'prompt body must live in PromptBuilder');
  assert.doesNotMatch(km, /checkBracePairing\(/, 'truth checks must live in TruthCheckService');
  assert.doesNotMatch(km, /legacy\.truthCheck\(/);
  // PromptBuilder 实体
  assert.match(prompt, /buildPrompt\(ocrText: string\): string/);
  assert.match(prompt, /你是数学学习笔记结构化助手/);
  assert.doesNotMatch(prompt, /from '\.\/KnowledgeModel'/);
  // TruthCheckService 实体
  assert.match(truthCheck, /return this\.truthCheck\(input\);/);
  assert.doesNotMatch(truthCheck, /legacy\.truthCheck\(/);
  assert.doesNotMatch(truthCheck, /from '\.\/KnowledgeModel'/);
});
