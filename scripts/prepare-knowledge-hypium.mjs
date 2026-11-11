// 路径: scripts/prepare-knowledge-hypium.mjs
// 职责: 把 agents/common 的 src/test 打包进 entry ohosTest；--check 模式下只校验不改写。
// 约束: generated 副本是易失的，agents/common 的 src/test 才是唯一编辑源。
//
// --check 校验两件事：
//   1) 生成物与源是否一致（missing / stale / orphan）
//   2) 测试从 barrel 导入的符号是否真的被导出（防止模块收口后测试静默失效）
import { mkdirSync, readFileSync, readdirSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, resolve, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const destination = resolve(root, 'entry/src/ohosTest/ets/generated-knowledge-tests');
const checkMode = process.argv.includes('--check');

function rewriteImports(original, module) {
  return original.replace(/from (['"])\.\.\/main\/(.*?)\1/g,
    (_match, quote, path) => `from ${quote}${module}/src/main/${path}${quote}`);
}

function collectSourceFiles(module) {
  const source = resolve(root, module, 'src/test');
  const out = [];
  if (!existsSync(source)) { return out; }
  function walk(relative = '') {
    for (const item of readdirSync(resolve(source, relative), { withFileTypes: true })) {
      const child = relative ? `${relative}/${item.name}` : item.name;
      if (item.isDirectory()) {
        walk(child);
      } else if (item.name.endsWith('.ets')) {
        out.push(child);
      }
    }
  }
  walk();
  return out;
}

/** 收集一个 barrel 导出的全部名字（含 `X as Y` 取 Y）。 */
function exportedNames(barrelPath) {
  const text = readFileSync(barrelPath, 'utf8');
  const names = new Set();
  for (const m of text.matchAll(/export\s+(?:type\s+)?\{([^}]*)\}\s*(?:from\s+['"][^'"]+['"])?;?/g)) {
    for (const raw of m[1].split(',')) {
      const item = raw.trim();
      if (item.length === 0) { continue; }
      const alias = item.split(/\s+as\s+/);
      names.add((alias.length > 1 ? alias[1] : alias[0]).trim());
    }
  }
  for (const m of text.matchAll(/export\s+(?:const|function|class|interface|type|enum)\s+([A-Za-z0-9_]+)/g)) {
    names.add(m[1]);
  }
  return names;
}

/** 把测试里的 import 说明符解析成仓库内路径；解析不到返回 null。 */
function resolveSpecifier(module, spec) {
  if (spec.startsWith('../main/')) {
    return resolve(root, module, 'src', 'main', `${spec.slice('../main/'.length)}.ets`);
  }
  if (/^(agents|common|entry)\/src\//.test(spec)) {
    return resolve(root, `${spec}.ets`);
  }
  return null;
}

function checkBarrelSymbols(module, child) {
  const file = resolve(root, module, 'src/test', child);
  const text = readFileSync(file, 'utf8');
  const problems = [];
  for (const m of text.matchAll(/import\s+(?:type\s+)?\{([^}]*)\}\s+from\s+['"]([^'"]+)['"]/g)) {
    const spec = m[2];
    const resolved = resolveSpecifier(module, spec);
    if (resolved === null || basename(resolved) !== 'Index.ets' || !existsSync(resolved)) { continue; }
    const available = exportedNames(resolved);
    for (const raw of m[1].split(',')) {
      const name = raw.trim().split(/\s+as\s+/)[0].trim();
      if (name.length === 0) { continue; }
      if (!available.has(name)) {
        problems.push(`${module}/src/test/${child}: '${name}' 不在 ${spec} 的导出里`);
      }
    }
  }
  return problems;
}

const drift = [];
const symbolProblems = [];
let count = 0;
const expected = new Set();

for (const module of ['agents', 'common']) {
  for (const child of collectSourceFiles(module)) {
    count++;
    const original = readFileSync(resolve(root, module, 'src/test', child), 'utf8');
    const content = `// Generated from ${module}/src/test/${child}; do not edit.\n${rewriteImports(original, module)}`;
    const target = resolve(destination, module, child);
    const relative = `${module}/${child}`;
    expected.add(relative);
    if (!existsSync(target)) {
      drift.push(`missing ${relative}`);
    } else if (readFileSync(target, 'utf8') !== content) {
      drift.push(`stale   ${relative}`);
    }
    symbolProblems.push(...checkBarrelSymbols(module, child));
  }
}

if (existsSync(destination)) {
  function walkGenerated(relative = '') {
    for (const item of readdirSync(resolve(destination, relative), { withFileTypes: true })) {
      const child = relative ? `${relative}/${item.name}` : item.name;
      if (item.isDirectory()) {
        walkGenerated(child);
      } else if (item.name.endsWith('.ets') && !expected.has(child)) {
        drift.push(`orphan  ${child}`);
      }
    }
  }
  walkGenerated();
}

if (!checkMode) {
  for (const module of ['agents', 'common']) {
    for (const child of collectSourceFiles(module)) {
      const original = readFileSync(resolve(root, module, 'src/test', child), 'utf8');
      const target = resolve(destination, module, child);
      mkdirSync(dirname(target), { recursive: true });
      writeFileSync(target,
        `// Generated from ${module}/src/test/${child}; do not edit.\n${rewriteImports(original, module)}`);
    }
  }
  console.log(`Prepared ${count} Hypium source files for entry ohosTest (not production).`);
  process.exit(0);
}

if (drift.length === 0 && symbolProblems.length === 0) {
  console.log(`[PASS] hypium-check — ${count} 个测试源与生成物一致，barrel 符号全部存在`);
  process.exit(0);
}

console.log('[FAIL] hypium-check');
if (drift.length > 0) {
  console.log('  生成物不一致（先跑 node scripts/prepare-knowledge-hypium.mjs）：');
  for (const item of drift.slice(0, 20)) { console.log('    ' + item); }
}
if (symbolProblems.length > 0) {
  console.log('  测试引用了 barrel 未导出的符号：');
  for (const item of symbolProblems.slice(0, 20)) { console.log('    ' + item); }
}
process.exit(1);
