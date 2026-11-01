// 路径: scripts/arkts-lint/tests/v7-a2a-intent.test.mjs
// 职责: A2A 意图路由 + OCR checkpoint 契约——聊天/OCR/存笔记/拍题卡片/计划推进显式分流；
//       OCR 后先出「识别摘要 + 规划」，用户「继续」才逐题入库。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

const plannerModule = loadNoteReviewEtsModule('agents/src/main/ets/graph/captureSetPlanner.ets');
const mocks = { agents: plannerModule };
const planModule = loadNoteReviewEtsModule('entry/src/main/ets/services/A2APlanModels.ets', { mocks });
const routerModule = loadNoteReviewEtsModule('entry/src/main/ets/services/A2AIntentRouter.ets', { mocks });
const { routeA2AIntent } = routerModule;
const { buildA2APlanItemsFromPages, formatA2APlanSummary } = planModule;

test('聊天默认走 chat，不被误判为整理', () => {
  assert.equal(routeA2AIntent('什么是洛必达法则？', false, false).kind, 'chat');
  assert.equal(routeA2AIntent('你好', false, false).kind, 'chat');
});

test('带图 → OCR；明确拍题但无图 → 卡片', () => {
  // 2.0：带图无整理意图 → 图片问答；明确整理意图 → OCR 整理
  assert.equal(routeA2AIntent('', true, false).kind, 'image_qa');
  assert.equal(routeA2AIntent('这题怎么做', true, false).kind, 'image_qa');
  assert.equal(routeA2AIntent('整理成笔记', true, false).kind, 'ocr');
  assert.equal(routeA2AIntent('帮我把这道题存到笔记', true, false).kind, 'ocr');
  assert.equal(routeA2AIntent('帮我拍题', false, false).kind, 'pick_card');
  assert.equal(routeA2AIntent('选图整理', false, false).kind, 'pick_card');
});

test('显式存笔记意图 → text_ingest', () => {
  assert.equal(routeA2AIntent('帮我整理这道题：求 f(2)', false, false).kind, 'text_ingest');
  assert.equal(routeA2AIntent('存笔记：矩阵的秩等于行秩', false, false).kind, 'text_ingest');
});

test('存在 checkpoint 计划时，继续/第N题/全部/取消 优先推进', () => {
  assert.equal(routeA2AIntent('继续', false, true).kind, 'plan_continue');
  assert.equal(routeA2AIntent('第 2 题', false, true).kind, 'plan_continue');
  assert.equal(routeA2AIntent('全部', false, true).kind, 'plan_continue');
  assert.equal(routeA2AIntent('取消', false, true).kind, 'plan_continue');
  assert.equal(routeA2AIntent('随便聊聊', false, true).kind, 'plan_waiting');
});

test('OCR 多页规划：保留来源图并写进摘要', () => {
  const pages = [
    { imageIndex: 0, text: '1. 求 f(1)\n' },
    { imageIndex: 1, text: '2. 求 f(2)\n' },
  ];
  const items = Array.from(buildA2APlanItemsFromPages(pages));
  assert.equal(items.length, 2);
  assert.deepEqual(Array.from(items[0].sourceImages), [0]);
  assert.deepEqual(Array.from(items[1].sourceImages), [1]);
  const summary = formatA2APlanSummary({ taskId: 't', createdAt: 1, items, done: [] });
  assert.ok(summary.includes('第 1 张图'));
  assert.ok(summary.includes('第 2 张图'));
});

test('扩展接线：意图路由 + OCR checkpoint（回复继续前不写库）', () => {
  const ability = read('entry/src/main/ets/agentextability/AgentExtAbility.ets');
  assert.match(ability, /routeA2AIntent\(text, images\.length > 0, plan !== null\)/);
  assert.match(ability, /INTENT_OCR/);
  assert.match(ability, /private handleOcrCheckpoint\(/);
  assert.match(ability, /planItemsFromRequest\(request\)/);
  const service = read('entry/src/main/ets/services/AgentIngestService.ets');
  assert.match(service, /static async planItemsFromRequest\(request: AgentIngestRequest\)/);
});


test('A2A 聊天接入 RAG：证据上下文注入 + 引用校验（P0-1）', () => {
  const ability = read('entry/src/main/ets/agentextability/AgentExtAbility.ets');
  assert.match(ability, /A2AChatContext\.build\(query\)/);
  assert.match(ability, /A2AChatContextResult/);
  assert.match(ability, /A2AChatContext\.sanitize\(session\.evidence, answer\)/);
  assert.match(ability, /A2A_EVIDENCE citations=/);
  const ctx = read('entry/src/main/ets/services/A2AChatContext.ets');
  assert.match(ctx, /service\.build\(trimmed, \{ topK: EVIDENCE_TOP_K \}\)/);
  assert.match(ctx, /EVIDENCE_TIMEOUT_MS: number = 1200/);
  assert.match(ctx, /sanitizeAnswer\(evidence, answer\)/);
  const entry = read('entry/src/main/ets/entryability/EntryAbility.ets');
  assert.match(entry, /mode === 'agentChatContext'/);
});


test('A2A 图片意图：带图但无整理短语 → image_qa；带「整理」→ ocr', () => {
  assert.equal(routeA2AIntent('这题怎么做', true, false).kind, 'image_qa');
  assert.equal(routeA2AIntent('', true, false).kind, 'image_qa');
  assert.equal(routeA2AIntent('整理成笔记', true, false).kind, 'ocr');
  assert.equal(routeA2AIntent('帮我把这道题存到笔记', true, false).kind, 'ocr');
  // 计划等待优先于图片问答
  assert.equal(routeA2AIntent('继续', true, true).kind, 'plan_continue');
});
