/**
 * 路径: scripts/hsp-freshness/tests/hsp-freshness.test.mjs
 * 职责: HSP 新鲜度判据的单测 (issue #219) — 严格晚于、等时失败、符号缺失
 *
 * No filesystem access: `evaluateFreshness` receives timestamps and a symbol
 * count, so the rules are testable without a DevEco build tree. The filesystem
 * gathering in `checkHspFreshness` is intentionally not tested here.
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { evaluateFreshness, CHECKED_SYMBOL } from '../index.mjs';

// Hand-picked epoch-ms literals. The ordering is the whole point, so the
// values are plain round numbers with an explicit, easy-to-audit delta.
const HSP_MTIME = 1_800_000_000_000; // 2027-01-15T08:00:00.000Z
const SOURCE_OLDER = HSP_MTIME - 1_000; // 1s older than the artifact
const SOURCE_NEWER = HSP_MTIME + 1; // 1ms newer than the artifact

test('artifact strictly newer than sources + symbol present => FRESH and ok', () => {
  const result = evaluateFreshness({
    hspMtimeMs: HSP_MTIME,
    latestSourceMtimeMs: SOURCE_OLDER,
    symbolCount: 7,
  });

  assert.equal(result.ok, true);
  assert.equal(result.code, 'FRESH');
  assert.ok(result.message.includes(CHECKED_SYMBOL));
});

test('artifact newer by a single millisecond => FRESH and ok', () => {
  // "必须晚于" is strict: being newer by 1ms is enough, only <= is stale.
  const result = evaluateFreshness({
    hspMtimeMs: HSP_MTIME,
    latestSourceMtimeMs: HSP_MTIME - 1,
    symbolCount: 1,
  });

  assert.equal(result.ok, true);
  assert.equal(result.code, 'FRESH');
});

test('source newer than artifact => STALE_ARTIFACT and not ok', () => {
  const result = evaluateFreshness({
    hspMtimeMs: HSP_MTIME,
    latestSourceMtimeMs: SOURCE_NEWER,
    symbolCount: 7,
  });

  assert.equal(result.ok, false);
  assert.equal(result.code, 'STALE_ARTIFACT');
});

test('equal timestamps with a symbol present => STALE_ARTIFACT and not ok', () => {
  // The artifact must be strictly newer; equality means the build did not
  // observe the latest source state and must fail.
  const result = evaluateFreshness({
    hspMtimeMs: HSP_MTIME,
    latestSourceMtimeMs: HSP_MTIME,
    symbolCount: 1,
  });

  assert.equal(result.ok, false);
  assert.equal(result.code, 'STALE_ARTIFACT');
});

test('staleness wins over a missing symbol (root cause reported first)', () => {
  // A stale HSP is the root cause even when the symbol is also absent: the
  // rule order is stale check first, then symbol check.
  const result = evaluateFreshness({
    hspMtimeMs: HSP_MTIME,
    latestSourceMtimeMs: HSP_MTIME,
    symbolCount: 0,
  });

  assert.equal(result.ok, false);
  assert.equal(result.code, 'STALE_ARTIFACT');
});

test('fresh artifact with zero symbols => MISSING_SYMBOL and not ok', () => {
  const result = evaluateFreshness({
    hspMtimeMs: HSP_MTIME,
    latestSourceMtimeMs: SOURCE_OLDER,
    symbolCount: 0,
  });

  assert.equal(result.ok, false);
  assert.equal(result.code, 'MISSING_SYMBOL');
  assert.ok(result.message.includes(CHECKED_SYMBOL));
});

test('failure messages carry actionable rebuild guidance', () => {
  const stale = evaluateFreshness({
    hspMtimeMs: HSP_MTIME,
    latestSourceMtimeMs: SOURCE_NEWER,
    symbolCount: 7,
  });
  assert.match(stale.message, /HSP 产物未晚于源码/);
  assert.match(stale.message, /重建/);

  const missing = evaluateFreshness({
    hspMtimeMs: HSP_MTIME,
    latestSourceMtimeMs: SOURCE_OLDER,
    symbolCount: 0,
  });
  assert.match(missing.message, /OnDeviceLlm/);
  assert.match(missing.message, /重建/);
});
