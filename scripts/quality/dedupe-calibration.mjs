#!/usr/bin/env node
/**
 * scripts/quality/dedupe-calibration.mjs — 判重灰区日志标定
 *
 * 用途: 解析 `.device-logs` 里的 `[DedupeTrace]`，统计 L1 分 / 向量分 / 裁决分布，
 *       评估「高置信免仲裁窗口」是否成立。只读日志，不跑设备。
 * 用法:
 *   node scripts/quality/dedupe-calibration.mjs
 *   node scripts/quality/dedupe-calibration.mjs --dir .device-logs --json
 * 退出码: 0 = 报告生成（样本不足也返回 0，结论写进报告）。
 */
import { readdirSync, readFileSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const DEFAULT_DIR = join(ROOT, '.device-logs');
const TRACE_RE = /\[DedupeTrace\]\s+(.*)$/;
const TIME_RE = /^(\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3})/;

function parseArgs(argv) {
  const options = { dir: DEFAULT_DIR, json: false };
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === '--dir' && i + 1 < argv.length) {
      options.dir = resolve(argv[i + 1]);
      i += 1;
    } else if (argv[i] === '--json') {
      options.json = true;
    }
  }
  return options;
}

function collectLogs(dir) {
  const files = [];
  const walk = (current) => {
    let entries = [];
    try {
      entries = readdirSync(current, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      const path = join(current, entry.name);
      if (entry.isDirectory()) {
        walk(path);
      } else if (entry.isFile() && entry.name.endsWith('.log')) {
        files.push(path);
      }
    }
  };
  walk(dir);
  return files.sort();
}

function parseTrace(body) {
  const kind = body.startsWith('gray') ? 'gray' : body.startsWith('vector') ? 'vector' : '';
  if (kind.length === 0) {
    return null;
  }
  const vecMatch = body.match(/vec=([0-9.]+)/);
  if (vecMatch === null) {
    return null;
  }
  const l1Match = body.match(/l1=([0-9.]+)/);
  const verdictMatch = body.match(/verdict=(same|supplement|different)/);
  const judgeMatch = body.match(/judge=(\d)/);
  const candidateMatch = body.match(/candidate=(\S+)/);
  // 两分类时代只有 judge=1（同题）与 judge=0（不同）；统一成三分类口径。
  let verdict = 'unknown';
  if (verdictMatch !== null) {
    verdict = verdictMatch[1];
  } else if (judgeMatch !== null) {
    verdict = judgeMatch[1] === '1' ? 'same' : 'different';
  }
  return {
    kind,
    l1: l1Match === null ? null : Number(l1Match[1]),
    vec: Number(vecMatch[1]),
    verdict,
    candidate: candidateMatch === null ? '' : candidateMatch[1],
  };
}

function loadSamples(dir) {
  const samples = [];
  const seen = new Set();
  for (const file of collectLogs(dir)) {
    let text = '';
    try {
      text = readFileSync(file, 'utf8');
    } catch {
      continue;
    }
    const lines = text.split(/\r?\n/);
    for (const line of lines) {
      const traceMatch = line.match(TRACE_RE);
      if (traceMatch === null) {
        continue;
      }
      const timeMatch = line.match(TIME_RE);
      const time = timeMatch === null ? '' : timeMatch[1];
      const key = time + '|' + traceMatch[1];
      if (seen.has(key)) {
        continue;
      }
      seen.add(key);
      const parsed = parseTrace(traceMatch[1]);
      if (parsed !== null) {
        samples.push({ file: file.replace(ROOT + '\\', '').replace(ROOT + '/', ''), time, ...parsed });
      }
    }
  }
  return samples;
}

function range(values) {
  if (values.length === 0) {
    return null;
  }
  return { min: Math.min(...values), max: Math.max(...values) };
}

function summarize(samples) {
  const byKind = { gray: [], vector: [] };
  const byVerdict = {};
  for (const sample of samples) {
    byKind[sample.kind].push(sample);
    byVerdict[sample.verdict] = (byVerdict[sample.verdict] ?? 0) + 1;
  }
  const vectors = samples.map((s) => s.vec);
  const l1s = samples.filter((s) => s.l1 !== null).map((s) => s.l1);
  const perVerdictVec = {};
  for (const verdict of Object.keys(byVerdict)) {
    perVerdictVec[verdict] = range(samples.filter((s) => s.verdict === verdict).map((s) => s.vec));
  }
  return {
    total: samples.length,
    files: [...new Set(samples.map((s) => s.file))].length,
    gray: byKind.gray.length,
    vector: byKind.vector.length,
    verdicts: byVerdict,
    vectorRange: range(vectors),
    l1Range: range(l1s),
    perVerdictVec,
  };
}

function thresholdTable(samples) {
  const thresholds = [0.80, 0.85, 0.90, 0.95];
  return thresholds.map((threshold) => {
    const hit = samples.filter((s) => s.vec >= threshold);
    const counts = {};
    for (const sample of hit) {
      counts[sample.verdict] = (counts[sample.verdict] ?? 0) + 1;
    }
    return { threshold, hit: hit.length, counts };
  });
}

function render(summary, table) {
  const lines = [];
  lines.push('[dedupe-calibration] files=' + summary.files + ' samples=' + summary.total
    + ' gray=' + summary.gray + ' vector=' + summary.vector);
  lines.push('verdicts: ' + JSON.stringify(summary.verdicts));
  lines.push('vec range: ' + JSON.stringify(summary.vectorRange)
    + '  l1 range: ' + JSON.stringify(summary.l1Range));
  lines.push('vec by verdict: ' + JSON.stringify(summary.perVerdictVec));
  lines.push('threshold coverage (vec >= t):');
  for (const row of table) {
    lines.push('  t=' + row.threshold.toFixed(2) + ' hit=' + row.hit
      + ' ' + JSON.stringify(row.counts));
  }
  const negatives = (summary.verdicts.different ?? 0) + (summary.verdicts.unknown ?? 0);
  if (negatives < 5) {
    lines.push('WARN: different/unknown 样本 ' + negatives + ' 条，不足以标定「免仲裁窗口」；'
      + '现有窗口只能证明同题样本，不能证明不会误合并。');
  }
  const sameMax = summary.perVerdictVec.same === null ? null : summary.perVerdictVec.same.max;
  const supplementMax = summary.perVerdictVec.supplement === null ? null : summary.perVerdictVec.supplement.max;
  if (sameMax !== null && supplementMax !== null && sameMax >= supplementMax) {
    lines.push('CONCLUSION: same 与 supplement 在高分段重叠（same max=' + sameMax
      + ', supplement max=' + supplementMax + '），不能只按向量分决定拦下还是写入。');
  }
  return lines.join('\n');
}

const options = parseArgs(process.argv.slice(2));
const samples = loadSamples(options.dir);
const summary = summarize(samples);
const table = thresholdTable(samples);
if (options.json) {
  process.stdout.write(JSON.stringify({ summary, table }, null, 2) + '\n');
} else {
  process.stdout.write(render(summary, table) + '\n');
}
