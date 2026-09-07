import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');

const read = (p) => readFileSync(resolve(root, p), 'utf8');

const llmClient = read('common/src/main/ets/llm/LlmClient.ets');
const llmTypes = read('common/src/main/ets/llm/LlmTypes.ets');
const llmGuard = read('common/src/main/ets/llm/LlmGuard.ets');
const commonIndex = read('common/src/main/ets/Index.ets');
const chatService = read('entry/src/main/ets/services/AgentChatService.ets');
const memoryService = read('entry/src/main/ets/services/AgentMemoryService.ets');
const studyPlanVm = read('entry/src/main/ets/viewmodels/StudyPlanViewModel.ets');
const aiSettingsVm = read('entry/src/main/ets/viewmodels/AiSettingsViewModel.ets');

// spec 005 / ADR-0004: LlmClient 只暴露一个公共入口 call(request)。
test('LlmClient exposes exactly one public entry call(request)', () => {
  const callDefs = llmClient.match(/public async call\(/g) ?? [];
  assert.equal(callDefs.length, 1, 'LlmClient must have exactly one public async call(');
  assert.doesNotMatch(llmClient, /public async callStream\(/, 'callStream must be removed');
  assert.doesNotMatch(llmClient, /public async callSseTokens\(/, 'callSseTokens must be removed');
});

test('LlmTypes declares LlmCallRequest and LlmCallResult', () => {
  assert.match(llmTypes, /export interface LlmCallRequest/);
  assert.match(llmTypes, /messages: ChatMessage\[\];/);
  assert.match(llmTypes, /stream\?: boolean;/);
  assert.match(llmTypes, /onDelta\?: LlmStreamCallback;/);
  assert.match(llmTypes, /export interface LlmCallResult/);
  assert.match(llmTypes, /text\?: string;/);
  assert.match(llmTypes, /streamed: boolean;/);
});

test('LlmGuard LlmCaller migrated to call(request) shape', () => {
  assert.match(llmGuard, /call\(request: LlmCallRequest\): Promise<LlmCallResult>/);
  assert.doesNotMatch(llmGuard, /call\(messages: ChatMessage\[\], opts/);
});

test('all call sites migrated off the 3-way split', () => {
  for (const [name, text] of [
    ['AgentChatService', chatService],
    ['AgentMemoryService', memoryService],
    ['StudyPlanViewModel', studyPlanVm],
    ['AiSettingsViewModel', aiSettingsVm],
  ]) {
    assert.doesNotMatch(text, /callSseTokens\(/, `${name} must not use callSseTokens`);
    assert.doesNotMatch(text, /callStream\(/, `${name} must not use callStream`);
  }
  assert.match(chatService, /stream: true/, 'AgentChatService real reply must use real SSE streaming');
});

test('common Index exports the new call types', () => {
  assert.match(commonIndex, /LlmCallRequest/);
  assert.match(commonIndex, /LlmCallResult/);
});
