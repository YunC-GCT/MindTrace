import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');

const WORKER = 'entry/src/main/ets/workers/ImageSearchWorker.ets';
const ADAPTER = 'entry/src/main/ets/services/CoreVisionImageSearchIndex.ets';

test('Worker 侧的 textSearchImage 只在独立 Worker 文件里 import', () => {
  const worker = read(WORKER);
  assert.match(worker, /from '@hms\.ai\.vision\.textSearchImage'/,
    'SDK 只有 default export，Worker 必须直接 import textSearchImage');
  assert.match(worker, /postMessage/, 'Worker 要回包');
  assert.match(worker, /queue|pending|serial/i, 'Worker 内部必须串行处理：一次只跑一条 search');
});

test('适配器把 search 交给 Worker，超时降级而不是抛错', () => {
  const adapter = read(ADAPTER);
  assert.match(adapter, /const WORKER_SCRIPT: string = 'entry\/ets\/workers\/ImageSearchWorker\.ets';/,
    'Worker 脚本路径要写死常量');
  assert.match(adapter, /new worker\.ThreadWorker\(WORKER_SCRIPT\)/,
    'search 必须走常驻 Worker');
  assert.match(adapter, /5000/, '单次检索上限 5000ms');
  assert.match(adapter, /search degraded reason=/, '超时要打降级日志');
  assert.match(adapter, /degrade\('timeout'/, '超时走 degrade(timeout) 收口');
  assert.match(adapter, /USE_WORKER/, '保留退回主线程直调的开关');
  assert.doesNotMatch(adapter, /^\s*throw\s+\w+\s+as\s+Error/m, 'ArkTS 禁止 throw error as Error（注释里的说明不算）');
});

test('build-profile 注册了两个 Worker，否则不会被打包', () => {
  const profile = read('entry/build-profile.json5');
  assert.match(profile, /\.\/src\/main\/ets\/workers\/ImageSearchWorker\.ets/);
  assert.match(profile, /\.\/src\/main\/ets\/workers\/ImageSearchProbeWorker\.ets/);
});

test('自检覆盖真正卡死过的场景：同一轮连查两次', () => {
  const runner = read('entry/src/main/ets/services/DebugCaptureRunner.ets');
  assert.match(runner, /'一元二次方程'/);
  assert.match(runner, /'平方根'/);
  assert.match(runner, /stage=search q=/);
});
