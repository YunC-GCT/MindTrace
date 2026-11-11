#!/usr/bin/env node
// ============================================================================
//  scripts/e2e-capture/timing.test.mjs — CAPTURE_TIMING 解析/统计单测
//  ----------------------------------------------------------------------------
//  路径: scripts/e2e-capture/timing.test.mjs
//  职责: 用 node --test 覆盖正常行、坏行、visits、冷热分组、中位数/均值与表格。
//  依赖: node:test / node:assert（无第三方依赖）
//  数据流: timingLine() -> parseCaptureTiming -> summarize/format 断言
// ============================================================================

import test from 'node:test';
import assert from 'node:assert/strict';
import {
  parseCaptureTiming,
  summarizeCaptureTimings,
  formatCaptureTimingTable,
} from './timing.mjs';

const DEFAULT_FIELDS = {
  seq: 1,
  outcome: 'ok',
  resolveMs: 120,
  ocrMs: 800,
  classifyMs: 900,
  draftMs: 1500,
  truthCheckMs: 300,
  persistMs: 80,
  otherMs: 100,
  totalMs: 3800,
  visits: 'capture:1,classify:1,structure:1,truth_check:1,persist:1',
};

const FIELD_ORDER = ['seq', 'outcome', 'resolveMs', 'ocrMs', 'classifyMs', 'draftMs',
  'truthCheckMs', 'persistMs', 'otherMs', 'totalMs'];

function timingLine(overrides = {}) {
  const values = { ...DEFAULT_FIELDS, ...overrides };
  const parts = [];
  for (const key of FIELD_ORDER) {
    if (values[key] === undefined) {
      continue;
    }
    parts.push(`${key}=${values[key]}`);
  }
  if (values.visits !== undefined) {
    parts.push(`visits=${values.visits}`);
  }
  return `10-27 13:57:28.970 1234 1234 I A00000/MindTrace: [AICapture] CAPTURE_TIMING ${parts.join(' ')}`;
}

test('解析带 hilog 前缀的正常 CAPTURE_TIMING 行', () => {
  const record = parseCaptureTiming(timingLine());
  assert.deepEqual(record, {
    seq: 1,
    outcome: 'ok',
    resolveMs: 120,
    ocrMs: 800,
    classifyMs: 900,
    draftMs: 1500,
    truthCheckMs: 300,
    persistMs: 80,
    otherMs: 100,
    totalMs: 3800,
    visits: {
      capture: 1,
      classify: 1,
      structure: 1,
      truth_check: 1,
      persist: 1,
    },
  });
});

test('不是 CAPTURE_TIMING 的行返回 undefined', () => {
  assert.equal(parseCaptureTiming('[AICapture] capture start'), undefined);
  assert.equal(parseCaptureTiming('CAPTURE_TIMING seq=1'), undefined);
  assert.equal(parseCaptureTiming(''), undefined);
  assert.equal(parseCaptureTiming(undefined), undefined);
});

test('缺字段返回 undefined', () => {
  assert.equal(parseCaptureTiming(timingLine({ totalMs: undefined })), undefined);
  assert.equal(parseCaptureTiming(timingLine({ outcome: undefined })), undefined);
  const withoutVisits = timingLine({ visits: undefined });
  assert.equal(parseCaptureTiming(withoutVisits), undefined);
});

test('非法 outcome 返回 undefined', () => {
  assert.equal(parseCaptureTiming(timingLine({ outcome: 'timeout' })), undefined);
  assert.equal(parseCaptureTiming(timingLine({ outcome: 'OK' })), undefined);
});

test('负数 / 小数 / 非数字字段返回 undefined', () => {
  for (const value of ['-1', '1.5', 'abc', '']) {
    assert.equal(parseCaptureTiming(timingLine({ resolveMs: value })), undefined, `resolveMs=${value}`);
  }
  assert.equal(parseCaptureTiming(timingLine({ seq: '2.0' })), undefined);
});

test('visits 缺项 / 多项 / 非法值返回 undefined', () => {
  assert.equal(parseCaptureTiming(timingLine({
    visits: 'capture:1,classify:1,structure:1,truth_check:1',
  })), undefined);
  assert.equal(parseCaptureTiming(timingLine({
    visits: 'capture:1,classify:1,structure:1,truth_check:1,persist:1,extra:1',
  })), undefined);
  assert.equal(parseCaptureTiming(timingLine({
    visits: 'capture:1,classify:1,structure:1,truth_check:1,persist:x',
  })), undefined);
  assert.equal(parseCaptureTiming(timingLine({
    visits: 'capture:1,capture:1,structure:1,truth_check:1,persist:1',
  })), undefined);
});

test('未执行 step 记 0，visits 也记 0', () => {
  const record = parseCaptureTiming(timingLine({
    ocrMs: 0,
    draftMs: 0,
    persistMs: 0,
    visits: 'capture:0,classify:1,structure:0,truth_check:1,persist:0',
  }));
  assert.equal(record.ocrMs, 0);
  assert.equal(record.draftMs, 0);
  assert.equal(record.persistMs, 0);
  assert.deepEqual(record.visits, {
    capture: 0,
    classify: 1,
    structure: 0,
    truth_check: 1,
    persist: 0,
  });
});

test('同一步多次访问的 visits 计数被保留', () => {
  const record = parseCaptureTiming(timingLine({
    visits: 'capture:2,classify:3,structure:4,truth_check:5,persist:6',
  }));
  assert.deepEqual(record.visits, {
    capture: 2,
    classify: 3,
    structure: 4,
    truth_check: 5,
    persist: 6,
  });
});

test('seq=1 归为冷启首张，seq>=2 归为同进程热态', () => {
  const summary = summarizeCaptureTimings([
    parseCaptureTiming(timingLine({ seq: 1, totalMs: 1000 })),
    parseCaptureTiming(timingLine({ seq: 2, totalMs: 2000 })),
    parseCaptureTiming(timingLine({ seq: 3, totalMs: 3000 })),
  ]);
  assert.equal(summary.cold.seq, 1);
  assert.equal(summary.cold.totalMs, 1000);
  assert.equal(summary.warm.length, 2);
  assert.deepEqual(summary.warm.map((record) => record.seq), [2, 3]);
  assert.equal(summary.samples, 3);
});

test('重复 seq 只保留首条，不重复计数', () => {
  const summary = summarizeCaptureTimings([
    parseCaptureTiming(timingLine({ seq: 2, totalMs: 2000 })),
    parseCaptureTiming(timingLine({ seq: 2, totalMs: 9999 })),
  ]);
  assert.equal(summary.samples, 1);
  assert.equal(summary.warm.length, 1);
  assert.equal(summary.warm[0].totalMs, 2000);
});

test('中位数：奇数样本取中间值', () => {
  const summary = summarizeCaptureTimings([
    parseCaptureTiming(timingLine({ seq: 2, totalMs: 1000 })),
    parseCaptureTiming(timingLine({ seq: 3, totalMs: 3000 })),
    parseCaptureTiming(timingLine({ seq: 4, totalMs: 2000 })),
  ]);
  assert.equal(summary.warmMedianTotalMs, 2000);
});

test('中位数：偶数样本取中间两个均值', () => {
  const summary = summarizeCaptureTimings([
    parseCaptureTiming(timingLine({ seq: 2, totalMs: 1000 })),
    parseCaptureTiming(timingLine({ seq: 3, totalMs: 2000 })),
    parseCaptureTiming(timingLine({ seq: 4, totalMs: 3000 })),
    parseCaptureTiming(timingLine({ seq: 5, totalMs: 4000 })),
  ]);
  assert.equal(summary.warmMedianTotalMs, 2500);
});

test('热态均值按样本数计算', () => {
  const summary = summarizeCaptureTimings([
    parseCaptureTiming(timingLine({ seq: 2, totalMs: 1000 })),
    parseCaptureTiming(timingLine({ seq: 3, totalMs: 2000 })),
    parseCaptureTiming(timingLine({ seq: 4, totalMs: 3001 })),
  ]);
  assert.equal(summary.warmMeanTotalMs, 2000.3);
});

test('坏行 / 非法记录不进汇总', () => {
  const valid = parseCaptureTiming(timingLine());
  const summary = summarizeCaptureTimings([
    valid,
    undefined,
    null,
    { seq: 2 },
    { ...valid, seq: 3, resolveMs: -1 },
    'junk',
  ]);
  assert.equal(summary.samples, 1);
  assert.equal(summary.cold.seq, 1);
  assert.equal(summary.warm.length, 0);
});

test('空样本汇总为零值', () => {
  const summary = summarizeCaptureTimings([]);
  assert.deepEqual(summary, {
    cold: null,
    warm: [],
    warmMedianTotalMs: 0,
    warmMeanTotalMs: 0,
    samples: 0,
  });
});

test('表格包含固定列、按 seq 排序并标注 cold/warm', () => {
  const table = formatCaptureTimingTable([
    parseCaptureTiming(timingLine({ seq: 2, totalMs: 2000 })),
    parseCaptureTiming(timingLine({ seq: 1, totalMs: 1000 })),
  ]);
  const lines = table.split('\n');
  assert.equal(lines.length, 3);
  assert.match(lines[0], /seq\s+sample\s+outcome\s+resolveMs\s+ocrMs\s+classifyMs\s+draftMs\s+truthCheckMs\s+persistMs\s+otherMs\s+totalMs/);
  assert.match(table, /^1\s+cold\s+ok/m);
  assert.match(table, /^2\s+warm\s+ok/m);
  assert.ok(table.indexOf('cold') < table.indexOf('warm'));
});

test('无有效行时表格给出明确提示', () => {
  assert.equal(formatCaptureTimingTable([]), 'CAPTURE_TIMING: 无有效样本');
  assert.equal(formatCaptureTimingTable([null, undefined]), 'CAPTURE_TIMING: 无有效样本');
});
