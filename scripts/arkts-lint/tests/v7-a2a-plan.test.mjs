// 路径: scripts/arkts-lint/tests/v7-a2a-plan.test.mjs
// 职责: A2A 多题「识别规划 + 一题一题来」契约——切题摘要（题数/质量/目录）、指令解析、
//       进度推进（继续/第N题/全部/取消）。复用 036 planner，纯函数可测。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

const plannerModule = loadNoteReviewEtsModule('agents/src/main/ets/graph/captureSetPlanner.ets');
const planModule = loadNoteReviewEtsModule('entry/src/main/ets/services/A2APlanModels.ets', {
  mocks: { agents: plannerModule },
});
const {
  buildA2APlanItems,
  parseA2APlanCommand,
  formatA2APlanSummary,
  formatA2APlanProgress,
  nextPlanItem,
  remainingPlanCount,
  reviewCountOf,
} = planModule;

const TWO_PROBLEMS = '1. 求方程 x^2-5x+6=0 的解。\n2. 求函数 f(x)=x^2+2x+1 的最小值。';

test('一段 OCR 文本切出多题，并给出题数/字数/质量目录', () => {
  const items = Array.from(buildA2APlanItems(TWO_PROBLEMS));
  assert.equal(items.length, 2);
  const plan = { taskId: 't', createdAt: 1, items, done: [] };
  const summary = formatA2APlanSummary(plan);
  assert.ok(summary.includes('识别到 2 道题'));
  assert.ok(summary.includes('[1.]'));
  assert.ok(summary.includes('[2.]'));
  assert.ok(summary.includes('正常'));
  assert.ok(summary.includes('回复「继续」'));
});

test('指令解析：继续/开始/第N题/全部/取消/普通文本', () => {
  const kinds = (q) => parseA2APlanCommand(q).kind;
  assert.equal(kinds('继续'), 'start');
  assert.equal(kinds('开始整理'), 'start');
  assert.equal(kinds('第 2 题'), 'index');
  assert.equal(parseA2APlanCommand('第 2 题').index, 2);
  assert.equal(kinds('全部'), 'all');
  assert.equal(kinds('取消'), 'cancel');
  assert.equal(kinds('你好'), 'none');
});

test('计划推进：下一题、剩余数、完成回执', () => {
  const items = Array.from(buildA2APlanItems(TWO_PROBLEMS));
  const plan = { taskId: 't', createdAt: 1, items, done: [] };
  const first = nextPlanItem(plan);
  assert.equal(first.index, 0);
  plan.done.push(first.index);
  assert.equal(remainingPlanCount(plan), 1);
  const progress = formatA2APlanProgress(plan, first, '解一元二次方程', '代数');
  assert.ok(progress.includes('第 1 题已整理入库：解一元二次方程'));
  assert.ok(progress.includes('还剩 1 题'));
  const second = nextPlanItem(plan);
  plan.done.push(second.index);
  assert.equal(remainingPlanCount(plan), 0);
  assert.equal(nextPlanItem(plan), undefined);
});

test('质量统计：待复核题数与摘要标注', () => {
  const items = Array.from(buildA2APlanItems(TWO_PROBLEMS));
  assert.equal(reviewCountOf(items), 0);
  const dirty = [{ index: 0, anchor: '1.', text: '短文本', needsReview: true, sourceImages: [] }];
  const plan = { taskId: 't', createdAt: 1, items: dirty, done: [] };
  assert.equal(reviewCountOf(dirty), 1);
  assert.ok(formatA2APlanSummary(plan).includes('待复核 1 道'));
});

test('扩展入口接线：多题先回规划，再按指令逐题整理；计划可落盘/清除', () => {
  const controller = [
    read('entry/src/main/ets/services/A2AController.ets'),
    read('entry/src/main/ets/services/A2AIngestHandler.ets'),
    read('entry/src/main/ets/services/A2AConstants.ets'),
    read('entry/src/main/ets/services/A2AAnswerHandler.ets'),
    read('entry/src/main/ets/services/A2ASession.ets'),
  ].join('\n');
  assert.match(controller, /handleTextPlanMessage\(/);
  assert.match(controller, /formatA2APlanSummary\(plan\)/);
  assert.match(controller, /handlePlanTurn\(/);
  assert.match(controller, /ingestPlanItem\(/);
  assert.match(controller, /A2APlanStore\.save\(this\.context, plan\.taskId, plan\)/);
  const store = read('entry/src/main/ets/services/A2APlanStore.ets');
  assert.match(store, /static async load\(context: common\.Context, taskId: string\)/);
  assert.match(store, /static async save\(context: common\.Context, taskId: string, plan: A2APlan\)/);
  assert.match(store, /filePath\(context, taskId\)/);
  const entry = read('entry/src/main/ets/entryability/EntryAbility.ets');
  assert.match(entry, /mode === 'agentTextPlan'/);
});


test('A2A 入库 deadline：超时转待整理队列（P0-2 第一片）', () => {
  const controller = [
    read('entry/src/main/ets/services/A2AController.ets'),
    read('entry/src/main/ets/services/A2AIngestHandler.ets'),
    read('entry/src/main/ets/services/A2AConstants.ets'),
    read('entry/src/main/ets/services/A2AAnswerHandler.ets'),
    read('entry/src/main/ets/services/A2ASession.ets'),
  ].join('\n');
  assert.match(controller, /INGEST_DEADLINE_MS: number = 90000/);
  assert.match(controller, /ingestWithDeadline\(text: string\): Promise<NoteOutcome>/);
  assert.match(controller, /INGEST_DEADLINE: ' \+ INGEST_DEADLINE_MS/);
  assert.match(controller, /a2aErrorText\('A2A_INGEST_TIMEOUT'\)/);
  assert.match(controller, /this\.enqueueTexts\(\[item\.text\]\)/);
});


test('A2APlan 多会话：计划 key 按 taskId 隔离且文件名安全', () => {
  const models = loadNoteReviewEtsModule('entry/src/main/ets/services/A2APlanModels.ets', {
    mocks: { agents: loadNoteReviewEtsModule('agents/src/main/ets/graph/captureSetPlanner.ets') },
  });
  const key = models.sanitizePlanKey;
  assert.equal(key('task-1'), 'task-1');
  assert.equal(key(''), 'default');
  assert.equal(key('a/b:c d'), 'a-b-c-d');
  assert.equal(key('x'.repeat(200)).length <= 64, true);
  assert.notEqual(key('task-1'), key('task-2'));
});
