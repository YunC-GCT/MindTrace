/**
 * math-text-renderer.test.mjs — TDD Red phase: spec 016 PR-B (issue #66)
 *
 * Asserts the source-level state of:
 *   common/src/main/ets/render/MathRenderCache.ets  (new)
 *   entry/src/main/ets/shared/atoms/MathTextRenderer.ets  (cache extracted)
 *
 * Why source-level: the refactor is structural — cache logic moves from
 * MathTextRenderer to MathRenderCache. Hypium tests in
 * common/src/test/MathRenderCache.test.ets (added in this PR) verify the
 * actual cache hit/miss behavior in DevEco.
 *
 * Pass conditions:
 *   - MathRenderCache.ets exports MathRenderCacheEntry class + cacheGet/Set/Remove
 *     + contentHash + 5 capacity constants
 *   - MathRenderCache uses common logger (not uiCacheLog)
 *   - common/Index.ets re-exports MathRenderCache symbols
 *   - MathTextRenderer no longer imports utils/UiCacheDebug
 *   - MathTextRenderer no longer has module-level cache state
 *
 * Out of PR-B scope (deferred to PR-C #67, audit C5):
 *   - Move MathTextRenderer.ets shared/atoms/ → shared/molecules/
 *   - Move MathPreviewText.ets shared/atoms/ → shared/molecules/
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve, join } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const cacheFile = join(root, 'common/src/main/ets/render/MathRenderCache.ets');
const rendererFile = join(root, 'entry/src/main/ets/shared/atoms/MathTextRenderer.ets');
const indexFile = join(root, 'common/src/main/ets/Index.ets');

const cacheSrc = existsSync(cacheFile) ? readFileSync(cacheFile, 'utf8') : '';
const rendererSrc = existsSync(rendererFile) ? readFileSync(rendererFile, 'utf8') : '';
const indexSrc = readFileSync(indexFile, 'utf8');

test('MathRenderCache.ets exists at common/src/main/ets/render/', () => {
  assert.ok(
    existsSync(cacheFile),
    'MathRenderCache.ets must exist at common/src/main/ets/render/MathRenderCache.ets'
  );
});

test('MathRenderCache exports MathRenderCacheEntry class (6 fields with explicit types)', () => {
  assert.match(cacheSrc, /export\s+class\s+MathRenderCacheEntry/);
  const expectedFields = [
    ['key', 'string'],
    ['encodedHtml', 'string'],
    ['height', 'number'],
    ['touched', 'number'],
    ['touchedAt', 'number'],
    ['size', 'number'],
  ];
  for (const [f, t] of expectedFields) {
    assert.match(
      cacheSrc,
      new RegExp(`\\b${f}\\b\\s*:\\s*${t}`),
      `MathRenderCacheEntry missing field '${f}: ${t}'`
    );
  }
});

test('MathRenderCache exports cache functions: cacheGet / cacheSet / cacheRemove', () => {
  assert.match(cacheSrc, /export\s+function\s+cacheGet\s*\(/);
  assert.match(cacheSrc, /export\s+function\s+cacheSet\s*\(/);
  assert.match(cacheSrc, /export\s+function\s+cacheRemove\s*\(/);
});

test('MathRenderCache exports capacity constants', () => {
  const expected = [
    'MATH_RENDER_CACHE_LIMIT',
    'MATH_RENDER_CACHE_MAX_CHARS',
    'MATH_RENDER_CACHE_KEY_VERSION',
    'MATH_RENDER_CACHE_TTL_MS',
    'MATH_RENDER_CACHE_PASSIVE_TRIM_TICKS',
  ];
  for (const c of expected) {
    assert.match(
      cacheSrc,
      new RegExp(`export\\s+const\\s+${c}\\b`),
      `Missing exported const: ${c}`
    );
  }
});

test('MathRenderCache uses common logger (not uiCacheLog)', () => {
  assert.match(
    cacheSrc,
    /from\s*['"]\.\.\/utils\/logger['"]/,
    'MathRenderCache must import from common/utils/logger'
  );
  assert.doesNotMatch(
    cacheSrc,
    /\buiCacheLog\b/,
    'MathRenderCache must not reference uiCacheLog (deleted)'
  );
});

test('MathRenderCache exports contentHash for stable cache keys', () => {
  assert.match(cacheSrc, /export\s+function\s+contentHash\s*\(/);
});

test('common/Index.ets re-exports MathRenderCache symbols', () => {
  assert.match(indexSrc, /\bMathRenderCacheEntry\b/, 'MathRenderCacheEntry not re-exported');
  assert.match(indexSrc, /\bcacheGet\b/, 'cacheGet not re-exported');
  assert.match(indexSrc, /\bcacheSet\b/, 'cacheSet not re-exported');
  assert.match(indexSrc, /\bcacheRemove\b/, 'cacheRemove not re-exported');
  assert.match(indexSrc, /\bcontentHash\b/, 'contentHash not re-exported');
  assert.match(indexSrc, /MATH_RENDER_CACHE_LIMIT/, 'capacity constants not re-exported');
  assert.match(indexSrc, /render\/MathRenderCache/, 'import path missing');
});

test('MathTextRenderer no longer imports utils/UiCacheDebug (spec 012 atom-isolation)', () => {
  assert.doesNotMatch(
    rendererSrc,
    /from\s*['"]\.\.\/\.\.\/utils\/UiCacheDebug['"]/,
    'MathTextRenderer still imports utils/UiCacheDebug'
  );
  assert.doesNotMatch(rendererSrc, /\buiCacheLog\b/, 'MathTextRenderer still references uiCacheLog');
});

test('MathTextRenderer no longer carries module-level cache state (moved out)', () => {
  assert.doesNotMatch(rendererSrc, /^(const|let|export)\s+MATH_RENDER_CACHE\b/m);
  assert.doesNotMatch(rendererSrc, /^(const|let|export)\s+MATH_RENDER_CACHE_LIMIT\b/m);
  assert.doesNotMatch(rendererSrc, /class\s+MathRenderCacheEntry/);
});

test('MathTextRenderer imports cache functions from common (re-exports the seam)', () => {
  assert.match(rendererSrc, /from\s*['"]common['"]/);
  assert.match(rendererSrc, /\bcacheGet\b/);
  assert.match(rendererSrc, /\bcacheSet\b/);
  assert.match(rendererSrc, /\bcacheRemove\b/);
  assert.match(rendererSrc, /\bcontentHash\b/);
});

test('MathTextRenderer LOC reduction: cache section removed', () => {
  // The renderer's only LRU-related symbol is the renderer's scheduling clock
  // (nextRenderDelay / RENDER_DEFER_*) — not the cache clock.
  assert.match(rendererSrc, /\bRENDER_DEFER_BASE_MS\b/);
  assert.match(rendererSrc, /\bnextRenderDelay\b/);
  // Old cache-only helpers must be gone.
  assert.doesNotMatch(rendererSrc, /function\s+cacheGet\s*\(/);
  assert.doesNotMatch(rendererSrc, /function\s+cacheSet\s*\(/);
  assert.doesNotMatch(rendererSrc, /function\s+cacheRemove\s*\(/);
  assert.doesNotMatch(rendererSrc, /function\s+contentHash\s*\(/);
  assert.doesNotMatch(rendererSrc, /function\s+trimCache/);
  assert.doesNotMatch(rendererSrc, /function\s+removeOldestCacheEntry/);
});