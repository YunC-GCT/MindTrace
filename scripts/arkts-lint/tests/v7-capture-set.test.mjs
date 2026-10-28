// 路径: scripts/arkts-lint/tests/v7-capture-set.test.mjs
// 职责: spec 036 阶段 1 的守卫——「一个 set 一个 run」。
//       1) N 项一次整理 → N 条逐项回执，下标与顺序保持
//       2) 单项失败不打断整批（失败隔离）
//       3) 取消后剩余项记 cancelled，不混进 failed，也不抛给调用方
//       4) UI 入口不再自己 for 循环 capture（那正是要修掉的形态）
//       5) onItem 每完成一项回调一次，且在 dispatchSet 返回前触发
//       6) 入口守卫：批量胶囊删除，图片入口固定 1..20 张并写 origin=image 记录
// Why: 采集入口原来在 AgentFloatWindow 里逐张调用 AiService.capture，
//      同一批图被当成 N 个互不相干的任务：没有共享预算、没有统一取消、
//      失败只留一个计数。dispatchSet 把「多张图 = 一次整理」立住，
//      切题与跨图合并（spec 036 阶段 2/3）才有挂点。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { createRuntime, memoryStorage } from './knowledge-dispatch-runtime.mjs';

// 测试文件在 scripts/arkts-lint/tests/：3 个 .. 到仓库根（文件段会先被 URL 解析掉）。
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

// 每项恰好两次调用：分类 → 结构化。奇数位分类、偶数位结构化。
const alternating = () => (_request, index) => (index % 2 === 1 ? CLASSIFICATION : NOTE_JSON);

const TEXT_ITEMS = [
  { kind: 'text', text: '函数在一点连续。' },
  { kind: 'text', text: '数列收敛的定义。' },
];

test('dispatchSet: 两张图一次整理，逐项回执且顺序不变', async () => {
  const runtime = createRuntime(alternating());
  const storage = memoryStorage();
  const result = await runtime.dispatcher.dispatchSet(
    { source: 'app', items: TEXT_ITEMS },
    { persist: true, dao: storage.dao },
  );

  assert.equal(result.total, 2);
  assert.equal(result.done, 2);
  assert.equal(result.failed, 0);
  assert.equal(result.cancelled, 0);
  assert.equal(result.items.length, 2);
  assert.equal(result.items[0].index, 0);
  assert.equal(result.items[1].index, 1);
  assert.ok(result.items[0].noteId, '第一项应带回 noteId');
  assert.ok(result.items[1].noteId, '第二项应带回 noteId');
  assert.notEqual(result.items[0].noteId, result.items[1].noteId, '两项必须是两条独立笔记');
  assert.equal(storage.writes.length, 2, '两项各落一条');
});

test('dispatchSet: 第二项模型失败，第一项照常落库', async () => {
  // 用第二项独有的题干文本触发失败，避免依赖第几次调用（LLM 层可能有重试）
  const flaky = (request) => {
    const prompt = request.messages.map((m) => m.content).join('\n');
    if (prompt.includes('数列收敛')) {
      throw new Error('model unavailable');
    }
    // 结构化调用的 system 提示词固定以「数学学习笔记结构化助手」开头；重试不会打乱这个判定
    return prompt.includes('结构化助手') ? NOTE_JSON : CLASSIFICATION;
  };
  const runtime = createRuntime(flaky);
  const storage = memoryStorage();
  const result = await runtime.dispatcher.dispatchSet(
    { source: 'app', items: TEXT_ITEMS },
    { persist: true, dao: storage.dao },
  );

  assert.equal(result.total, 2);
  assert.equal(result.done, 1);
  assert.equal(result.failed, 1);
  assert.equal(result.items[0].success, true);
  assert.equal(result.items[1].success, false);
  assert.equal(storage.writes.length, 1, '失败项不得落库，成功项不受影响');
});

test('dispatchSet: 取消后剩余项记 cancelled，不混进 failed', async () => {
  const probe = createRuntime();
  const token = new probe.common.CancellationToken();
  const runtime = createRuntime((request) => {
    const prompt = request.messages.map((m) => m.content).join('\n');
    if (prompt.includes('数列收敛')) {
      token.cancel();
    }
    // 结构化调用的 system 提示词固定以「数学学习笔记结构化助手」开头；重试不会打乱这个判定
    return prompt.includes('结构化助手') ? NOTE_JSON : CLASSIFICATION;
  });
  const storage = memoryStorage();
  const result = await runtime.dispatcher.dispatchSet(
    { source: 'app', items: TEXT_ITEMS },
    { persist: true, dao: storage.dao, cancellationToken: token },
  );

  assert.equal(result.total, 2);
  assert.equal(result.done, 1, '取消前完成的一项仍然算完成');
  assert.equal(result.failed, 0, '取消不算失败');
  assert.equal(result.cancelled, 1);
  assert.equal(result.items[1].cancelled, true);
});

test('采集入口：UI 不再自己 for 循环 capture，统一走 captureSet', () => {
  const source = readRepoFile('entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets');
  assert.ok(source.includes('service.captureSet('), '整理入口必须调用 captureSet');
  assert.ok(!source.includes('service.capture('), '不得再逐张调用 capture（会退化成 N 个独立任务）');
});

test('dispatchSet: onItem 每完成一项回调一次，且在返回前触发', async () => {
  const runtime = createRuntime(alternating());
  const storage = memoryStorage();
  const seen = [];
  let returned = false;
  const items = [
    TEXT_ITEMS[0],
    TEXT_ITEMS[1],
    { kind: 'text', text: '第三题：极限的定义。' },
  ];
  const result = await runtime.dispatcher.dispatchSet(
    { source: 'app', items },
    {
      persist: true,
      dao: storage.dao,
      onItem: (item) => {
        assert.equal(returned, false, 'onItem 必须在 dispatchSet 返回之前触发');
        seen.push({ index: item.index, success: item.success });
      },
    },
  );
  returned = true;

  assert.equal(result.done, 3);
  assert.equal(seen.length, 3, '3 项都必须各回调一次');
  assert.deepEqual(seen.map((item) => item.index), [0, 1, 2], 'index 必须依次为 0/1/2');
  assert.ok(seen.every((item) => item.success === true), '3 项都应成功');
});

test('入口守卫：批量入口合并进图片图标（spec 036）', () => {
  const plus = readRepoFile('entry/src/main/ets/overlays/AgentFloatWindow/PlusActionSheet.ets');
  assert.equal(plus.includes('BatchAction'), false, '+ 弹窗不得再出现 BatchAction 胶囊');

  const floatWindow = readRepoFile('entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets');
  assert.equal(floatWindow.includes('onBatchAction'), false, '不得保留 onBatchAction');
  assert.equal(floatWindow.includes('onAlbumBatchAction'), false, '不得保留 onAlbumBatchAction');
  assert.ok(floatWindow.includes("origin: 'image'"), '整理记录必须写成 origin=image 的 ai 消息');
  assert.ok(
    // getContext(this) 自带括号，不能用 [^)]* 这种「不含右括号」的朴素匹配
    /AlbumPickerLauncher\.pick\([\s\S]{0,160}?,\s*20\)/.test(floatWindow),
    '图片入口必须固定最多 20 张',
  );
});
