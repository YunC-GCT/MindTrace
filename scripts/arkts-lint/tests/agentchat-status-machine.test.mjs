import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');

const machine = read('entry/src/main/ets/services/ChatStatusMachine.ets');
const chatService = read('entry/src/main/ets/services/AgentChatService.ets');
const chatModels = read('entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatModels.ets');

// spec 007 PR2: 13 步 Chat 状态机从 AgentChatService.statusFromStep 抽取为 ChatStatusMachine。
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
  'note_material_summary',
  'note_structure_save',
  'note_finalize',
  'completed',
];

test('ChatStatusMachine exposes a single public advance(step) entry that returns ChatStatusMeta', () => {
  assert.match(machine, /export class ChatStatusMachine/);
  assert.match(machine, /public advance\(step: ChatStatusStep\): ChatStatusMeta/);
});

test('ChatStatusMachine.META_TABLE maps all 13 ChatStatusStep values (intent_check ... completed)', () => {
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

test('AgentChatService delegates setStep via ChatStatusMachine; private statics removed', () => {
  assert.match(chatService, /private statusMachine: ChatStatusMachine = new ChatStatusMachine\(\);/);
  assert.match(chatService, /this\.statusMachine\.advance\(step\)/);
  assert.doesNotMatch(chatService, /private static statusFromStep/);
  assert.doesNotMatch(chatService, /private static status\(step: ChatStatusStep/);
});

test('finishBusy remains in AgentChatService; ChatStatusMachine does not own busy lifecycle', () => {
  assert.match(chatService, /private finishBusy\(\): void/);
  assert.match(chatService, /this\.cbs\.setStatusMeta\(null\)/);
  // ChatStatusMachine.advance must be a pure step→meta function; no callback wiring.
  assert.doesNotMatch(machine, /setBusy|cbs\.setStatusMeta/);
  assert.match(machine, /advance\(step: ChatStatusStep\): ChatStatusMeta \{[^}]*return \{ step/m);
});

test('ChatStatusStep union is still defined in overlays/.../ChatModels (overlay contract preserved)', () => {
  assert.match(chatModels, /export type ChatStatusStep/);
  for (const step of ALL_STEPS) {
    assert.match(
      chatModels,
      new RegExp(`'${step}'`),
      `ChatModels.ChatStatusStep missing value '${step}'`,
    );
  }
});
