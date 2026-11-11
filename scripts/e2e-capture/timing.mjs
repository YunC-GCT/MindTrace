#!/usr/bin/env node
// ============================================================================
//  scripts/e2e-capture/timing.mjs — CAPTURE_TIMING 纯解析/统计/格式化
//  ----------------------------------------------------------------------------
//  路径: scripts/e2e-capture/timing.mjs
//  职责: 从 hilog 原始行里解析 AICapture 的 CAPTURE_TIMING 单行契约，
//        汇总冷启首张 / 同进程热态样本，并渲染逐图表格。
//  依赖: 无（纯函数，不碰文件 / 进程 / 网络）
//  数据流: raw log line -> parseCaptureTiming -> records
//          -> summarizeCaptureTimings / formatCaptureTimingTable
// ============================================================================

const MARKER = 'CAPTURE_TIMING';
const VISIT_KEYS = ['capture', 'classify', 'structure', 'truth_check', 'persist'];
const INTEGER_KEYS = [
  'seq',
  'resolveMs',
  'ocrMs',
  'classifyMs',
  'draftMs',
  'truthCheckMs',
  'persistMs',
  'otherMs',
  'totalMs',
];

/**
 * @typedef {Object} CaptureTimingVisits
 * @property {number} capture
 * @property {number} classify
 * @property {number} structure
 * @property {number} truth_check
 * @property {number} persist
 */

/**
 * @typedef {Object} CaptureTimingRecord
 * @property {number} seq
 * @property {'ok'|'error'} outcome
 * @property {number} resolveMs
 * @property {number} ocrMs
 * @property {number} classifyMs
 * @property {number} draftMs
 * @property {number} truthCheckMs
 * @property {number} persistMs
 * @property {number} otherMs
 * @property {number} totalMs
 * @property {CaptureTimingVisits} visits
 */

function asNonNegativeInteger(value) {
  if (typeof value !== 'string' || !/^\d+$/.test(value)) {
    return undefined;
  }
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 0) {
    return undefined;
  }
  return parsed;
}

function parseVisits(raw) {
  if (typeof raw !== 'string' || raw.length === 0) {
    return undefined;
  }
  const visits = {};
  const entries = raw.split(',');
  if (entries.length !== VISIT_KEYS.length) {
    return undefined;
  }
  for (const entry of entries) {
    const colon = entry.indexOf(':');
    if (colon <= 0 || colon === entry.length - 1) {
      return undefined;
    }
    const key = entry.slice(0, colon);
    if (!VISIT_KEYS.includes(key) || visits[key] !== undefined) {
      return undefined;
    }
    const value = asNonNegativeInteger(entry.slice(colon + 1));
    if (value === undefined) {
      return undefined;
    }
    visits[key] = value;
  }
  for (const key of VISIT_KEYS) {
    if (visits[key] === undefined) {
      return undefined;
    }
  }
  return {
    capture: visits.capture,
    classify: visits.classify,
    structure: visits.structure,
    truth_check: visits.truth_check,
    persist: visits.persist,
  };
}

function isValidRecord(record) {
  if (record === null || typeof record !== 'object') {
    return false;
  }
  if (record.outcome !== 'ok' && record.outcome !== 'error') {
    return false;
  }
  for (const key of INTEGER_KEYS) {
    if (!Number.isSafeInteger(record[key]) || record[key] < 0) {
      return false;
    }
  }
  const visits = record.visits;
  if (visits === null || typeof visits !== 'object') {
    return false;
  }
  for (const key of VISIT_KEYS) {
    if (!Number.isSafeInteger(visits[key]) || visits[key] < 0) {
      return false;
    }
  }
  return true;
}

/**
 * Parse one raw hilog line. The marker may appear after the hilog prefix.
 * Returns undefined for missing fields, negative / non-integer numbers,
 * unknown fields, or an outcome other than ok/error.
 * @param {string} line
 * @returns {CaptureTimingRecord|undefined}
 */
export function parseCaptureTiming(line) {
  if (typeof line !== 'string') {
    return undefined;
  }
  const markerAt = line.indexOf(MARKER);
  if (markerAt < 0) {
    return undefined;
  }
  const body = line.slice(markerAt + MARKER.length).trim();
  if (!body.startsWith('seq=')) {
    return undefined;
  }

  const fields = new Map();
  let visitsRaw;
  for (const token of body.split(/\s+/)) {
    const equals = token.indexOf('=');
    if (equals <= 0 || equals === token.length - 1) {
      return undefined;
    }
    const key = token.slice(0, equals);
    const value = token.slice(equals + 1);
    if (key === 'visits') {
      if (visitsRaw !== undefined) {
        return undefined;
      }
      visitsRaw = value;
      continue;
    }
    if (fields.has(key)) {
      return undefined;
    }
    fields.set(key, value);
  }

  const expectedKeys = ['seq', 'outcome', 'resolveMs', 'ocrMs', 'classifyMs', 'draftMs',
    'truthCheckMs', 'persistMs', 'otherMs', 'totalMs'];
  if (fields.size !== expectedKeys.length) {
    return undefined;
  }
  for (const key of expectedKeys) {
    if (!fields.has(key)) {
      return undefined;
    }
  }

  const outcome = fields.get('outcome');
  if (outcome !== 'ok' && outcome !== 'error') {
    return undefined;
  }
  const visits = parseVisits(visitsRaw);
  if (visits === undefined) {
    return undefined;
  }

  const numbers = {};
  for (const key of INTEGER_KEYS) {
    const parsed = asNonNegativeInteger(fields.get(key));
    if (parsed === undefined) {
      return undefined;
    }
    numbers[key] = parsed;
  }

  return {
    seq: numbers.seq,
    outcome: outcome,
    resolveMs: numbers.resolveMs,
    ocrMs: numbers.ocrMs,
    classifyMs: numbers.classifyMs,
    draftMs: numbers.draftMs,
    truthCheckMs: numbers.truthCheckMs,
    persistMs: numbers.persistMs,
    otherMs: numbers.otherMs,
    totalMs: numbers.totalMs,
    visits: visits,
  };
}

function dedupeBySeq(records) {
  const seen = new Set();
  const valid = [];
  for (const record of Array.isArray(records) ? records : []) {
    if (!isValidRecord(record) || seen.has(record.seq)) {
      continue;
    }
    seen.add(record.seq);
    valid.push(record);
  }
  valid.sort((left, right) => left.seq - right.seq);
  return valid;
}

function median(values) {
  if (values.length === 0) {
    return 0;
  }
  const sorted = values.slice(0).sort((left, right) => left - right);
  const middle = Math.floor(sorted.length / 2);
  if (sorted.length % 2 === 1) {
    return sorted[middle];
  }
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

function mean(values) {
  if (values.length === 0) {
    return 0;
  }
  const sum = values.reduce((total, value) => total + value, 0);
  return Math.round((sum / values.length) * 10) / 10;
}

/**
 * Group valid records by sample temperature and summarize warm totalMs.
 * seq=1 = 冷启首张；seq>=2 = 同进程热态。Duplicate seq keeps the first record.
 * @param {CaptureTimingRecord[]} records
 * @returns {{cold: CaptureTimingRecord|null, warm: CaptureTimingRecord[],
 *   warmMedianTotalMs: number, warmMeanTotalMs: number, samples: number}}
 */
export function summarizeCaptureTimings(records) {
  const valid = dedupeBySeq(records);
  let cold = null;
  const warm = [];
  for (const record of valid) {
    if (record.seq === 1) {
      cold = record;
    } else if (record.seq >= 2) {
      warm.push(record);
    }
  }
  const warmTotals = warm.map((record) => record.totalMs);
  return {
    cold: cold,
    warm: warm,
    warmMedianTotalMs: median(warmTotals),
    warmMeanTotalMs: mean(warmTotals),
    samples: valid.length,
  };
}

/**
 * Render a deterministic ASCII table. Returns a short notice when no valid row.
 * @param {CaptureTimingRecord[]} records
 * @returns {string}
 */
export function formatCaptureTimingTable(records) {
  const rows = dedupeBySeq(records);
  if (rows.length === 0) {
    return 'CAPTURE_TIMING: 无有效样本';
  }
  const columns = ['seq', 'sample', 'outcome', 'resolveMs', 'ocrMs', 'classifyMs', 'draftMs',
    'truthCheckMs', 'persistMs', 'otherMs', 'totalMs'];
  const table = [columns];
  for (const record of rows) {
    table.push([
      String(record.seq),
      record.seq === 1 ? 'cold' : 'warm',
      record.outcome,
      String(record.resolveMs),
      String(record.ocrMs),
      String(record.classifyMs),
      String(record.draftMs),
      String(record.truthCheckMs),
      String(record.persistMs),
      String(record.otherMs),
      String(record.totalMs),
    ]);
  }
  const widths = columns.map((column, index) => {
    let width = column.length;
    for (const row of table) {
      width = Math.max(width, row[index].length);
    }
    return width;
  });
  return table.map((row) => row
    .map((cell, index) => (index === 0 ? cell.padEnd(widths[index]) : cell.padStart(widths[index])))
    .join('  '))
    .join('\n');
}
