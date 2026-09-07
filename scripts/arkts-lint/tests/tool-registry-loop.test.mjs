import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');

const llmTypes = read('common/src/main/ets/llm/LlmTypes.ets');
const commonIndex = read('common/src/main/ets/Index.ets');
const registry = read('common/src/main/ets/tools/ToolRegistry.ets');
const toolLoop = read('common/src/main/ets/tools/ToolLoop.ets');

// spec 014 §2: ToolRegistry — AgentTool/ToolResult/注册校验/容错执行。
test('ToolRegistry declares AgentTool + ToolResult + registry API', () => {
  assert.match(registry, /export interface ToolResult/);
  assert.match(registry, /ok: boolean;/);
  assert.match(registry, /content: string;/);
  assert.match(registry, /export interface AgentTool/);
  assert.match(registry, /execute\(args: Record<string, Object>\): Promise<ToolResult>;/);
  assert.match(registry, /export class ToolRegistry/);
  assert.match(registry, /register\(tool: AgentTool\): void/);
  assert.match(registry, /has\(name: string\): boolean/);
  assert.match(registry, /listDefinitions\(\): LlmToolDefinition\[\]/);
  assert.match(registry, /async execute\(name: string, argsJson: string\): Promise<ToolResult>/);
});

test('ToolRegistry: duplicate/invalid name rejected via TOOL_REGISTRY_ERROR; unknown tool + bad JSON -> ok:false (no throw)', () => {
  assert.match(llmTypes, /'TOOL_REGISTRY_ERROR'/);
  assert.match(registry, /'TOOL_REGISTRY_ERROR'/);
  assert.match(registry, /unknown tool: /);
  assert.match(registry, /invalid tool arguments/);
  assert.match(registry, /\^\[a-z\]\[a-z0-9_\]\{0,63\}\$/, 'naming rule ^[a-z][a-z0-9_]{0,63}$ enforced at registration');
});

test('no entry imports in common/src/main/ets/tools/ (topology red line, ADR-0012)', () => {
  assert.doesNotMatch(registry, /from ['"].*entry/);
  assert.doesNotMatch(toolLoop, /from ['"].*entry/);
});

// spec 014 §3: ToolLoop — LlmCaller seam 注入 / toolCalls 循环 / maxSteps 触顶。
test('ToolLoop injects LlmCaller and declares ToolLoopOptions', () => {
  assert.match(toolLoop, /constructor\(llm: LlmCaller\)/);
  assert.match(toolLoop, /run\(messages: ChatMessage\[\], registry: ToolRegistry, options\?: ToolLoopOptions\)/);
  assert.match(toolLoop, /export interface ToolLoopOptions/);
  assert.match(toolLoop, /maxSteps\?: number;/);
  assert.match(toolLoop, /callOptions\?: LlmCallOptions;/);
  assert.match(toolLoop, /listDefinitions\(\)/);
});

test('ToolLoop appends assistant(tool_calls) + role=tool messages; throws TOOL_LOOP_MAX_STEPS', () => {
  assert.match(toolLoop, /tool_calls: result\.toolCalls/);
  assert.match(toolLoop, /role: 'tool'/);
  assert.match(toolLoop, /tool_call_id: /);
  assert.match(toolLoop, /'TOOL_LOOP_MAX_STEPS'/);
});

test('common Index exports the tool surface and wire types', () => {
  assert.match(commonIndex, /export \{ ToolRegistry \} from '\.\/tools\/ToolRegistry'/);
  assert.match(commonIndex, /export \{ ToolLoop \} from '\.\/tools\/ToolLoop'/);
  assert.match(commonIndex, /AgentTool/);
  assert.match(commonIndex, /ToolResult/);
  assert.match(commonIndex, /LlmToolDefinition/);
  assert.match(commonIndex, /LlmToolCall/);
});
