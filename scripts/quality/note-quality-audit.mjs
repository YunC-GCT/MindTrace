#!/usr/bin/env node
/**
 * scripts/quality/note-quality-audit.mjs — 笔记质量回归报告（P0-3）
 *
 * 用途: 跑真机只读审计 `e2e=noteAudit`（或复用最近一次日志），输出可回归的质量指标：
 *   笔记数 / 学科分布 / 非规范学科占比 / 字段填充率 / 空字段笔记 / 重复标题对。
 * 用法:
 *   node scripts/quality/note-quality-audit.mjs             # 跑设备审计并输出 JSON
 *   node scripts/quality/note-quality-audit.mjs --reuse     # 复用最近一次 audit 日志（不跑设备）
 *   node scripts/quality/note-quality-audit.mjs --assert    # 阈值断言（CI 用）
 * 退出码: 0 = 报告生成；--assert 下 1 = 超阈值。
 */
import { spawnSync } from 'node:child_process';
import { readdirSync, readFileSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const LOG_DIR = join(ROOT, '.device-logs');
const CANONICAL_SUBJECTS = [
  '数学分析', '高等数学', '线性代数', '解析几何', '概率论',
  '最优化方法', '数值分析', '离散数学', '初中数学', '高中数学', '其他',
];
const MAX_DUPLICATE_RATIO = 0.15;
const MAX_BLANK_NOTE_RATIO = 0;
const MAX_NON_CANONICAL_RATIO = 0.2;

function latestAuditLog() {
  if (!existsDir(LOG_DIR)) {
    return '';
  }
  const files = readdirSync(LOG_DIR)
    .filter((name) => name.startsWith('e2e-noteAudit-') && name.endsWith('.log'))
    .map((name) => ({ name, path: join(LOG_DIR, name), mtime: statMtime(join(LOG_DIR, name)) }))
    .sort((a, b) => b.mtime - a.mtime);
  return files.length > 0 ? files[0].path : '';
}

function existsDir(path) {
  try {
    readdirSync(path);
    return true;
  } catch {
    return false;
  }
}

function statMtime(path) {
  try {
    return Number(readFileSync(path, { encoding: 'utf8', flag: 'r' }).length) + 0;
  } catch {
    return 0;
  }
}

function runDeviceAudit() {
  const args = ['scripts/device-runner.mjs', 'e2e', 'noteAudit', '--cold', '--wait', '120'];
  process.stdout.write('[quality] 运行真机审计: node ' + args.join(' ') + '\n');
  const result = spawnSync(process.execPath, args, { cwd: ROOT, encoding: 'utf8' });
  if (result.stdout) {
    process.stdout.write(result.stdout);
  }
  if (result.stderr) {
    process.stderr.write(result.stderr);
  }
  if (result.status !== 0) {
    process.stdout.write('[quality] 设备审计未完成（status=' + result.status + '），尝试复用最近日志\n');
  }
}

function parseAudit(content) {
  const notes = [];
  const notePattern = /audit note id=(\S+) subject=(.*?) category=(\S+) title=(.*?) sections=(.*?) filled=(\d+) empty=(\d+)/g;
  let match;
  while ((match = notePattern.exec(content)) !== null) {
    notes.push({
      id: match[1],
      subject: match[2].trim(),
      category: match[3],
      title: match[4].trim(),
      filled: Number(match[6]),
      empty: Number(match[7]),
    });
  }
  const summary = content.match(/stage=done audit=(\d+) notes=(\d+) duplicatePairs=(\d+) notesWithBlankSections=(\d+)/);
  return {
    notes,
    summary: summary === null
      ? null
      : {
        audit: Number(summary[1]),
        notes: Number(summary[2]),
        duplicatePairs: Number(summary[3]),
        notesWithBlankSections: Number(summary[4]),
      },
  };
}

function buildReport(parsed) {
  const notes = parsed.notes;
  const summary = parsed.summary ?? { audit: 0, notes: notes.length, duplicatePairs: 0, notesWithBlankSections: 0 };
  const total = summary.notes > 0 ? summary.notes : notes.length;
  const subjectCounts = {};
  let nonCanonical = 0;
  let filled = 0;
  let empty = 0;
  for (const note of notes) {
    subjectCounts[note.subject] = (subjectCounts[note.subject] ?? 0) + 1;
    if (!CANONICAL_SUBJECTS.includes(note.subject)) {
      nonCanonical += 1;
    }
    filled += note.filled;
    empty += note.empty;
  }
  const fieldTotal = filled + empty;
  const duplicateRatio = total > 0 ? summary.duplicatePairs / total : 0;
  const nonCanonicalRatio = total > 0 ? nonCanonical / total : 0;
  const blankRatio = total > 0 ? summary.notesWithBlankSections / total : 0;
  return {
    sampledNotes: total,
    subjectDistribution: subjectCounts,
    nonCanonicalSubjectNotes: nonCanonical,
    nonCanonicalRatio: Number(nonCanonicalRatio.toFixed(3)),
    fieldFilledRatio: fieldTotal > 0 ? Number((filled / fieldTotal).toFixed(3)) : null,
    notesWithBlankSections: summary.notesWithBlankSections,
    blankNoteRatio: Number(blankRatio.toFixed(3)),
    duplicatePairs: summary.duplicatePairs,
    duplicateRatio: Number(duplicateRatio.toFixed(3)),
    thresholds: {
      maxDuplicateRatio: MAX_DUPLICATE_RATIO,
      maxBlankNoteRatio: MAX_BLANK_NOTE_RATIO,
      maxNonCanonicalRatio: MAX_NON_CANONICAL_RATIO,
    },
  };
}

function main() {
  const reuse = process.argv.includes('--reuse');
  const assertMode = process.argv.includes('--assert');
  if (!reuse) {
    runDeviceAudit();
  }
  const logPath = latestAuditLog();
  if (logPath === '') {
    process.stdout.write(JSON.stringify({ ok: false, error: 'no-audit-log' }, null, 2) + '\n');
    process.exit(assertMode ? 1 : 0);
  }
  process.stdout.write('[quality] 解析日志: ' + logPath + '\n');
  const report = buildReport(parseAudit(readFileSync(logPath, 'utf8')));
  report.log = logPath;
  process.stdout.write(JSON.stringify(report, null, 2) + '\n');

  if (!assertMode) {
    return;
  }
  const failures = [];
  if (report.duplicateRatio > MAX_DUPLICATE_RATIO) {
    failures.push('duplicateRatio ' + report.duplicateRatio + ' > ' + MAX_DUPLICATE_RATIO);
  }
  if (report.blankNoteRatio > MAX_BLANK_NOTE_RATIO) {
    failures.push('blankNoteRatio ' + report.blankNoteRatio + ' > ' + MAX_BLANK_NOTE_RATIO);
  }
  if (report.nonCanonicalRatio > MAX_NON_CANONICAL_RATIO) {
    failures.push('nonCanonicalRatio ' + report.nonCanonicalRatio + ' > ' + MAX_NON_CANONICAL_RATIO);
  }
  if (failures.length > 0) {
    process.stdout.write('[quality] ASSERT FAILED:\n - ' + failures.join('\n - ') + '\n');
    process.exit(1);
  }
  process.stdout.write('[quality] ASSERT PASSED\n');
}

main();
