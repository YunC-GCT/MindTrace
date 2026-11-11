#!/usr/bin/env node
/**
 * scripts/quality/latency-report.mjs — 单题整理延迟报告（P0-2 第二片）
 *
 * 用途: 跑真机 `e2e=latencyProbe` N 次（或复用已有日志），从 CAPTURE_STAGE / CAPTURE_TOTAL
 *       解析各阶段与总耗时，输出 P50/P95，给「快速路由」前后做可回归对比。
 * 用法:
 *   node scripts/quality/latency-report.mjs                 # 跑 3 次采样并报告
 *   node scripts/quality/latency-report.mjs --samples 5     # 跑 5 次
 *   node scripts/quality/latency-report.mjs --reuse         # 只解析最近 3 份日志
 */
import { spawnSync } from 'node:child_process';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const LOG_DIR = join(ROOT, '.device-logs');
const STAGES = ['capture', 'classify', 'structure', 'truth_check', 'persist'];

function listLogs() {
  try {
    return readdirSync(LOG_DIR)
      .filter((name) => name.startsWith('e2e-latencyProbe-') && name.endsWith('.log'))
      .map((name) => ({ name, path: join(LOG_DIR, name), mtime: statSync(join(LOG_DIR, name)).mtimeMs }))
      .sort((a, b) => b.mtime - a.mtime);
  } catch {
    return [];
  }
}

function parseLog(path) {
  const content = readFileSync(path, 'utf8');
  const stageLine = (stage) => {
    const match = content.match(new RegExp('CAPTURE_STAGE step=' + stage + ' ms=(\\d+)'));
    return match === null ? null : Number(match[1]);
  };
  const totalMatch = content.match(/CAPTURE_TOTAL kind=(\w+) ms=(\d+)/);
  const result = { stages: {}, totalMs: totalMatch === null ? null : Number(totalMatch[2]), kind: totalMatch === null ? '' : totalMatch[1] };
  for (const stage of STAGES) {
    result.stages[stage] = stageLine(stage);
  }
  return result;
}

function percentile(values, p) {
  if (values.length === 0) {
    return null;
  }
  const sorted = values.slice().sort((a, b) => a - b);
  const index = Math.min(sorted.length - 1, Math.ceil((p / 100) * sorted.length) - 1);
  return sorted[Math.max(0, index)];
}

function runProbe() {
  const args = ['scripts/device-runner.mjs', 'e2e', 'latencyProbe', '--wait', '240'];
  const result = spawnSync(process.execPath, args, { cwd: ROOT, encoding: 'utf8' });
  if (result.status !== 0) {
    process.stdout.write('[latency] probe exited status=' + result.status + '（继续解析已有日志）\n');
  }
}

function main() {
  const reuse = process.argv.includes('--reuse');
  const samplesIndex = process.argv.indexOf('--samples');
  const samples = samplesIndex >= 0 ? Number(process.argv[samplesIndex + 1]) : 3;
  let logs = listLogs();
  if (!reuse) {
    const before = logs.length > 0 ? logs[0].mtime : 0;
    for (let i = 0; i < samples; i += 1) {
      process.stdout.write('[latency] 采样 ' + (i + 1) + '/' + samples + ' ...\n');
      runProbe();
    }
    logs = listLogs().filter((entry) => entry.mtime > before);
    if (logs.length === 0) {
      logs = listLogs();
    }
  }
  const picked = logs.slice(0, Math.max(1, samples));
  const runs = picked.map((entry) => ({ name: entry.name, ...parseLog(entry.path) }));
  const totals = runs.map((run) => run.totalMs).filter((value) => value !== null);
  const summary = {
    samples: runs.length,
    totalMs: {
      p50: percentile(totals, 50),
      p95: percentile(totals, 95),
      min: totals.length > 0 ? Math.min(...totals) : null,
      max: totals.length > 0 ? Math.max(...totals) : null,
    },
    stages: {},
    runs,
  };
  for (const stage of STAGES) {
    const values = runs.map((run) => run.stages[stage]).filter((value) => value !== null);
    summary.stages[stage] = {
      p50: percentile(values, 50),
      p95: percentile(values, 95),
      avg: values.length > 0 ? Math.round(values.reduce((sum, value) => sum + value, 0) / values.length) : null,
    };
  }
  process.stdout.write(JSON.stringify(summary, null, 2) + '\n');
}

main();
