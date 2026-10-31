// 路径: scripts/arkts-lint/tests/v7-capture-set.test.mjs
// 职责: spec 036 阶段 1 的守卫 —— 「一个 set 一个 run」（A4 4c：改走 dispatchSetCommand/NoteBatchOutcome）。
//       1) N 项一次整理 → N 条逐项回执，顺序保持
//       2) 单项失败不打中断整批（失败隔离）
//       3) 取消后剩余项记 cancelled，不混进 failed
//       4) UI 入口不再自己 for 循环 capture
//       5) onOutcome 每完成一项回调一次，且在返回前触发
//       6) 入口守卫：批量胶囊删除，图片入口固定 1..20 张并写 origin=image 记录
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { createRuntime, memoryStorage } from './knowledge-dispatch-runtime.mjs';

const REPO_ROOT = new URL('../../../', import.meta.url);
const readRepoFile = (path) => readFileSync(new URL(path, REPO_ROOT), 'utf8');

const CLASSIFICATION = {
  category: '概念',
  subject: '数学分析',
  chapter: '连续性',
  confidence: 0.95,
  cleaned_text: '函数在一点连续。',
};

const NOTE_JSON = {
  category: '概念',
  subject: '数学分析',
  chapter: '连续性',
  title: '连续函数',
  tags: ['连续'],
  difficulty: 1,
  importance: 3,
  fields: [{ key: 'definition', label: '定义', value: '函数在一点连续。' }],
};

const alternating = () => (_request, index) => (index % 2 === 1 ? CLASSIFICATION : NOTE_JSON);

const TEXT_ITEMS = [
  { kind: 'text', text: '函数在一点连续。' },
  { kind: 'text', text: '数列收敛的定义。' },
];

let seq = 0;
const commandsOf = (items) => items.map((payload) => ({
  kind: 'capture',
  operationId: 'op-set-' + (++seq),
  source: 'app',
  payload,
}));

test('dispatchSetCommand: 两项一次整理，逐项回执且顺序不变', async () => {
  const runtime = createRuntime(alternating());
  const storage = memoryStorage();
  const batch = await runtime.dispatcher.dispatchSetCommand(commandsOf(TEXT_ITEMS), {
    persist: true,
    dao: storage.dao,
  });

  assert.equal(batch.total, 2);
  assert.equal(batch.committed, 2);
  assert.equal(batch.failed, 0);
  assert.equal(batch.cancelled, 0);
  assert.equal(batch.items.length, 2);
  assert.equal(batch.items[0].kind, 'committed');
  assert.equal(batch.items[1].kind, 'committed');
  assert.ok(batch.items[0].noteId, '第一项应带回 noteId');
  assert.ok(batch.items[1].noteId, '第二项应带回 noteId');
  assert.notEqual(batch.items[0].noteId, batch.items[1].noteId, '两项必须是两条独立笔记');
  assert.equal(storage.writes.length, 2, '两项各落一条');
});

test('dispatchSetCommand: 第二项模型失败，第一项照常落库', async () => {
  const flaky = (request) => {
    const prompt = request.messages.map((m) => m.content).join('\n');
    if (prompt.includes('数列收敛')) {
      throw new Error('model unavailable');
    }
    return prompt.includes('结构化助手') ? NOTE_JSON : CLASSIFICATION;
  };
  const runtime = createRuntime(flaky);
  const storage = memoryStorage();
  const batch = await runtime.dispatcher.dispatchSetCommand(commandsOf(TEXT_ITEMS), {
    persist: true,
    dao: storage.dao,
  });

  assert.equal(batch.total, 2);
  assert.equal(batch.committed, 1);
  assert.equal(batch.failed, 1);
  assert.equal(batch.items[0].kind, 'committed');
  assert.equal(batch.items[1].kind, 'failed');
  assert.equal(storage.writes.length, 1, '失败项不得落库，成功项不受影响');
});

test('dispatchSetCommand: 取消后剩余项记 cancelled，不混进 failed', async () => {
  const probe = createRuntime();
  const token = new probe.common.CancellationToken();
  const runtime = createRuntime((request) => {
    const prompt = request.messages.map((m) => m.content).join('\n');
    if (prompt.includes('数列收敛')) {
      token.cancel();
    }
    return prompt.includes('结构化助手') ? NOTE_JSON : CLASSIFICATION;
  });
  const storage = memoryStorage();
  const batch = await runtime.dispatcher.dispatchSetCommand(commandsOf(TEXT_ITEMS), {
    persist: true,
    dao: storage.dao,
    cancellationToken: token,
  });

  assert.equal(batch.total, 2);
  assert.equal(batch.committed, 1, '取消前完成的一项仍算完成');
  assert.equal(batch.failed, 0, '取消不算失败');
  assert.equal(batch.cancelled, 1);
  assert.equal(batch.items[1].kind, 'cancelled');
});

test('采集入口：UI 不再自己 for 循环 capture，统一走 captureSet', () => {
  const source = readRepoFile('entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets');
  assert.ok(source.includes('service.captureSet('), '整理入口必须调用 captureSet');
  assert.ok(!source.includes('service.capture('), '不得再逐张调用 capture（会退化成 N 个独立任务）');
});

test('dispatchSetCommand: onOutcome 每完成一项回调一次，且在返回前触发', async () => {
  const runtime = createRuntime(alternating());
  const storage = memoryStorage();
  const seen = [];
  let returned = false;
  const items = [
    TEXT_ITEMS[0],
    TEXT_ITEMS[1],
    { kind: 'text', text: '第三题：极限的定义。' },
  ];
  const batch = await runtime.dispatcher.dispatchSetCommand(commandsOf(items), {
    persist: true,
    dao: storage.dao,
  }, (index, outcome) => {
    assert.equal(returned, false, 'onOutcome 必须在 dispatchSetCommand 返回之前触发');
    seen.push({ index: index, kind: outcome.kind });
  });
  returned = true;

  assert.equal(batch.committed, 3);
  assert.equal(seen.length, 3, '3 项都必须各回调一次');
  assert.deepEqual(seen.map((item) => item.index), [0, 1, 2], 'index 必须依次为 0/1/2');
  assert.ok(seen.every((item) => item.kind === 'committed'), '3 项都应为 committed');
});

test('入口守卫：批量入口合并进图片图标（spec 036）', () => {
  const plus = readRepoFile('entry/src/main/ets/overlays/AgentFloatWindow/PlusActionSheet.ets');
  assert.equal(plus.includes('BatchAction'), false, '+ 弹窗不得再出现 BatchAction 胶囊');

  const floatWindow = readRepoFile('entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets');
  assert.equal(floatWindow.includes('onBatchAction'), false, '不得保留 onBatchAction');
  assert.equal(floatWindow.includes('onAlbumBatchAction'), false, '不得保留 onAlbumBatchAction');
  assert.ok(floatWindow.includes("origin: 'image'"), '整理记录必须写成 origin=image 的 ai 消息');
  assert.ok(
    /AlbumPickerLauncher\.pick\([\s\S]{0,160}?,\s*20\)/.test(floatWindow),
    '图片入口必须固定最多 20 张',
  );
});
