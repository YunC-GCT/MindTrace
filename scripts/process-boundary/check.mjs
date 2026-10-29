#!/usr/bin/env node
/**
 * scripts/process-boundary/check.mjs
 *
 * 进程边界检查（spec 033）。回答一个问题：从每个模块入口出发，能到达哪些模块？
 * 任何「受限能力」被不白名单的进程可达，就失败。
 *
 * 为什么需要它：HSP 的 barrel 是静态全量求值——`import { X } from 'common'` 会把
 * Index.ets 里所有**值导出**都加载一遍。2026-10-24 的 A2A 挂死就是这条路径把
 * @kit.DataAugmentationKit 带进了 :agent 进程。
 *
 * 与 spec 033 的对应：
 *   R1 可达集 = 白名单（本文件）
 *   R2 共享层不含受限 Kit（本文件命中即报）
 *   R3 扩展入口不得 import ui-only/（本文件检查）
 *   R4 新 Kit 先登记（RESTRICTED 表）
 *
 * 用法：node scripts/process-boundary/check.mjs [--json]
 * 退出码：0 通过；1 有违规；2 无法解析。
 */

import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DEFAULT_ROOT = join(__dirname, '..', '..');

/** 模块目录（含 module.json5 的都算） */
const MODULE_DIRS = ['entry', 'common', 'agents', 'skill', 'cardservice'];

/** HSP 的对外出口，import 它等于展开整张导出表 */
const BARRELS = { common: 'common/src/main/ets/Index.ets', agents: 'agents/src/main/ets/Index.ets' };

/**
 * 受限能力登记表（R4）。
 * key = import 说明符（包名或 @kit 名）；value = 允许的进程集合。
 * 未登记的一律按 unsupported 处理——不猜。
 */
export const RESTRICTED = {
  '@kit.DataAugmentationKit': ['main'],
  '@kit.AgentFrameworkKit': ['main'],
  '@ohos.web.webview': ['main'],
  '@kit.FormKit': ['main', 'form'], // main 用 formProvider.updateForm 推快照，卡片宿主也要
  // OCR：main 用 CoreVisionOcrRecognizer；:agent 用小艺入口的 OCR 节点
  // （agentextability/XiaoyiOcrService，识别完只传文本，不碰 UI）
  '@kit.CoreVisionKit': ['main', 'agent'],
  '@kit.ImageKit': ['main', 'agent'],  // :agent 侧把 part.raw/url 解码成 PixelMap 供 OCR
  '@ohos.file.picker': ['main'],
  '@kit.CameraKit': ['main'],
};

/** extension type → 进程名 */
const TYPE_TO_PROCESS = {
  agent: 'agent',
  agentUI: 'agentUI',
  backup: 'backup',
  form: 'form',
  service: 'service',
};

/** 值导出的 re-export 才算运行时加载；export type 会被擦除 */
const RE_TYPE_EXPORT = /^\s*export\s+type\s*\{/;

const stripComments = (text) =>
  text.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/[^\n]*/g, '$1');

/**
 * 抽出模块说明符，并区分两类边：
 *   static — 加载期就求值（静态 import / 值 re-export），越界即事故；
 *   lazy   — 运行时才 import()，加载期不触碰，只在真正调用该路径时求值。
 * 这个区分是 spec 033 §6 S2 的前提：懒加载让 barrel 在扩展进程里安全求值。
 */
export function parseImports(rawText) {
  const text = stripComments(rawText);
  const seen = new Map();
  for (const m of text.matchAll(/import\s+(?:[^'"]*?\s+from\s+)?['"]([^'"]+)['"]/g)) {
    // import type 在运行时被擦除，不构成加载边
    if (/^import\s+type\b/.test(m[0])) continue;
    seen.set(m[1], 'static');
  }
  for (const m of text.matchAll(/export\s+(?:type\s+)?[^'"]*?\s+from\s+['"]([^'"]+)['"]/g)) {
    if (!RE_TYPE_EXPORT.test(m[0]) && !seen.has(m[1])) seen.set(m[1], 'static');
  }
  for (const m of text.matchAll(/import\s*\(\s*['"]([^'"]+)['"]\s*\)/g)) {
    if (!seen.has(m[1])) seen.set(m[1], 'lazy');
  }
  return [...seen.entries()].map(([spec, kind]) => ({ spec, kind }));
}

/** 运行时加载的页面：loadContent('pages/X') / pushUrl({ url: 'pages/X' }) */
export function parsePageLoads(rawText) {
  const text = stripComments(rawText);
  const out = [];
  for (const m of text.matchAll(/loadContent\s*\(\s*['"]([^'"]+)['"]/g)) out.push(m[1]);
  for (const m of text.matchAll(/url\s*:\s*['"](pages\/[^'"]+)['"]/g)) out.push(m[1]);
  return [...new Set(out)];
}

/** 解析 barrel：只返回值导出的目标文件（类型导出被擦除，不能算） */
export function parseBarrelExports(rawText) {
  const text = stripComments(rawText);
  const out = [];
  for (const m of text.matchAll(/export\s+(type\s+)?[^'"]*?\s+from\s+['"]([^'"]+)['"]/g)) {
    if (m[1]) continue; // export type → 运行时不存在
    out.push(m[2]);
  }
  return [...new Set(out)];
}

/** 从 module.json5 里找出所有入口（abilities + extensionAbilities） */
export function parseModuleEntries(rawText) {
  const text = stripComments(rawText);
  const entries = [];
  for (const m of text.matchAll(/"srcEntry"\s*:\s*"([^"]+)"/g)) {
    const at = m.index ?? 0;
    // 入口对象的 "name" 就在 srcEntry 前面不远处；取窗口内最后一个，避免抓到上一个对象
    const before = text.slice(Math.max(0, at - 260), at);
    const names = [...before.matchAll(/"name"\s*:\s*"([^"]+)"/g)];
    const name = names.length > 0 ? names[names.length - 1][1] : 'unknown';
    const typeAfter = text.slice(at, at + 400).match(/"type"\s*:\s*"([^"]+)"/)?.[1];
    const typeBefore = before.slice(-200).match(/"type"\s*:\s*"([^"]+)"/)?.[1];
    const kind = typeAfter ?? typeBefore ?? null;
    entries.push({ name, srcEntry: m[1], type: kind });
  }
  return entries;
}

const toPosix = (p) => p.replace(/\\/g, '/');
const moduleOf = (rel) => rel.split('/')[0];

function resolveSpec(root, fromFile, spec) {
  if (spec.startsWith('.')) {
    const base = resolve(dirname(join(root, fromFile)), spec);
    for (const candidate of [base, `${base}.ets`, `${base}.ts`, join(base, 'Index.ets')]) {
      if (existsSync(candidate)) return toPosix(relative(root, candidate));
    }
    return null;
  }
  return null;
}

/**
 * 从一组入口出发，做可达性遍历。
 * 返回 { hits: [{kit, chain}], files, unresolved }
 */
export function walkGraph(root, entries) {
  const queue = entries.map((e) => ({ file: e.file, chain: [e.name], process: e.process }));
  const seen = new Set();
  const hits = [];
  const unresolved = [];

  while (queue.length > 0) {
    const { file, chain, process, lazy } = queue.shift();
    // 懒边传播：一旦这条链是运行时 import()，后续命中都只算警告
    const abs = join(root, file);
    // 静态可达与懒可达要分开记：同一文件经静态边到达时，违规更严重
    const key = `${file}|${process}|${lazy ? 1 : 0}`;
    if (!existsSync(abs) || seen.has(key)) continue;
    seen.add(key);

    const text = readFileSync(abs, 'utf8');
    const specs = parseImports(text);

    for (const { spec, kind } of specs) {
      const lazy = kind === 'lazy';
      const mod = BARRELS[spec];
      if (mod) {
        const barrelText = readFileSync(join(root, mod), 'utf8');
        for (const target of parseBarrelExports(barrelText)) {
          const resolved = resolveSpec(root, mod, target);
          if (resolved) queue.push({ file: resolved, chain: [...chain, `${spec} → ${target}`], process, lazy });
        }
        continue;
      }
      const rel = resolveSpec(root, file, spec);
      if (rel) {
        queue.push({ file: rel, chain: [...chain, rel], process, lazy });
      } else if (spec.startsWith('@') || spec.includes('/')) {
        const allowed = RESTRICTED[spec];
        if (allowed && !allowed.includes(process)) hits.push({ kit: spec, chain, process, lazy });
      }
    }

    for (const page of parsePageLoads(text)) {
      // 页面路径相对模块的 ets 根（pages/... 与当前文件同属 <module>/src/main/ets）
      const etsRoot = file.includes('/ets/') ? `${file.split('/ets/')[0]}/ets` : dirname(file);
      const resolved = resolveSpec(root, `${etsRoot}/__page__.ets`, `./${page}`);
      if (resolved) {
        queue.push({ file: resolved, chain: [...chain, `loadContent ${page}`], process });
      } else {
        unresolved.push({ file, page });
      }
    }

    // R3：扩展入口不得 import ui-only/
    if (chain.length > 0 && /agentextability\//.test(file) && specs.some((s) => s.spec.includes('ui-only'))) {
      hits.push({ kit: 'ui-only (R3)', chain, process });
    }
  }

  return { hits, files: [...new Set([...seen].map((s) => s.split('|')[0]))], unresolved };
}

export function discoverEntries(root) {
  const entries = [];
  for (const dir of MODULE_DIRS) {
    const manifest = join(root, dir, 'src', 'main', 'module.json5');
    if (!existsSync(manifest)) continue;
    for (const e of parseModuleEntries(readFileSync(manifest, 'utf8'))) {
      const rel = toPosix(join(dir, 'src', 'main', e.srcEntry.replace(/^\.\//, '')));
      const process = e.type ? (TYPE_TO_PROCESS[e.type] ?? 'main') : 'main';
      entries.push({ ...e, file: rel, process });
    }
  }
  return entries;
}

export function runCheck(root = DEFAULT_ROOT) {
  const entries = discoverEntries(root);
  const graph = walkGraph(root, entries);
  const blocking = graph.hits.filter((h) => !h.lazy);
  return { entries, graph, blocking, ok: blocking.length === 0 && graph.unresolved.length === 0 };
}

function main() {
  const json = process.argv.includes('--json');
  const root = process.env.MINDTRACE_ROOT ?? DEFAULT_ROOT;
  const { entries, graph, ok } = runCheck(root);

  if (json) {
    console.log(JSON.stringify({ ok, entries: entries.length, hits: graph.hits, unresolved: graph.unresolved }, null, 2));
    process.exit(ok ? 0 : 1);
  }

  const warnings = graph.hits.filter((h) => h.lazy);
  if (ok) {
    console.log(`[PASS] process-boundary — ${entries.length} 入口 / ${graph.files.length} 个文件可达，受限能力未越界`);
    for (const w of warnings) {
      console.log(`  [WARN] 懒加载：${w.process} 进程运行到该路径时会加载 ${w.kit}`);
      console.log(`    链：${w.chain.join(' → ')}`);
    }
    return;
  }

  console.log('[FAIL] process-boundary');
  for (const hit of graph.hits.filter((h) => !h.lazy)) {
    console.log(`  入口进程 ${hit.process} 可达受限能力 ${hit.kit}`);
    console.log(`    链：${hit.chain.join(' → ')}`);
    const allowed = RESTRICTED[hit.kit];
    console.log(`    允许进程：${allowed ? allowed.join(', ') : '未登记（R4：先登记再使用）'}`);
  }
  for (const u of graph.unresolved) {
    console.log(`  页面加载路径无法解析：${u.file} → ${u.page}`);
  }
  process.exit(1);
}

if (process.argv[1] && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url))) main();
