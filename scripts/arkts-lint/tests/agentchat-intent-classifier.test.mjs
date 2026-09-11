import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');

const classifier = read('entry/src/main/ets/services/IntentClassifier.ets');
const chatService = read('entry/src/main/ets/services/AgentChatService.ets');
const workflow = read('entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets');
const replyService = read('entry/src/main/ets/services/ReplyService.ets');

// spec 007 PR1: 意图分类 + 提示词构建从 AgentChatService 抽取为 IntentClassifier。

test('IntentClassifier exists with public classify / inlineNoteMaterial / buildReplyMessages', () => {
  assert.match(classifier, /export class IntentClassifier/);
  assert.match(classifier, /public async classify\(userText: string\): Promise<TextIntent>/);
  assert.match(classifier, /public inlineNoteMaterial\(userInstruction: string\): string/);
  assert.match(classifier, /public buildReplyMessages\(memoryContext: string, learnerProfileContext: string, userContent: string\): ChatMessage\[\]/);
  assert.match(classifier, /export type TextIntent = 'note_generation' \| 'chat';/);
});

test('IntentClassifier takes an injectable LlmGuard seam and reuses guard.extractJsonObject (no duplicate)', () => {
  assert.match(classifier, /constructor\(guard\?: LlmGuard\)/);
  assert.match(classifier, /this\.guard\.extractJsonObject\(raw\)/);
  assert.doesNotMatch(classifier, /private extractJsonObject/);
});

test('ConversationWorkflow owns intent orchestration and AgentChatService stays a facade', () => {
  assert.doesNotMatch(chatService, /IntentClassifier|classifyTextIntent|generateNoteFromConversation/);
  assert.match(chatService, /private readonly workflow: ConversationWorkflow/);
  assert.match(chatService, /await this\.workflow\.run\(request\)/);
  assert.match(workflow, /private intentClassifier: IntentClassifier = new IntentClassifier\(\);/);
  assert.match(workflow, /this\.intentClassifier\.classify\(/);
  assert.match(workflow, /this\.intentClassifier\.inlineNoteMaterial\(/);
  assert.match(replyService, /this\.intentClassifier\.buildReplyMessages\(/);
});

test('ConversationWorkflow owns reply implementation without duplicate facade logic', () => {
  assert.match(workflow, /private clip\(text: string, limit: number\): string/);
  assert.match(workflow, /private formatAnalyzeReply\(/);
  assert.match(workflow, /private replyService: ReplyService/);
  assert.match(replyService, /async complete\(/);
  assert.match(replyService, /async stream\(/);
  assert.doesNotMatch(replyService, /summarizeNoteMaterial/);
  assert.doesNotMatch(workflow, /LlmClient|LlmGuard|ContentProtocol/);
  assert.doesNotMatch(chatService, /LlmClient|AgentMemoryService|ContentProtocol|AiService/);
});
