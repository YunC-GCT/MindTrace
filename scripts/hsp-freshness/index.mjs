/**
 * 路径: scripts/hsp-freshness/index.mjs
 * 职责: HSP 产物新鲜度判据 (issue #219) — 纯函数 + 文件系统事实采集, 供 CLI 与一键构建脚本复用
 *
 * Why: `common` is packaged as an HSP. Building only the HAP can leave
 * `common/build/.../modules.abc` at an old timestamp while the HAP references
 * symbols that were added to `common/src` afterwards. The device then dies at
 * runtime with a `SyntaxError` before the process starts.
 *
 * The decision itself is a pure function (`evaluateFreshness`) so it can be
 * unit-tested without a build tree. `checkHspFreshness` gathers the filesystem
 * facts and returns the same shape instead of exiting, so the one-command build
 * (`scripts/build-hsp-hap.mjs`) can stop between HSP and HAP.
 *
 * Usage:
 *   node scripts/hsp-freshness/index.mjs
 *
 * Exit code: 0 = FRESH, 1 = STALE_ARTIFACT / MISSING_SYMBOL / setup error.
 */

import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');

export const HSP_ARTIFACT_PATH =
  'common/build/default/intermediates/loader_out/default/ets/modules.abc';
/** The whole module source tree, so `module.json5` and resources count too. */
export const HSP_SOURCE_DIR = 'common/src';
/** Spec #219 checks exactly one symbol; no flag, no override. */
export const CHECKED_SYMBOL = 'OnDeviceLlm';
/** The one remediation sentence shared by every failure path. */
export const REBUILD_HSP_HINT =
  '请先重建 HSP（common），再构建 HAP，否则运行期 SyntaxError';

// ---------------------------------------------------------------------------
// pure helpers (exported for tests)
// ---------------------------------------------------------------------------

export function formatMtime(ms) {
  return new Date(ms).toISOString();
}

/**
 * Decide whether an HSP artifact can back a fresh HAP build.
 *
 * Pure: no filesystem access, no clock reads. Callers pass the timestamps and
 * the symbol evidence they already gathered.
 *
 * Rules, in order:
 *   1. `latestSourceMtimeMs >= hspMtimeMs` -> STALE_ARTIFACT (equal counts as
 *      stale: the artifact must be strictly newer than every source file)
 *   2. otherwise `symbolCount <= 0`        -> MISSING_SYMBOL
 *   3. otherwise                           -> FRESH
 *
 * @param {{
 *   hspMtimeMs: number,
 *   latestSourceMtimeMs: number,
 *   symbolCount: number,
 * }} input
 * @returns {{ ok: boolean, code: 'FRESH'|'STALE_ARTIFACT'|'MISSING_SYMBOL', message: string }}
 */
export function evaluateFreshness({ hspMtimeMs, latestSourceMtimeMs, symbolCount }) {
  if (latestSourceMtimeMs >= hspMtimeMs) {
    return {
      ok: false,
      code: 'STALE_ARTIFACT',
      message:
        `HSP 产物未晚于源码（产物 mtime=${formatMtime(hspMtimeMs)}，` +
        `源码最新 mtime=${formatMtime(latestSourceMtimeMs)}）：` +
        REBUILD_HSP_HINT,
    };
  }

  if (symbolCount <= 0) {
    return {
      ok: false,
      code: 'MISSING_SYMBOL',
      message: `HSP 产物中缺少符号 "${CHECKED_SYMBOL}"（命中 0 处）：${REBUILD_HSP_HINT}`,
    };
  }

  return {
    ok: true,
    code: 'FRESH',
    message: `HSP 产物新鲜（晚于 ${HSP_SOURCE_DIR} 最新源码，符号 "${CHECKED_SYMBOL}" 命中 ${symbolCount} 处），可以构建 HAP`,
  };
}

// ---------------------------------------------------------------------------
// filesystem fact gathering (still no process.exit, so the build script can
// branch on the result)
// ---------------------------------------------------------------------------

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

/**
 * Gather filesystem facts under `repoRoot` and evaluate the freshness rule.
 *
 * Never exits: returns a failure result for a missing source tree or artifact,
 * so callers decide whether to stop a build.
 *
 * @param {string} [repoRoot]
 * @returns {{ ok: boolean, code: 'FRESH'|'STALE_ARTIFACT'|'MISSING_SYMBOL'|'MISSING_SOURCE_DIR'|'MISSING_ARTIFACT', message: string }}
 */
export function checkHspFreshness(repoRoot = REPO_ROOT) {
  const hspPath = join(repoRoot, HSP_ARTIFACT_PATH);
  const sourceDir = join(repoRoot, HSP_SOURCE_DIR);

  if (!existsSync(sourceDir)) {
    return {
      ok: false,
      code: 'MISSING_SOURCE_DIR',
      message: `HSP 源码目录不存在：${HSP_SOURCE_DIR}：请确认在仓库根目录执行，或先拉取完整仓库`,
    };
  }

  if (!existsSync(hspPath)) {
    return {
      ok: false,
      code: 'MISSING_ARTIFACT',
      message: `HSP 产物不存在：${HSP_ARTIFACT_PATH}：${REBUILD_HSP_HINT}`,
    };
  }

  return evaluateFreshness({
    hspMtimeMs: statSync(hspPath).mtimeMs,
    latestSourceMtimeMs: latestMtimeMs(sourceDir),
    symbolCount: countOccurrences(readFileSync(hspPath), CHECKED_SYMBOL),
  });
}

// ---------------------------------------------------------------------------
// CLI (process exit only; the gate logic above stays testable)
// ---------------------------------------------------------------------------

function main() {
  const result = checkHspFreshness();

  if (result.ok) {
    console.log(result.message);
    return;
  }

  console.error(result.message);
  process.exit(1);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}
