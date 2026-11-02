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
  // 短指令「整理成笔记」但没内容：给选图/打字引导，不能静默走闲聊
  assert.equal(routeA2AIntent('整理成笔记', false, false).kind, 'pick_card');
  assert.equal(routeA2AIntent('存笔记', false, false).kind, 'pick_card');
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
  assert.match(ability, /A2AChatContext\.build\(query/);
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


test('A2A 多轮记忆：contextId 会话键 + memoryContext 注入 + 回答后落盘', () => {
  const ability = read('entry/src/main/ets/agentextability/AgentExtAbility.ets');
  assert.ok(ability.includes('readContextId'));
  assert.ok(ability.includes('conversationKey'));
  assert.ok(ability.includes('A2AConversationStore.loadWithFallback(this.context, conversationKey)'));
  assert.ok(ability.includes('A2AChatContext.build(query, memory)'));
  assert.ok(ability.includes('A2AConversationStore.append(this.context, session.conversationKey'));
  assert.ok(ability.includes("A2A_MEMORY key="));
  // 扩展进程补 DB 初始化：RAG 证据不再 store-not-ready
  assert.ok(ability.includes('DatabaseHelper.init(this.context)'));
  const chat = read('entry/src/main/ets/services/A2AChatContext.ets');
  assert.ok(chat.includes("static async build(query: string, memoryContext: string = '')"));
  assert.ok(chat.includes('memoryContext: memoryContext'));
  const store = read('entry/src/main/ets/services/A2AConversationStore.ets');
  assert.ok(store.includes('static keyOf(taskId: string, contextId: string)'));
  assert.ok(store.includes('static format(turns: A2AConversationTurn[])'));
  assert.ok(store.includes('MAX_TURNS: number = 6'));
});


test('「上一条」问题走确定性记忆回答（不依赖模型是否用 memoryContext）', () => {
  const ability = read('entry/src/main/ets/agentextability/AgentExtAbility.ets');
  assert.ok(ability.includes('matchesRememberIntent(query)'));
  assert.ok(ability.includes('answerFromConversationMemory'));
  assert.ok(ability.includes("你上一条消息是：「"));
  const store = read('entry/src/main/ets/services/A2AConversationStore.ets');
  assert.ok(store.includes('export function matchesRememberIntent'));
  for (const phrase of ['上一条', '上一句', '刚才', '之前聊']) {
    assert.ok(store.includes("'" + phrase + "'"));
  }
});


test('记忆键合并：contextId 与 default 按时间合并（跨请求无 contextId 兼容）', () => {
  const store = read('entry/src/main/ets/services/A2AConversationStore.ets');
  assert.ok(store.includes('static async loadWithFallback'));
  assert.ok(store.includes("A2AConversationStore.load(context, 'default')"));
  assert.ok(store.includes('merged.sort('));
  assert.ok(store.includes('MAX_TURNS'));
  const ability = read('entry/src/main/ets/agentextability/AgentExtAbility.ets');
  assert.ok(ability.includes('loadWithFallback(this.context, conversationKey)'));
  assert.ok(ability.includes("A2AConversationStore.append(this.context, 'default'"));
});


test('图片整理意图：带图 +「整理雅可比」→ OCR 整理；带图提问 → image_qa', () => {
  const mod = loadNoteReviewEtsModule('entry/src/main/ets/services/A2AIntentRouter.ets', { mocks });
  assert.equal(mod.routeA2AIntent('整理雅可比', true, false).kind, 'ocr');
  assert.equal(mod.routeA2AIntent('帮我把这张图存成笔记', true, false).kind, 'ocr');
  assert.equal(mod.routeA2AIntent('这题怎么做', true, false).kind, 'image_qa');
  assert.equal(mod.hasIngestIntent('整理雅可比'), true);
  assert.equal(mod.hasIngestIntent('这题怎么做'), false);
  // 无图且无内容：短整理指令给引导，不进闲聊
  assert.equal(routeA2AIntent('整理雅可比', false, false).kind, 'pick_card');
});

test('A2A 不再发「进入 App」卡片；无图整理用上一次图片 OCR 文本内联完成', () => {
  const ability = read('entry/src/main/ets/agentextability/AgentExtAbility.ets');
  assert.ok(ability.includes('answerWithLastImageMaterial'));
  assert.ok(ability.includes('A2AImageContextStore.save(this.context, conversationKey, text)'));
  assert.ok(ability.includes('A2AImageContextStore.load(this.context, conversationKey)'));
  assert.ok(ability.includes('IMAGE_RECALL ingest chars='));
  assert.ok(ability.includes('不需要打开 App'));
  assert.ok(ability.includes('小艺这边只把文字转给智能体'));
  assert.equal(ability.includes('sendAnswerWithPickCard'), false);
  assert.equal(ability.includes('buildPickCardPartJson'), false);
  assert.equal(ability.includes('A2A_UI_CARD'), false);
  const store = read('entry/src/main/ets/services/A2AImageContextStore.ets');
  assert.ok(store.includes('static async save'));
  assert.ok(store.includes('static async load'));
  assert.ok(store.includes("loadExact(context, 'default')"));
});


test('图片材料探针隔离：e2e-probe key 不镜像 default，并可清理', () => {
  const store = read('entry/src/main/ets/services/A2AImageContextStore.ets');
  assert.ok(store.includes('mirrorToDefault: boolean = true'));
  assert.ok(store.includes('mirrorToDefault && key !=='));
  assert.ok(store.includes('static async clear'));
  const runner = read('entry/src/main/ets/services/DebugCaptureRunner.ets');
  assert.ok(runner.includes("probeKey: string = 'e2e-probe'"));
  assert.ok(runner.includes('save(ctx, probeKey, ocrText, false)'));
  assert.ok(runner.includes('runA2AImageContextClear'));
  assert.ok(runner.includes("clear(ctx, 'default')"));
});
