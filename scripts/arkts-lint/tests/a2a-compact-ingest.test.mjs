// 路径: scripts/arkts-lint/tests/a2a-compact-ingest.test.mjs
// 职责: A2A 快速整理契约——短 prompt、小输出上限、30s deadline 的接线不被改回。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

test('A2A 文本整理走快速模式：短 prompt + 小输出上限 + 30s deadline', () => {
  const pipeline = read('entry/src/main/ets/services/ai/CapturePipeline.ets');
  assert.match(pipeline, /ingestTextOutcome\(text: string\): Promise<NoteOutcome>/);
  assert.match(pipeline, /processAndPersistOutcome\(payload, undefined, true, true\)/);
  assert.match(pipeline, /compactStructure: compactStructure/);
  const options = read('agents/src/main/ets/core/dispatch/DispatchOptions.ets');
  assert.match(options, /compactStructure\?: boolean/);
  const workflow = read('agents/src/main/ets/workflows/NoteCaptureWorkflow.ets');
  assert.match(workflow, /compactStructure: mode\.compactStructure === true/);
  const state = read('agents/src/main/ets/graph/AgentState.ets');
  assert.match(state, /compactStructure\?: boolean/);
  const node = read('agents/src/main/ets/graph/nodes/StructureNode.ets');
  assert.match(node, /input\.compactStructure === true/);
  const constants = read('entry/src/main/ets/services/A2AConstants.ets');
  assert.match(constants, /INGEST_DEADLINE_MS: number = 30000/);
});

test('快速整理 prompt 有独立长度约束，默认模式仍要求完整信息', () => {
  const prompt = read('agents/src/main/ets/subagents/PromptBuilder.ets');
  assert.match(prompt, /KNOWLEDGE_COMPACT_MAX_TOKENS: number = 2048/);
  assert.match(prompt, /KNOWLEDGE_COMPACT_TIMEOUT_MS: number = 25000/);
  assert.match(prompt, /buildPrompt\(ocrText: string, knownSubjects: string\[\] = \[\], compact: boolean = false\)/);
  assert.match(prompt, /快速整理模式（小艺）/);
  assert.match(prompt, /每个字段最多 30 字/);
  assert.match(prompt, /整个 JSON 正文不超过 220 字/);
  assert.match(prompt, /保留完整信息，不要把原题和关键步骤摘要丢失/);
  const structurer = read('agents/src/main/ets/subagents/CaptureStructurer.ets');
  assert.match(structurer, /buildPrompt\(ocrText, knownSubjects, compact\)/);
  assert.match(structurer, /maxTokens: compact \? KNOWLEDGE_COMPACT_MAX_TOKENS : KNOWLEDGE_MAX_TOKENS/);
  assert.match(structurer, /timeoutMs: compact \? KNOWLEDGE_COMPACT_TIMEOUT_MS : KNOWLEDGE_TIMEOUT_MS/);
  assert.match(structurer, /callOptions\.enableThinking = false/);
});
