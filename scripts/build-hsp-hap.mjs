/**
 * 路径: scripts/build-hsp-hap.mjs
 * 职责: 一键构建 — HSP → 新鲜度断言 → HAP (issue #219), 任一步失败即停
 *
 * Why: a HAP-only build can ship against an old `common` HSP and die at runtime
 * with `SyntaxError`. This wrapper makes the correct order the default:
 *
 *   [1/4] assembleHsp(common)       刷新产物
 *   [2/4] checkHspFreshness()       产物必须严格晚于 common/src 且含 OnDeviceLlm
 *   [3/4] assembleHap(entry)        只有断言通过才构建 HAP
 *   [4/4] assembleHap(cardservice)  卡片宿主是独立 HAP，漏构建=桌面图标在但卡片加载不出
 *
 * hvigorw resolution order:
 *   1. $env:HVIGORW (path to hvigorw.js)
 *   2. $env:DEVECO_SDK_HOME/../tools/hvigor/bin/hvigorw.js
 *
 * Usage:
 *   node scripts/build-hsp-hap.mjs
 *
 * Exit code: 0 = HSP + HAP built, 1 = first failing step (build, assertion, or
 * hvigorw not found).
 */

import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { dirname, delimiter, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { checkHspFreshness } from './hsp-freshness/index.mjs';

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const BASE_ARGS = ['--mode', 'module', '-p', 'product=default', '--no-daemon', '--no-incremental'];

const HVIGORW_MISSING_MESSAGE = [
  '找不到 hvigorw.js，无法构建。请按顺序设置其一：',
  '  1. HVIGORW=<DevEco>/tools/hvigor/bin/hvigorw.js',
  '  2. DEVECO_SDK_HOME=<DevEco>/sdk（脚本会再拼 ../tools/hvigor/bin/hvigorw.js）',
  'PowerShell 示例：$env:HVIGORW = "<DevEco>/tools/hvigor/bin/hvigorw.js"',
].join('\n');

/**
 * Resolve the hvigor CLI entry from the environment.
 *
 * @param {Record<string, string | undefined>} [env]
 * @returns {string | null} absolute path to hvigorw.js, or null
 */
export function resolveHvigorw(env = process.env) {
  const candidates = [];
  if (env.HVIGORW) candidates.push(resolve(env.HVIGORW));
  if (env.DEVECO_SDK_HOME) {
    candidates.push(
      resolve(env.DEVECO_SDK_HOME, '..', 'tools', 'hvigor', 'bin', 'hvigorw.js'),
    );
  }
  return candidates.find((candidate) => existsSync(candidate)) ?? null;
}

/**
 * Point the child process at the JDK bundled with DevEco Studio.
 *
 * hvigor packages the HSP with an external `java`; when the shell PATH still
 * holds a deleted IDE, spawn fails with `spawn java ENOENT` even though the
 * build itself is fine. Deriving jbr from hvigorw keeps the script working
 * after an IDE is uninstalled or moved.
 *
 * @param {string} hvigorw absolute path to hvigorw.js
 * @param {Record<string, string | undefined>} env
 * @returns {Record<string, string | undefined>}
 */
export function withBundledJbr(hvigorw, env = process.env) {
  const jbr = resolve(dirname(hvigorw), '..', '..', '..', 'jbr');
  const javaName = process.platform === 'win32' ? 'java.exe' : 'java';
  if (!existsSync(resolve(jbr, 'bin', javaName))) return env;
  const pathKey = Object.keys(env).find((key) => key.toUpperCase() === 'PATH') ?? 'PATH';
  return {
    ...env,
    JAVA_HOME: jbr,
    [pathKey]: `${resolve(jbr, 'bin')}${delimiter}${env[pathKey] ?? ''}`,
  };
}

/** Run one hvigor task; true when the process exits 0. */
function runHvigor(hvigorw, taskArgs) {
  console.log(`  $ node ${hvigorw} ${[...BASE_ARGS, ...taskArgs].join(' ')}`);
  const result = spawnSync(process.execPath, [hvigorw, ...BASE_ARGS, ...taskArgs], {
    cwd: REPO_ROOT,
    stdio: 'inherit',
    env: withBundledJbr(hvigorw),
  });

  if (result.error) {
    console.error(`  构建进程启动失败：${result.error.message}`);
    return false;
  }
  if (result.status !== 0) {
    console.error(`  构建失败（退出码 ${result.status ?? 'unknown'}），停在当前步骤`);
    return false;
  }
  return true;
}

/**
 * Run HSP build, freshness assertion, HAP build in order.
 *
 * @param {Record<string, string | undefined>} [env]
 * @returns {number} process exit code
 */
export function main(env = process.env) {
  const hvigorw = resolveHvigorw(env);
  if (!hvigorw) {
    console.error(HVIGORW_MISSING_MESSAGE);
    return 1;
  }

  console.log('[1/4] 构建 HSP：module=common@default assembleHsp');
  if (!runHvigor(hvigorw, ['-p', 'module=common@default', 'assembleHsp'])) return 1;

  console.log('[2/4] 校验 HSP 新鲜度：common/src 必须早于产物，且产物含 OnDeviceLlm');
  const freshness = checkHspFreshness();
  if (!freshness.ok) {
    console.error(`  断言失败（${freshness.code}）：${freshness.message}`);
    console.error('  已停止：HAP 未构建');
    return 1;
  }
  console.log(`  ${freshness.message}`);

  console.log('[3/4] 构建 HAP：module=entry@default assembleHap');
  if (!runHvigor(hvigorw, ['-p', 'module=entry@default', 'assembleHap'])) return 1;

  console.log('[4/4] 构建卡片 HAP：module=cardservice@default assembleHap');
  if (!runHvigor(hvigorw, ['-p', 'module=cardservice@default', 'assembleHap'])) return 1;

  console.log('完成：HSP、entry HAP、cardservice HAP 均已构建');
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exit(main());
}
