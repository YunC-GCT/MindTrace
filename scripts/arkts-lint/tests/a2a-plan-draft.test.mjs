// 路径: scripts/arkts-lint/tests/a2a-plan-draft.test.mjs
// 职责: 多题计划/图片计划走草稿确认，以及「整理成笔记」复用上一轮回答。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

test('计划项先草稿后入库：确认回写 done，全部完成清计划', () => {
  const handler = read('entry/src/main/ets/services/A2AIngestHandler.ets');
  assert.match(handler, /beginPlanDraftCheckpoint\(/);
  assert.match(handler, /beginDraftCheckpoint\(taskId, conversationKey, request, plan\.taskId, item\.index\)/);
  assert.match(handler, /draft\.planTaskId = planTaskId === undefined \? '' : planTaskId/);
  assert.match(handler, /draft\.planItemIndex = planItemIndex/);
  assert.match(handler, /completePlanDraftItem\(/);
  assert.match(handler, /plan\.done\.push\(itemIndex\)/);
  assert.match(handler, /这次计划全部完成/);
  assert.match(handler, /回复「继续」整理下一题/);
  // 计划项是自包含文本，不混入对话历史
  assert.match(handler, /planItemIndex !== undefined\s*\?\s*\[\] : A2AIngestHandler\.historySources/);
  const plan = read('entry/src/main/ets/services/A2APlanModels.ets');
  assert.match(plan, /每题先出草稿，确认后保存/);
});

test('「整理成笔记」复用上一轮回答；图片计划单题直接出草稿', () => {
  const controller = read('entry/src/main/ets/services/A2AController.ets');
  assert.match(controller, /CHAT_RECALL ingest chars=/);
  assert.match(controller, /answerWithLastMaterial\(/);
  assert.match(controller, /用户问题：' \+ user \+ '\\n助手回答：' \+ assistant/);
  assert.match(controller, /this\.ingestHandler\.handleTextPlanMessage\(taskId, ingest, conversationKey\)/);
  assert.match(controller, /handlePlanTurn\(input\.taskId, text, plan, conversationKey\)/);
  assert.match(controller, /handleOcrCheckpoint\(input\.taskId, ingest, conversationKey\)/);
  assert.match(controller, /items\.length === 1[\s\S]*?beginPlanDraftCheckpoint/);
});
