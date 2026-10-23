/**
 * scripts/build/hsp-freshness.test.mjs
 *
 * Unit tests for the pure HSP freshness evaluator (issue #219).
 *
 * No filesystem access: `evaluateFreshness` receives timestamps and a symbol
 * count, so the rules are testable without a DevEco build tree. The CLI part
 * of `hsp-freshness.mjs` (fs walking, process.exit) is intentionally not
 * tested here.
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { evaluateFreshness } from './hsp-freshness.mjs';

// Hand-picked epoch-ms literals. The ordering is the whole point, so the
// values are plain round numbers with an explicit, easy-to-audit delta.
const HSP_MTIME = 1_800_000_000_000; // 2027-01-15T08:00:00.000Z
const SOURCE_OLDER = HSP_MTIME - 1_000; // 1s older than the artifact
const SOURCE_NEWER = HSP_MTIME + 1; // 1ms newer than the artifact

test('artifact newer than sources + symbol present => FRESH and ok', () => {
  const result = evaluateFreshness({
    hspMtimeMs: HSP_MTIME,
    latestSourceMtimeMs: SOURCE_OLDER,
    symbolCount: 7,
    symbol: 'OnDeviceLlm',
  });

  assert.equal(result.ok, true);
  assert.equal(result.code, 'FRESH');
});

test('source newer than artifact => STALE_ARTIFACT and not ok', () => {
  const result = evaluateFreshness({
    hspMtimeMs: HSP_MTIME,
    latestSourceMtimeMs: SOURCE_NEWER,
    symbolCount: 7,
    symbol: 'OnDeviceLlm',
  });

  assert.equal(result.ok, false);
  assert.equal(result.code, 'STALE_ARTIFACT');
});

test('equal timestamps but zero symbols => MISSING_SYMBOL and not ok', () => {
  const result = evaluateFreshness({
    hspMtimeMs: HSP_MTIME,
    latestSourceMtimeMs: HSP_MTIME,
    symbolCount: 0,
    symbol: 'OnDeviceLlm',
  });

  assert.equal(result.ok, false);
  assert.equal(result.code, 'MISSING_SYMBOL');
  assert.ok(result.message.includes('OnDeviceLlm'));
});

test('failure messages carry actionable rebuild guidance', () => {
  const stale = evaluateFreshness({
    hspMtimeMs: HSP_MTIME,
    latestSourceMtimeMs: SOURCE_NEWER,
    symbolCount: 7,
    symbol: 'OnDeviceLlm',
  });
  assert.match(stale.message, /HSP 产物早于源码/);
  assert.match(stale.message, /重建/);

  const missing = evaluateFreshness({
    hspMtimeMs: HSP_MTIME,
    latestSourceMtimeMs: HSP_MTIME,
    symbolCount: 0,
    symbol: 'OnDeviceLlm',
  });
  assert.match(missing.message, /OnDeviceLlm/);
  assert.match(missing.message, /重建/);
});

test('equal timestamps with a symbol present stays FRESH (strictly-newer rule)', () => {
  // Clock granularity can make the two timestamps equal; the spec says only
  // `latestSourceMtimeMs > hspMtimeMs` is stale, so equality must pass.
  const result = evaluateFreshness({
    hspMtimeMs: HSP_MTIME,
    latestSourceMtimeMs: HSP_MTIME,
    symbolCount: 1,
    symbol: 'OnDeviceLlm',
  });

  assert.equal(result.ok, true);
  assert.equal(result.code, 'FRESH');
});

test('staleness wins over a missing symbol (root cause reported first)', () => {
  // A stale HSP is the root cause even when the symbol is also absent: the
  // rule order is stale check first, then symbol check.
  const result = evaluateFreshness({
    hspMtimeMs: HSP_MTIME,
    latestSourceMtimeMs: SOURCE_NEWER,
    symbolCount: 0,
    symbol: 'OnDeviceLlm',
  });

  assert.equal(result.ok, false);
  assert.equal(result.code, 'STALE_ARTIFACT');
});
