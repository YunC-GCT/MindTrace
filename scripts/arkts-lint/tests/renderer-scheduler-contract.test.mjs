import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import test from 'node:test';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');
const schedulerPath = 'entry/src/main/ets/services/RendererScheduler.ets';
const tickPath = 'entry/src/main/ets/services/RenderTick.ets';
const scheduler = read(schedulerPath);
const tick = read(tickPath);
const listTests = read('entry/src/test/List.test.ets');

test('RendererScheduler stays independent from chat and persistence models', () => {
  assert.doesNotMatch(scheduler, /ChatMsg|messages|OpenTail|StreamingReplyDocument|Preferences|ChatBubble/);
  assert.match(scheduler, /export interface RenderTask/);
  assert.match(scheduler, /export interface RenderTaskCompletion/);
  assert.match(scheduler, /distanceToViewportScreens/);
  assert.match(scheduler, /DEFAULT_MAX_WEB_CREATES_PER_FRAME: number = 1/);
  assert.match(scheduler, /DEFAULT_MAX_WEB_WORK_MS_PER_FRAME: number = 16/);
  assert.match(scheduler, /MAX_NEARBY_VIEWPORT_DISTANCE_SCREENS: number = 1/);
  assert.match(scheduler, /completion\.workDurationMs/);
  assert.match(scheduler, /onBlockHeightChanged\(completion\.blockId, completion\.height\)/);
});

test('RenderTick has one delayed 50ms timer and fixed event order', () => {
  assert.match(tick, /export const TICK_MS: number = 50/);
  assert.equal((tick.match(/setInterval\(/g) ?? []).length, 1);
  assert.equal((tick.match(/clearInterval\(/g) ?? []).length, 1);
  assert.match(tick, /this\.handlers\.notifyData\(\);[\s\S]*this\.handlers\.notifyGeometry\(\);[\s\S]*this\.handlers\.handleScroll\(\);/);
  assert.match(tick, /this\.handlers\.updatePendingState\(\);/);
  assert.match(tick, /this\.handlers\.disconnectSubscriber\(\);/);
  assert.match(tick, /private static activeInstanceCount: number = 0/);
  assert.match(tick, /this\.flushPendingForSubscriber\(\);/);
  assert.match(tick, /RenderTick\.activeInstanceCount -= 1/);
});

test('Hypium suite registers both issue 140 behavior tests', () => {
  assert.match(listTests, /import rendererSchedulerTest from '\.\/RendererScheduler\.test';/);
  assert.match(listTests, /import renderTickTest from '\.\/RenderTick\.test';/);
  assert.match(listTests, /rendererSchedulerTest\(\);/);
  assert.match(listTests, /renderTickTest\(\);/);
});
