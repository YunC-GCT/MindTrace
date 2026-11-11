// 路径: scripts/arkts-lint/tests/a2a-usability.test.mjs
// 职责: A2A 可用性补口——回执意图优先级、App 内重复提示、inbox 补齐通知。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

test('回执意图在 pick_card / 草稿预览之前处理', () => {
  const controller = read('entry/src/main/ets/services/A2AController.ets');
  const start = controller.indexOf('private routeInput(');
  const end = controller.indexOf('private handleImageQuestion(', start);
  assert.notEqual(start, -1);
  assert.notEqual(end, -1);
  const route = controller.slice(start, end);
  const receipt = route.indexOf('matchesReceiptIntent(text)');
  const pending = route.indexOf('if (pendingDraft !== null)');
  assert.notEqual(receipt, -1);
  assert.notEqual(pending, -1);
  assert.ok(receipt < pending, '回执判断必须早于待确认草稿和 pick_card 分支');
  assert.match(route, /this\.answerFromReceipt\(input\.taskId\)/);
});

test('App 内确认重复草稿时明确提示已复用', () => {
  const draft = read('agents/src/main/ets/conversation/ConversationDraftWorkflow.ets');
  assert.match(draft, /const reused: boolean = committed\.id !== candidate\.id;/);
  assert.match(draft, /检测到相同笔记，已复用/);
  assert.match(draft, /\(reused \? '已保存笔记（检测到相同笔记，已复用）：' : '已保存笔记：'\)/);
});

test('inbox 前台补齐后通过 toast 告知用户，后台仍停止轮询', () => {
  const inbox = read('entry/src/main/ets/services/A2AInboxIngestService.ets');
  assert.match(inbox, /static startWatch\(context: common\.UIAbilityContext,/);
  assert.match(inbox, /onConsumed\?: \(summary: IngestSummary\) => void/);
  assert.match(inbox, /summary\.claimed > 0/);

  const ability = read('entry/src/main/ets/entryability/EntryAbility.ets');
  assert.match(ability, /private windowStage: window\.WindowStage \| null = null;/);
  assert.match(ability, /this\.windowStage = windowStage;/);
  assert.match(ability, /private notifyInboxConsumed\(summary: IngestSummary\): void/);
  assert.match(ability, /getPromptAction\(\)\.showToast\(/);
  assert.match(ability, /小艺待整理已补齐/);
  assert.match(ability, /A2AInboxIngestService\.startWatch\(this\.context, /);
  assert.match(ability, /A2AInboxIngestService\.stopWatch\(\);/);
});
