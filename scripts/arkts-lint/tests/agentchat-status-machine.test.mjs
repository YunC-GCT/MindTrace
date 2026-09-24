import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');

const machine = read('entry/src/main/ets/services/ChatStatusMachine.ets');
const chatService = read('entry/src/main/ets/services/AgentChatService.ets');
const workflow = read('entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets');
const chatModels = read('entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatModels.ets');
const conversationState = read('entry/src/main/ets/workflows/conversation/ConversationState.ets');

// spec 007 PR2: Chat 状态机从 AgentChatService.statusFromStep 抽取为 ChatStatusMachine。
// 4 个 structural guard (与 PR1 agentchat-intent-classifier.test.mjs 同节奏)。

const ALL_STEPS = [
  'intent_check',
  'reply_context_load',
  'reply_model_call',
  'image_message_save',
  'image_recognize',
  'image_material_save',
  'note_intent_check',
  'note_context_load',
  'note_source_prepare',
  'note_structure_save',
  'note_finalize',
  'completed',
];

test('ChatStatusMachine exposes a single public advance(step) entry that returns ChatStatusMeta', () => {
  assert.match(machine, /export class ChatStatusMachine/);
  assert.match(machine, /public advance\(step: ChatStatusStep\): ChatStatusMeta/);
});

test('ChatStatusMachine.META_TABLE maps all ChatStatusStep values', () => {
  for (const step of ALL_STEPS) {
    assert.match(
      machine,
      new RegExp(`'${step}',\\s*\\{`),
      `META_TABLE missing entry for step '${step}'`,
    );
  }
});

test('ChatStatusMachine.META_TABLE value type is a typed interface (no untyped object literal)', () => {
  assert.match(machine, /interface MetaEntry/);
  assert.match(machine, /Map<ChatStatusStep, MetaEntry>/);
});

test('AgentChatService adapter maps workflow progress through ChatStatusMachine', () => {
  assert.match(chatService, /private readonly statusMachine: ChatStatusMachine = new ChatStatusMachine\(\);/);
  assert.match(chatService, /this\.statusMachine\.advance\(step\)/);
  assert.match(workflow, /this\.cbs\.onProgress\(ref, step\)/);
  assert.doesNotMatch(workflow, /ChatStatusMachine|setStatusMeta|setBusy/);
});

test('busy lifecycle remains in AgentChatService adapter; workflow emits lifecycle events', () => {
  assert.match(chatService, /onStart\(ref: ConversationRunRef\): void/);
  assert.match(chatService, /onFinish\(ref: ConversationRunRef\): void/);
  assert.match(chatService, /this\.callbacks\.setStatusMeta\(ref, null\)/);
  assert.match(workflow, /this\.cbs\.onStart\(runRef\)/);
  assert.match(workflow, /this\.cbs\.onFinish\(runRef\)/);
  assert.doesNotMatch(machine, /setBusy|cbs\.setStatusMeta/);
  assert.match(machine, /advance\(step: ChatStatusStep\): ChatStatusMeta \{[^}]*return \{ step/m);
});

test('ChatStatusStep preserves the workflow progress contract', () => {
  assert.match(chatModels, /export type ChatStatusStep = ConversationProgressStep/);
  for (const step of ALL_STEPS) {
    assert.match(
      conversationState,
      new RegExp(`'${step}'`),
      `ConversationProgressStep missing value '${step}'`,
    );
  }
});
