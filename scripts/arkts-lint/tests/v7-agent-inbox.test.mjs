// 路径: scripts/arkts-lint/tests/v7-agent-inbox.test.mjs
// 职责: 小艺「待整理队列」协议契约测试（装载真实 .ets，不复制实现）。
// Why: 入队判定放宽会把普通长问题关进队列；队列解析太脆会把整批整理想丢一条脏行一起拖垮。

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const mod = loadNoteReviewEtsModule('entry/src/main/ets/services/AgentInboxModels.ets');
const { shouldEnqueue, buildInboxItem, serializeInboxItem, parseInboxItems, MIN_INBOX_CHARS } = mod;

test('a plain long question is not queued (no explicit note intent)', () => {
  const text = '老师这道题为什么要先求导再讨论单调性，能不能直接从二阶导判断极值？';
  assert.equal(shouldEnqueue(text), false, '没有「存笔记」这类显式指令就不该入队');
});

test('explicit note intent with enough body is queued', () => {
  const text = '存笔记：求函数 f(x)=x^2 在 x=1 处的导数，并说明几何意义。';
  assert.equal(shouldEnqueue(text), true);
});

test('intent word alone (too short) is not queued', () => {
  assert.equal(shouldEnqueue('存笔记'), false, '正文不足下限时没有可整理的原文');
  assert.ok(MIN_INBOX_CHARS >= 8);
});

test('buildInboxItem trims body and keeps channel xiaoyi', () => {
  const item = buildInboxItem('  存笔记：矩阵的秩\n', 1730000000000);
  assert.equal(item.text, '存笔记：矩阵的秩');
  assert.equal(item.channel, 'xiaoyi');
  assert.equal(item.receivedAt, 1730000000000);
  assert.ok(item.id.startsWith('xiaoyi-1730000000000-'));
});

test('serialize then parse round-trips one item', () => {
  const item = buildInboxItem('存笔记：行列式按行展开', 1730000000001);
  const items = parseInboxItems(serializeInboxItem(item));
  assert.equal(items.length, 1);
  assert.equal(items[0].id, item.id);
  assert.equal(items[0].text, item.text);
  assert.equal(items[0].receivedAt, item.receivedAt);
});

test('parse skips broken lines and empty text instead of failing the batch', () => {
  const good = serializeInboxItem(buildInboxItem('存笔记：连续函数的介值定理', 1730000000002));
  const raw = '\n{"text":""}\nnot-json\n' + good + '{"id":"x"}\n';
  const items = parseInboxItems(raw);
  assert.equal(items.length, 1, '只有一条合法条目');
  assert.ok(items[0].text.includes('介值定理'));
});

test('parse tolerates a fully malformed payload', () => {
  assert.equal(parseInboxItems('').length, 0);
  assert.equal(parseInboxItems('{{{{').length, 0);
});
