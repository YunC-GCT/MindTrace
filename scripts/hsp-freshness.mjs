/**
 * scripts/build/hsp-freshness.mjs
 *
 * HSP build-freshness gate (issue #219).
 *
 * Why: `common` is packaged as an HSP. Building only the HAP can leave
 * `common/build/.../modules.abc` at an old timestamp while the HAP references
 * symbols that were added to `common/src/main/ets` afterwards. The device then
 * dies at runtime with a `SyntaxError` before the process starts.
 *
 * The decision itself is a pure function (`evaluateFreshness`) so it can be
 * unit-tested without a build tree. The CLI wrapper gathers filesystem facts:
 *   - HSP artifact mtime
 *   - newest mtime under the HSP source tree
 *   - how often the required symbol appears in the compiled artifact
 *
 * Usage:
 *   node scripts/build/hsp-freshness.mjs [--symbol=OnDeviceLlm]
 *
 * Exit code: 0 = FRESH, 1 = STALE_ARTIFACT / MISSING_SYMBOL / setup error.
 */

import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');

const DEFAULT_HSP_PATH =
  'common/build/default/intermediates/loader_out/default/ets/modules.abc';
const DEFAULT_SOURCE_DIR = 'common/src/main/ets';
const DEFAULT_SYMBOL = 'OnDeviceLlm';

/**
 * Decide whether an HSP artifact can back a fresh HAP build.
 *
 * Pure: no filesystem access, no clock reads. Callers pass the timestamps and
 * the symbol evidence they already gathered.
 *
 * Rules, in order:
 *   1. `latestSourceMtimeMs > hspMtimeMs` -> STALE_ARTIFACT
 *   2. otherwise `symbolCount <= 0`        -> MISSING_SYMBOL
 *   3. otherwise                           -> FRESH
 *
 * @param {{
 *   hspMtimeMs: number,
 *   latestSourceMtimeMs: number,
 *   symbolCount: number,
 *   symbol: string,
 * }} input
 * @returns {{ ok: boolean, code: 'FRESH'|'STALE_ARTIFACT'|'MISSING_SYMBOL', message: string }}
 */
export function evaluateFreshness({ hspMtimeMs, latestSourceMtimeMs, symbolCount, symbol }) {
  if (latestSourceMtimeMs > hspMtimeMs) {
    return {
      ok: false,
      code: 'STALE_ARTIFACT',
      message:
        `HSP 产物早于源码（产物 mtime=${formatMtime(hspMtimeMs)}，` +
        `源码最新 mtime=${formatMtime(latestSourceMtimeMs)}）：` +
        `请先重建 HSP（common），再构建 HAP，否则运行期 SyntaxError`,
    };
  }

  if (symbolCount <= 0) {
    return {
      ok: false,
      code: 'MISSING_SYMBOL',
      message:
        `HSP 产物中缺少符号 "${symbol}"（命中 0 处）：` +
        `请先重建 HSP（common），再构建 HAP，否则运行期 SyntaxError`,
    };
  }

  return {
    ok: true,
    code: 'FRESH',
    message: `HSP 产物新鲜（符号 "${symbol}" 命中 ${symbolCount} 处），可以构建 HAP`,
  };
}

// ---------------------------------------------------------------------------
// CLI (filesystem + process exit; not covered by unit tests)
// ---------------------------------------------------------------------------

function formatMtime(ms) {
  return Number.isFinite(ms) ? new Date(ms).toISOString() : String(ms);
}

/** Newest mtime (epoch ms) of any regular file under `dir`, recursively. */
function latestMtimeMs(dir) {
  let latest = 0;
  const pending = [dir];

  while (pending.length > 0) {
    const current = pending.pop();
    for (const entry of readdirSync(current, { withFileTypes: true })) {
      const entryPath = join(current, entry.name);
      if (entry.isDirectory()) {
        pending.push(entryPath);
      } else if (entry.isFile()) {
        const { mtimeMs } = statSync(entryPath);
        if (mtimeMs > latest) latest = mtimeMs;
      }
    }
  }

  return latest;
}

/** Count non-overlapping byte occurrences of `needle` in `buffer`. */
function countOccurrences(buffer, needle) {
  const target = Buffer.from(needle, 'utf8');
  if (target.length === 0) return 0;

  let count = 0;
  let index = buffer.indexOf(target);
  while (index !== -1) {
    count += 1;
    index = buffer.indexOf(target, index + target.length);
  }
  return count;
}

function parseSymbol(argv) {
  const flag = argv.find((arg) => arg.startsWith('--symbol='));
  return flag ? flag.slice('--symbol='.length) : DEFAULT_SYMBOL;
}

function main(argv) {
  const symbol = parseSymbol(argv);
  const hspPath = join(REPO_ROOT, DEFAULT_HSP_PATH);
  const sourceDir = join(REPO_ROOT, DEFAULT_SOURCE_DIR);

  if (!existsSync(sourceDir)) {
    console.error(
      `HSP 源码目录不存在：${DEFAULT_SOURCE_DIR}：请确认在仓库根目录执行，或先拉取完整仓库`,
    );
    process.exit(1);
  }

  if (!existsSync(hspPath)) {
    console.error(
      `HSP 产物不存在：${DEFAULT_HSP_PATH}：请先重建 HSP（common），再构建 HAP，否则运行期 SyntaxError`,
    );
    process.exit(1);
  }

  const result = evaluateFreshness({
    hspMtimeMs: statSync(hspPath).mtimeMs,
    latestSourceMtimeMs: latestMtimeMs(sourceDir),
    symbolCount: countOccurrences(readFileSync(hspPath), symbol),
    symbol,
  });

  if (result.ok) {
    console.log(result.message);
    return;
  }

  console.error(result.message);
  process.exit(1);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2));
}
