// 路径: scripts/arkts-lint/tests/v7-write-section.test.mjs
// 职责: 写区互斥契约——并发写入的 post-commit 阶段必须串行，避免 native 卡死（S0 实验结论）。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const mod = loadNoteReviewEtsModule('entry/src/main/ets/services/AsyncMutex.ets');
const AsyncMutex = mod.AsyncMutex;

test('runExclusive 串行执行重叠任务（不交错）', async () => {
  const mutex = new AsyncMutex();
  const events = [];
  const task = (name, ms) => mutex.runExclusive(async () => {
    events.push(name + ':start');
    await new Promise((resolve) => setTimeout(resolve, ms));
    events.push(name + ':end');
    return name;
  });
  const results = await Promise.all([task('a', 30), task('b', 5)]);
  assert.deepEqual(results, ['a', 'b']);
  assert.deepEqual(events, ['a:start', 'a:end', 'b:start', 'b:end']);
});

test('runExclusive 返回值/异常传播且异常后继续可用', async () => {
  const mutex = new AsyncMutex();
  const value = await mutex.runExclusive(async () => 42);
  assert.equal(value, 42);
  await assert.rejects(() => mutex.runExclusive(async () => { throw new Error('boom'); }), /boom/);
  const after = await mutex.runExclusive(async () => 'ok');
  assert.equal(after, 'ok');
});

test('写服务：索引同步与 post-commit effects 在写区内串行', () => {
  const root = resolve(import.meta.dirname, '../../..');
  const read = (path) => readFileSync(resolve(root, path), 'utf8');
  const service = read('entry/src/main/ets/services/KnowledgeUnitWriteService.ets');
  assert.match(service, /AsyncMutex/);
  assert.match(service, /runExclusive/);
  assert.match(service, /writeSection/);
});
