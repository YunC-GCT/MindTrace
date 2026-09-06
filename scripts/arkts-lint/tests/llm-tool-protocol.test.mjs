import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');

const llmTypes = read('common/src/main/ets/llm/LlmTypes.ets');
const llmClient = read('common/src/main/ets/llm/LlmClient.ets');

// spec 014 / ADR-0012: OpenAI 兼容 tool-calling 协议字段(全部可选, wire 兼容)。

test('ChatMessage widened: tool role + tool_call_id + tool_calls (additive)', () => {
  assert.match(llmTypes, /'system' \| 'user' \| 'assistant' \| 'tool'/);
  assert.match(llmTypes, /tool_call_id\?: string;/);
  assert.match(llmTypes, /tool_calls\?: LlmToolCall\[\];/);
});

test('wire definitions: LlmFunctionDefinition / LlmToolDefinition / LlmToolCall', () => {
  assert.match(llmTypes, /export interface LlmFunctionDefinition/);
  assert.match(llmTypes, /name: string;/);
  assert.match(llmTypes, /description: string;/);
  assert.match(llmTypes, /parameters: Record<string, Object>;/);
  assert.match(llmTypes, /export interface LlmToolDefinition/);
  assert.match(llmTypes, /export interface LlmToolCall/);
  assert.match(llmTypes, /export interface LlmFunctionCallNameArgs/);
  assert.match(llmTypes, /arguments: string;/);
  const fnTypeHits = llmTypes.match(/type: 'function';/g) ?? [];
  assert.ok(fnTypeHits.length >= 2, 'both LlmToolDefinition and LlmToolCall carry type=function');
});

test('request-side optional fields on both LlmRequestBody and LlmCallRequest', () => {
  const toolsHits = llmTypes.match(/tools\?: LlmToolDefinition\[\];/g) ?? [];
  assert.ok(toolsHits.length >= 2, 'tools? must appear on LlmRequestBody AND LlmCallRequest');
  const choiceHits = llmTypes.match(/tool_choice\?: string;/g) ?? [];
  assert.ok(choiceHits.length >= 2, 'tool_choice? must appear on both request types');
});

test('LlmCallResult carries toolCalls; LlmErrorKind has TOOL_LOOP_MAX_STEPS', () => {
  assert.match(llmTypes, /toolCalls\?: LlmToolCall\[\];/);
  assert.match(llmTypes, /'TOOL_LOOP_MAX_STEPS'/);
});

test('LlmClient passes tools through and extracts tool_calls provider-tolerantly', () => {
  assert.match(llmClient, /private extractToolCalls\(parsed: LlmResponse\)/);
  assert.match(llmClient, /request\.tools !== undefined/);
  assert.match(llmClient, /request\.tool_choice !== undefined/);
  assert.match(llmClient, /result\.toolCalls = toolCalls/, 'LlmCallResult.toolCalls must be populated');
  assert.doesNotMatch(
    llmClient,
    /finish_reason === 'tool_calls'/,
    'gate must NOT depend on finish_reason (OpenAI-compatible endpoint variance)',
  );
});
