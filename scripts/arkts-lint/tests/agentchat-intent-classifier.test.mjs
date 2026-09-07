import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');

const classifier = read('entry/src/main/ets/services/IntentClassifier.ets');
const chatService = read('entry/src/main/ets/services/AgentChatService.ets');

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

test('AgentChatService delegates: intent methods removed, intentClassifier field + call sites', () => {
  assert.doesNotMatch(chatService, /classifyTextIntent|buildIntentMessages|parseTextIntent|validateTextIntentJson|shouldUseRemoteIntentClassifier|hasNoteGenerationDenyIntent|hasExplicitNoteGenerationIntent|hasActionNearTarget/);
  assert.doesNotMatch(chatService, /private extractJsonObject/);
  assert.match(chatService, /private intentClassifier: IntentClassifier = new IntentClassifier\(\);/);
  assert.match(chatService, /this\.intentClassifier\.classify\(/);
  assert.match(chatService, /this\.intentClassifier\.inlineNoteMaterial\(/);
  assert.match(chatService, /this\.intentClassifier\.buildReplyMessages\(/);
  assert.match(chatService, /import \{ IntentClassifier \} from '\.\/IntentClassifier';/);
});

test('AgentChatService keeps orchestration-only concerns (clip, formatAnalyzeReply, status machine)', () => {
  assert.match(chatService, /private clip\(text: string, limit: number\): string/);
  assert.match(chatService, /private formatAnalyzeReply\(/);
  assert.match(chatService, /private setStep\(step: ChatStatusStep\): void/);
  assert.match(chatService, /private async callChatAnswerWithRetry\(/);
});
