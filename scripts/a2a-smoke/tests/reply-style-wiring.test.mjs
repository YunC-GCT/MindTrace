import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');

const ability = read('entry/src/main/ets/agentextability/AgentExtAbility.ets');
const replyService = read('entry/src/main/ets/services/ReplyService.ets');
const UI_CALLERS = [
  'entry/src/main/ets/services/ModelRouter.ets',
  'entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets',
  'entry/src/main/ets/workflows/conversation/ConversationWorkflowPorts.ets',
];

test('A2A passes plain_text_math explicitly to ReplyService.complete', () => {
  assert.match(ability, /const A2A_REPLY_STYLE: ReplyStyle = 'plain_text_math'/);
  assert.match(ability, /\.complete\(context, session\.token, policy, A2A_REPLY_STYLE\)/);
});

test('ReplyService keeps markdown as the default style for UI callers', () => {
  assert.match(
    replyService,
    /async complete\([\s\S]*?style: ReplyStyle = 'markdown',[\s\S]*?\): Promise<string>/,
  );
  assert.match(
    replyService,
    /private async guardedComplete\([\s\S]*?style: ReplyStyle = 'markdown',[\s\S]*?\): Promise<string>/,
  );
  assert.match(replyService, /buildReplyMessages\(context, style\)/);
});

test('UI call sites do not opt into plain_text_math', () => {
  for (const file of UI_CALLERS) {
    assert.doesNotMatch(read(file), /plain_text_math/, file + ' must keep the default markdown style');
  }
});
