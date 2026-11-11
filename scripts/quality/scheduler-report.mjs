#!/usr/bin/env node
/**
 * scripts/quality/scheduler-report.mjs — WriteJob 调度器观测报告（spec 038 A8）
 *
 * 用途: 解析最近 N 份 e2e=schedulerProbe / schedulerIntegration 日志，汇总
 *       [WriteJob] 生命周期事件与 stage=scheduler 统计（submitted/completed/failed/
 *       queueDepth/maxConcurrent/lastWaitMs/lastRunMs），给调度器行为留可回归证据。
 *       S1 不接 run_event（S2 再接），报告以 hilog 事件为准。
 * 用法:
 *   node scripts/quality/scheduler-report.mjs            # 解析最近 1 份两类日志
 *   node scripts/quality/scheduler-report.mjs --samples 3
 *   node scripts/quality/scheduler-report.mjs --reuse    # 只解析，不跑 e2e
 */
import { spawnSync } from 'node:child_process';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const LOG_DIR = join(ROOT, '.device-logs');

function listLogs(prefix) {
  try {
    return readdirSync(LOG_DIR)
      .filter((name) => name.startsWith(prefix) && name.endsWith('.log'))
      .map((name) => ({ name, path: join(LOG_DIR, name), mtime: statSync(join(LOG_DIR, name)).mtimeMs }))
      .sort((a, b) => b.mtime - a.mtime);
  } catch {
    return [];
  }
}

function parseSchedulerLog(path) {
  const content = readFileSync(path, 'utf8');
  const events = { enqueued: 0, started: 0, done: 0, failed: 0 };
  const priorities = [];
  const runEvents = {};
  for (const line of content.split('\n')) {
    const runEventMatch = line.match(/run_event kind=(\S+)/);
    if (runEventMatch !== null) {
      runEvents[runEventMatch[1]] = (runEvents[runEventMatch[1]] ?? 0) + 1;
    }
    const match = line.match(/\[WriteJob\] (enqueued|started|done|failed) id=\S+ priority=(\w+)/);
    if (match !== null) {
      events[match[1]] += 1;
      if (!priorities.includes(match[2])) {
        priorities.push(match[2]);
      }
    }
  }
  const summary = content.match(
    /stage=scheduler done interactiveMs=(\d+) backgroundMs=(\d+)(?: background2Ms=(\d+))? submitted=(\d+) completed=(\d+) failed=(\d+) queueDepth=(\d+) maxConcurrent=(\d+) lastWaitMs=(\d+) lastRunMs=(\d+)/);
  const integrationDelta = content.match(
    /stage=scheduler-integration kind=(\w+) submittedDelta=(\d+) completedDelta=(\d+) failedDelta=(\d+)/);
  const stress = content.match(
    /stage=stress submittedDelta=(\d+) completedDelta=(\d+) failedDelta=(\d+) maxConcurrent=(\d+) queueDepth=(\d+) lastWaitMs=(\d+) lastRunMs=(\d+) persistedEvents=(\d+) terminalCommitted=(\d+) terminalFailed=(\d+)/);
  const inbox = content.match(
    /stage=inbox claimed=(\d+) done=(\d+) failed=(\d+) submittedDelta=(\d+) completedDelta=(\d+) failedDelta=(\d+) maxConcurrent=(\d+)/);
  return {
    events,
    priorities,
    runEvents,
    probe: summary === null ? null : {
      interactiveMs: Number(summary[1]),
      backgroundMs: Number(summary[2]),
      background2Ms: summary[3] !== undefined ? Number(summary[3]) : null,
      submitted: Number(summary[4]),
      completed: Number(summary[5]),
      failed: Number(summary[6]),
      queueDepth: Number(summary[7]),
      maxConcurrent: Number(summary[8]),
      lastWaitMs: Number(summary[9]),
      lastRunMs: Number(summary[10]),
    },
    integration: integrationDelta === null ? null : {
      kind: integrationDelta[1],
      submittedDelta: Number(integrationDelta[2]),
      completedDelta: Number(integrationDelta[3]),
      failedDelta: Number(integrationDelta[4]),
    },
    stress: stress === null ? null : {
      submittedDelta: Number(stress[1]),
      completedDelta: Number(stress[2]),
      failedDelta: Number(stress[3]),
      maxConcurrent: Number(stress[4]),
      queueDepth: Number(stress[5]),
      lastWaitMs: Number(stress[6]),
      lastRunMs: Number(stress[7]),
      persistedEvents: Number(stress[8]),
      terminalCommitted: Number(stress[9]),
      terminalFailed: Number(stress[10]),
    },
    inbox: inbox === null ? null : {
      claimed: Number(inbox[1]),
      done: Number(inbox[2]),
      failed: Number(inbox[3]),
      submittedDelta: Number(inbox[4]),
      completedDelta: Number(inbox[5]),
      failedDelta: Number(inbox[6]),
      maxConcurrent: Number(inbox[7]),
    },
  };
}

function runProbe() {
  const result = spawnSync(process.execPath,
    ['scripts/device-runner.mjs', 'e2e', 'schedulerProbe', '--wait', '600'],
    { cwd: ROOT, encoding: 'utf8' });
  if (result.status !== 0) {
    process.stdout.write('[scheduler] probe exited status=' + result.status + '（继续解析已有日志）\n');
  }
}

function main() {
  const reuse = process.argv.includes('--reuse');
  const samplesIndex = process.argv.indexOf('--samples');
  const samples = samplesIndex >= 0 ? Number(process.argv[samplesIndex + 1]) : 1;
  if (!reuse) {
    for (let i = 0; i < samples; i += 1) {
      process.stdout.write('[scheduler] 采样 ' + (i + 1) + '/' + samples + ' ...\n');
      runProbe();
    }
  }
  const probeLogs = listLogs('e2e-schedulerProbe-').slice(0, Math.max(1, samples));
  const integrationLogs = listLogs('e2e-schedulerIntegration-').slice(0, 1);
  const stressLogs = listLogs('e2e-schedulerStress-').slice(0, 1);
  const inboxLogs = listLogs('e2e-schedulerInbox-').slice(0, 1);
  const report = {
    samples: probeLogs.length,
    probes: probeLogs.map((entry) => ({ name: entry.name, ...parseSchedulerLog(entry.path) })),
    integration: integrationLogs.length > 0
      ? { name: integrationLogs[0].name, ...parseSchedulerLog(integrationLogs[0].path) }
      : null,
    stress: stressLogs.length > 0
      ? { name: stressLogs[0].name, ...parseSchedulerLog(stressLogs[0].path) }
      : null,
    inbox: inboxLogs.length > 0
      ? { name: inboxLogs[0].name, ...parseSchedulerLog(inboxLogs[0].path) }
      : null,
  };
  process.stdout.write(JSON.stringify(report, null, 2) + '\n');
}

main();
