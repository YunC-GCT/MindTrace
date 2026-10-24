#!/usr/bin/env node
// ============================================================================
//  scripts/e2e-capture/run.mjs — 批量链路真机自检器
//  ----------------------------------------------------------------------------
//  路径: scripts/e2e-capture/run.mjs
//  职责: 一条命令完成「装 HSP/HAP → 带 e2e=true 启动 → 边跑边筛日志 → 判定结果」，
//        省掉手工 hdc 往复和 hilog 抓取，机器等的时间一半以上都耗在那上面。
//  依赖: hdc（DevEco SDK 自带）, 真机已连且解锁
//  数据流: hdc install → aa start --ps e2e true → hdc shell hilog (stream)
//          → 只保留 E2E/ImageSearch/Card 日志 → 读到 stage=done 或超时 → 汇总 → 退出码
//  用法:
//    node scripts/e2e-capture/run.mjs                 # 装 HSP+HAP 再跑
//    node scripts/e2e-capture/run.mjs --no-install    # 只跑，已装好时用
//    node scripts/e2e-capture/run.mjs --with-card     # 连 cardservice 一起装
//    node scripts/e2e-capture/run.mjs --timeout 180   # 放宽等 done 的时间（秒）
//    HDC=/path/to/hdc node scripts/e2e-capture/run.mjs
//  退出码: 0 = 两图都成功且每条检索都有命中；1 = 有失败或超时（原始日志路径会打印）
// ============================================================================

import { spawn, spawnSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const HDC = process.env.HDC ??
  'C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe';
const BUNDLE = 'com.example.mindtrace';
const ABILITY = 'EntryAbility';
const MODULE = 'entry';

const args = process.argv.slice(2);
const hasFlag = (name) => args.includes(name);
const optValue = (name, fallback) => {
  const i = args.indexOf(name);
  return i >= 0 && args[i + 1] !== undefined ? args[i + 1] : fallback;
};

// 单张 capture 实测 6.9s ~ 68.5s（模型调用波动大），默认给足 300s
const TIMEOUT_S = Number(optValue('--timeout', '300'));
// e2e 启动参数：true = 跑完整批量链路；search = 只跑检索探针（每条 20s 上限）
const MODE = optValue('--mode', 'true');
const INSTALL = !hasFlag('--no-install');
const WITH_CARD = hasFlag('--with-card');
const ARTIFACTS = {
  common: 'common/build/default/outputs/default/common-default-signed.hsp',
  entry: 'entry/build/default/outputs/default/entry-default-signed.hap',
  cardservice: 'cardservice/build/default/outputs/default/cardservice-default-signed.hap',
};

// 只看这几类日志：E2E 阶段 / 文搜图 / 卡片快照 / 卡片推帧 / 应用业务日志里的 OCR 相关
const KEEP = /A0E2E0|A0C5D0|A0C4D0|A0C4D1|\[AiService\]|\[Dispatcher\]|\[OcrTool\]|Ability onForeground|Ability onBackground/;

const logFile = resolve(ROOT, '.e2e-run.log');
// 全部原始行留在内存：writeStream 的 flush 是异步的，读完立刻解析会丢尾部
const rawLines = [];
const e2eLines = [];
const searchLines = [];
const probeLines = [];

function hdc(args, { timeout = 240000, quiet = true } = {}) {
  // stdio 必须显式给 pipe+ignore：后台/非 tty 运行时 hdc 会读到 "stdin is not a tty" 直接失败
  const r = spawnSync(HDC, args, { encoding: 'utf8', timeout, cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'] });
  if (process.env.E2E_DEBUG) {
    console.error(`$ hdc ${args.join(' ')} -> rc=${r.status} out=${JSON.stringify((r.stdout ?? '').slice(0, 120))}`);
  }
  if (r.status !== 0 && !quiet) {
    console.error(`[hdc ${args.join(' ')}] exit=${r.status}`);
  }
  return (r.stdout ?? '') + (r.stderr ?? '');
}

/** 不依赖外部 sleep.exe（Windows 上 PATH 未必有） */
function sleepSync(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function step(text) {
  console.log(text);
}

function fail(text) {
  console.error(text);
  writeFileSync(logFile, rawLines.join('\n'));
  process.exitCode = 1;
}

// ---- 0) 前置检查 -----------------------------------------------------------
if (!existsSync(HDC)) {
  fail(`找不到 hdc：${HDC}\n用 HDC=/path/to/hdc 指定，或先装 DevEco Studio。`);
}
const targets = hdc(['list', 'targets']).trim();
if (targets.length === 0 || /Empty/i.test(targets)) {
  fail('没有连接的真机。插上 USB、确认 hdc 授权后再跑。');
}
step(`device: ${targets.split('\n')[0].trim()}`);

// ---- 1) 安装（HSP 必须先于 HAP） -------------------------------------------
if (INSTALL) {
  const order = ['common', 'entry'];
  if (WITH_CARD) {
    order.push('cardservice');
  }
  for (const name of order) {
    // hdc 会把相对路径拼到自己的 cwd 上；绝对路径反而被拼坏，所以这里给相对路径
    const artifact = ARTIFACTS[name];
    if (!existsSync(resolve(ROOT, artifact))) {
      fail(`缺构建产物：${ARTIFACTS[name]}\n先跑 node scripts/build-hsp-hap.mjs`);
    }
    const out = hdc(['install', '-r', artifact]);
    if (!/success|AppMod finish/i.test(out)) {
      fail(`安装 ${name} 失败：${out.trim().split('\n').slice(-3).join(' | ')}`);
    }
    step(`installed ${name}`);
  }
}

// ---- 1.5) 屏幕常亮 ---------------------------------------------------------
// 平板熄屏后应用会被挂起，整轮自检就永远等不到 stage=done。这里直接改系统电源模式，
// 不依赖人手去点屏幕；结束（含超时/失败）时恢复 601 正常模式。
hdc(['shell', 'power-shell', 'wakeup']);
// setmode 602 在平板（MRO-W00）返回 "Set Mode Failed, current mode is: 601"，
// 改用覆盖熄屏超时：-o 毫秒，-r 恢复默认
hdc(['shell', 'power-shell', 'timeout', '-o', '1800000']);
step('screen kept awake (power-shell timeout -o 1800000)');

// ---- 2) 起日志流 -----------------------------------------------------------
hdc(['shell', 'aa', 'force-stop', BUNDLE]);
sleepSync(1000);

// 设备端先按 tag 过滤再回传：整机 hilog 每秒几百行，USB 上必丢（实测 270 次 write socket failed）
const LOG_CMD = 'hilog -T E2E,ImageSearch,CardSnapshot,FormCard,MindTrace';
const stream = spawn(HDC, ['shell', LOG_CMD], { stdio: ['ignore', 'pipe', 'pipe'] });
let buffer = '';
let done = false;
let timedOut = false;

const onLine = (line) => {
  rawLines.push(line);
  if (!KEEP.test(line)) {
    return;
  }
  console.log('  ' + line.replace(/^\S+ \S+ +\d+ +\d+ [IWE] /, ''));
  if (/stage=(pick|capture|card|search|done)/.test(line)) {
    e2eLines.push(line);
  }
  if (/stage=search/.test(line)) {
    searchLines.push(line);
  }
  if (/probe=search/.test(line)) {
    probeLines.push(line);
    if (probeLines.length >= 2) {
      done = true;
      finish(0);
    }
  }
  if (/stage=done/.test(line)) {
    done = true;
    finish(0);
  }
};

stream.stdout.on('data', (chunk) => {
  buffer += chunk.toString('utf8');
  const parts = buffer.split('\n');
  buffer = parts.pop() ?? '';
  for (const line of parts) {
    onLine(line);
  }
});

let finished = false;
function finish(code) {
  if (finished) {
    return;
  }
  finished = true;
  stream.kill();
  hdc(['shell', 'power-shell', 'timeout', '-r']);
  writeFileSync(logFile, rawLines.join('\n'));
  process.exitCode = printSummary() ? 0 : 1;
}

// ---- 3) 触发自检 -----------------------------------------------------------
const started = hdc(['shell', 'aa', 'start', '-a', ABILITY, '-b', BUNDLE, '-m', MODULE, '--ps', 'e2e', MODE]);
if (!/successfully/i.test(started)) {
  fail(`启动失败：${started.trim().split('\n').slice(-2).join(' | ')}\n（真机提示开发者模式时，先在设置里打开开发者选项）`);
}
step(`started ${BUNDLE} with e2e=${MODE}, 等结束信号（上限 ${TIMEOUT_S}s）`);

setTimeout(() => {
  if (!done) {
    timedOut = true;
    console.error(`\n超时 ${TIMEOUT_S}s 未出现 stage=done`);
    finish(1);
  }
}, TIMEOUT_S * 1000);

// ---- 4) 汇总 ---------------------------------------------------------------
function printSummary() {
  // hdc 的 stdout 会按 chunk 切开，流式统计会漏行；结束后从原始日志重新解析才准
  const lines = rawLines.filter((l) => KEEP.test(l));

  // 判定以应用自己的收尾行为准：hilog 流仍会偶发丢中间行（实测 -T 过滤后 seq=2 的 capture 行仍可能丢）
  const doneMatch = /stage=done ok=(\d+) failed=(\d+) totalMs=(\d+)/.exec(rawLines.join('\n'));
  const okCount = doneMatch ? Number(doneMatch[1]) : 0;
  const failedCount = doneMatch ? Number(doneMatch[2]) : -1;
  const totalMs = doneMatch ? Number(doneMatch[3]) : 0;
  const captures = lines.filter((l) => l.includes('stage=capture'));
  const withSource = captures.filter((l) => /sourceImageId=(?!\(空\))/.test(l)).length;
  const hits = lines.filter((l) => l.includes('stage=search') && !l.includes('search-start'))
    .map((l) => {
      const m = /q=(\S+) hits=(\d+)/.exec(l);
      return m ? { q: m[1], hits: Number(m[2]) } : null;
    }).filter(Boolean);
  const noHit = hits.filter((h) => h.hits === 0);
  const cardPushed = lines.some((l) => l.includes('stage=card refresh=1'));

  console.log('\n================ 结果 ================');
  console.log(`抓取     : 成功 ${okCount}，失败 ${failedCount}，总耗时 ${totalMs}ms` +
    (captures.length < okCount ? `（日志收到 ${captures.length} 行 capture，中间行被 hilog 丢了）` : ''));
  console.log(`检索     : ${hits.length} 条` + (hits.length > 0
    ? `（${hits.map((h) => `${h.q}=${h.hits}`).join(', ')}）` : '（没有 search 日志）'));
  if (probeLines.length > 0) {
    console.log(`探针     : ${probeLines.length} 条`);
    for (const line of probeLines) {
      console.log('           ' + line.replace(/^.*E2E: /, ''));
    }
  }
  console.log(`卡片     : ${cardPushed ? '已刷新' : '未刷新'}`);
  const probeOk = probeLines.length === 2 && probeLines.every((l) => /hits=[1-9]/.test(l));
  const verdict = !timedOut && (MODE === 'search'
    ? probeOk
    : doneMatch !== null && okCount === 2 && failedCount === 0 && hits.length >= 1 && noHit.length === 0);
  console.log(`判定     : ${verdict ? 'PASS' : 'FAIL'}`);
  console.log(`原始日志 : ${logFile}`);
  if (!verdict) {
    console.log('排查提示 : 缺 search 日志说明 search() 未返回——先看是否有 [ImageSearch] init ok；');
    console.log('           有 init 无 search 则 textSearchImage.search 阻塞，需查 Kit 对 query 的要求。');
  }
  return verdict;
}
