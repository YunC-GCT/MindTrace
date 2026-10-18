#!/usr/bin/env node
/**
 * scripts/agent-gate/index.mjs
 *
 * One-command pre-flight gate for AI coding agents working on MindTrace.
 *
 * Default: inspect the current change set (tracked + untracked) and run:
 *   - .ets hygiene: UTF-8 BOM, file header, module-boundary imports
 *   - arkts-lint (only when .ets files changed)
 *   - naming-lint, link-check, doc-trace
 *
 * Usage:
 *   node scripts/agent-gate/index.mjs
 *   node scripts/agent-gate/index.mjs --all
 *   node scripts/agent-gate/index.mjs --json
 *
 * Exit codes: 0 = pass (warnings allowed), 1 = at least one error, 2 = setup error.
 */

import { execFileSync } from 'node:child_process';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, relative, extname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, '..', '..');
const MODULE_DIRS = ['entry', 'common', 'agents', 'skill', 'cardservice'];
const SKIP_DIRS = new Set(['node_modules', 'oh_modules', 'build', '.hvigor', '.git', '.idea', '.cache', '.test', '.preview', '.cxx', '.gradle']);

// ---------------------------------------------------------------------------
// pure helpers (exported for tests)
// ---------------------------------------------------------------------------

export function hasBom(buffer) {
  return buffer.length >= 3 && buffer[0] === 0xef && buffer[1] === 0xbb && buffer[2] === 0xbf;
}

export function hasFileHeader(text) {
  const head = text.split('\n').slice(0, 30).join('\n');
  return /路径\s*[:：]/.test(head) && /职责\s*[:：]/.test(head);
}

export function boundaryViolations(relPath, text) {
  const out = [];
  const p = relPath.replace(/\\/g, '/');
  const imports = [...text.matchAll(/from\s+['"]([^'"]+)['"]/g)].map((m) => m[1]);

  if (p.startsWith('agents/')) {
    for (const spec of imports) {
      if (spec.startsWith('entry/')) {
        out.push(`agents must not import entry (${spec})`);
      }
    }
  }

  if (/^entry\/src\/main\/ets\/(pages|overlays)\//.test(p)) {
    for (const spec of imports) {
      if (spec.startsWith('agents/src/main/ets/graph/') ||
          spec === 'agents/src/main/ets/core/Dispatcher' ||
          spec.startsWith('entry/src/main/ets/database/NoteDao')) {
        out.push(`page/overlay must go through a service, not ${spec}`);
      }
    }
  }
  return out;
}

export function parseLintSummary(output) {
  const errors = output.match(/Errors:\s+(\d+)/);
  const warnings = output.match(/Warnings:\s+(\d+)/);
  return {
    errors: errors ? Number(errors[1]) : null,
    warnings: warnings ? Number(warnings[1]) : null,
  };
}

export function parseLintJson(output) {
  try {
    const parsed = JSON.parse(output);
    const totals = parsed.totals ?? {};
    return {
      errors: typeof totals.errors === 'number' ? totals.errors : null,
      warnings: typeof totals.warnings === 'number' ? totals.warnings : null,
      filesScanned: typeof parsed.filesScanned === 'number' ? parsed.filesScanned : null,
    };
  } catch {
    return parseLintSummary(output);
  }
}

// ---------------------------------------------------------------------------
// change set
// ---------------------------------------------------------------------------

function git(args) {
  try {
    return execFileSync('git', args, { cwd: REPO_ROOT, encoding: 'utf8' }).trim();
  } catch {
    return '';
  }
}

export function changedFiles(all = false) {
  if (all) {
    const files = [];
    const walk = (dir) => {
      let entries;
      try { entries = readdirSync(dir); } catch { return; }
      for (const entry of entries) {
        if (SKIP_DIRS.has(entry)) continue;
        const p = join(dir, entry);
        let st;
        try { st = statSync(p); } catch { continue; }
        if (st.isDirectory()) walk(p);
        else if (extname(p) === '.ets') files.push(relative(REPO_ROOT, p));
      }
    };
    for (const m of MODULE_DIRS) walk(join(REPO_ROOT, m));
    return files.sort();
  }
  const tracked = git(['diff', '--name-only', 'HEAD']).split('\n').filter(Boolean);
  const untracked = git(['ls-files', '--others', '--exclude-standard']).split('\n').filter(Boolean);
  return [...new Set([...tracked, ...untracked])].sort();
}

// ---------------------------------------------------------------------------
// checks
// ---------------------------------------------------------------------------

function runNode(script, args = []) {
  try {
    const out = execFileSync('node', [script, ...args], {
      cwd: REPO_ROOT,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    return { status: 0, output: out };
  } catch (e) {
    return { status: e.status ?? 1, output: `${e.stdout ?? ''}${e.stderr ?? ''}` };
  }
}

function checkEts(files, all = false) {
  const errors = [];
  const warnings = [];
  for (const rel of files) {
    if (!rel.endsWith('.ets')) continue;
    const abs = join(REPO_ROOT, rel);
    let buffer;
    try { buffer = readFileSync(abs); } catch { continue; }
    if (hasBom(buffer)) errors.push(`${rel}: UTF-8 BOM detected (must be BOM-less)`);
    const text = buffer.toString('utf8');
    if (!all && !hasFileHeader(text)) warnings.push(`${rel}: missing 路径:/职责: file header`);
    for (const v of boundaryViolations(rel, text)) errors.push(`${rel}: ${v}`);
  }
  return { errors, warnings };
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

function main() {
  const args = process.argv.slice(2);
  const all = args.includes('--all');
  const json = args.includes('--json');
  const files = changedFiles(all);
  const changedEts = files.filter((f) => f.endsWith('.ets'));

  const checks = [];
  const ets = checkEts(changedEts, all);
  checks.push({
    name: 'ets-hygiene',
    status: ets.errors.length > 0 ? 'FAIL' : (ets.warnings.length > 0 ? 'WARN' : 'PASS'),
    errors: ets.errors,
    warnings: ets.warnings,
    detail: `${changedEts.length} .ets file(s) inspected`,
  });

  if (changedEts.length > 0 || all) {
    const lint = runNode('scripts/arkts-lint/index.mjs', ['--json']);
    const summary = parseLintJson(lint.output);
    checks.push({
      name: 'arkts-lint',
      status: lint.status === 0 ? 'PASS' : 'FAIL',
      detail: `errors=${summary.errors ?? '?'} warnings=${summary.warnings ?? '?'}`,
      errors: lint.status === 0 ? [] : [lint.output.trim().split('\n').slice(-12).join('\n')],
      warnings: [],
    });
  } else {
    checks.push({ name: 'arkts-lint', status: 'SKIP', detail: 'no .ets changes', errors: [], warnings: [] });
  }

  for (const [name, script] of [
    ['naming-lint', 'scripts/naming-lint/index.mjs'],
    ['link-check', 'scripts/link-check/index.mjs'],
    ['doc-trace', 'scripts/doc-trace/index.mjs'],
  ]) {
    const r = runNode(script);
    checks.push({
      name,
      status: r.status === 0 ? 'PASS' : 'FAIL',
      detail: r.output.trim().split('\n')[0] ?? '',
      errors: r.status === 0 ? [] : [r.output.trim().split('\n').slice(0, 12).join('\n')],
      warnings: [],
    });
  }

  const failed = checks.filter((c) => c.status === 'FAIL');
  const result = {
    ok: failed.length === 0,
    root: REPO_ROOT,
    scope: all ? 'all' : 'changed',
    changed: files.length,
    etsChanged: changedEts.length,
    checks,
  };

  if (json) {
    console.log(JSON.stringify(result, null, 2));
  } else {
    console.log(`agent-gate — ${files.length} ${all ? 'scanned' : 'changed'} file(s), ${changedEts.length} .ets`);
    for (const c of checks) {
      console.log(`  [${c.status}] ${c.name}${c.detail ? ` — ${c.detail}` : ''}`);
      for (const e of c.errors) console.log(`      error: ${e}`);
      for (const w of c.warnings) console.log(`      warn:  ${w}`);
    }
    console.log(result.ok ? 'RESULT: PASS' : 'RESULT: FAIL — fix the first error above, then rerun');
  }
  process.exit(result.ok ? 0 : 1);
}

if (process.argv[1] && join(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main();
}
