/**
 * scripts/doc-trace/index.mjs
 *
 * Structural traceability check for the docs corpus:
 *   1. every Markdown file under docs/ is reachable from docs/index.md
 *      through relative links (directory links resolve to their index.md);
 *   2. every directory index lists every non-index Markdown file next to it;
 *   3. spec / ADR numeric prefixes are unique.
 *
 * It does NOT judge technical content or status wording — that stays with
 * docs/agents/document-control.md and human review.
 *
 * Usage:
 *   node scripts/doc-trace/index.mjs
 *   node scripts/doc-trace/index.mjs --json
 *   node scripts/doc-trace/index.mjs docs
 *
 * Exit codes: 0 = clean, 1 = violations, 2 = usage / parser error.
 */

import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs';
import { join, relative, dirname, extname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, '..', '..');
const SKIP_DIRS = new Set(['node_modules', '.git', 'vendor', '__generated__']);

// ---------------------------------------------------------------------------
// helpers (exported for tests)
// ---------------------------------------------------------------------------

/** Remove fenced code blocks so examples do not create graph edges. */
export function stripFences(text) {
  const out = [];
  let fenced = false;
  for (const line of text.split('\n')) {
    if (line.trimStart().startsWith('```')) {
      fenced = !fenced;
      out.push('');
      continue;
    }
    out.push(fenced ? '' : line);
  }
  return out.join('\n');
}

/** Extract inline markdown link targets, in file order. */
export function extractLinkTargets(text) {
  const clean = stripFences(text);
  const targets = [];
  const re = /\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g;
  let m;
  while ((m = re.exec(clean)) !== null) {
    const target = m[1];
    if (/^(https?:|mailto:|tel:)/i.test(target) || target.startsWith('#')) continue;
    targets.push(target);
  }
  return targets;
}

/** Resolve a link target to an absolute path, or null when external. */
export function resolveTarget(fromFile, target) {
  let raw = target.trim();
  if (!raw || raw.startsWith('#') || /^(https?:|mailto:|tel:)/i.test(raw)) return null;
  raw = raw.split('#')[0];
  if (!raw) return null;
  if (raw.startsWith('<') && raw.endsWith('>')) raw = raw.slice(1, -1);
  let abs = resolve(dirname(fromFile), raw);
  if (existsSync(abs) && statSync(abs).isDirectory()) {
    abs = join(abs, 'index.md');
  }
  return abs;
}

/** Walk a root directory and collect Markdown files. */
export function walkMarkdown(root) {
  const files = [];
  function visit(p) {
    let st;
    try { st = statSync(p); } catch { return; }
    if (st.isDirectory()) {
      const base = p.split(/[/\\]/).pop();
      if (SKIP_DIRS.has(base)) return;
      for (const child of readdirSync(p)) visit(join(p, child));
    } else if (st.isFile() && extname(p) === '.md') {
      files.push(p);
    }
  }
  visit(root);
  return files.sort();
}

// ---------------------------------------------------------------------------
// checks
// ---------------------------------------------------------------------------

export function checkReachability(root, entryFile) {
  const files = walkMarkdown(root);
  const known = new Set(files);
  const seen = new Set();
  const queue = [resolve(entryFile)];
  const violations = [];

  while (queue.length > 0) {
    const current = queue.shift();
    if (!known.has(current) || seen.has(current)) continue;
    seen.add(current);
    const text = readFileSync(current, 'utf8');
    for (const target of extractLinkTargets(text)) {
      const abs = resolveTarget(current, target);
      if (abs && known.has(abs) && !seen.has(abs)) queue.push(abs);
    }
  }

  for (const file of files) {
    if (!seen.has(file)) {
      violations.push({
        kind: 'unreachable',
        file: relative(REPO_ROOT, file).replace(/\\/g, '/'),
        detail: 'not reachable from docs/index.md through relative links',
      });
    }
  }
  return violations;
}

export function checkIndexCoverage(root) {
  const files = walkMarkdown(root);
  const byDir = new Map();
  for (const file of files) {
    const dir = dirname(file);
    if (!byDir.has(dir)) byDir.set(dir, []);
    byDir.get(dir).push(file);
  }

  const violations = [];
  for (const [dir, entries] of byDir) {
    const indexPath = join(dir, 'index.md');
    const siblings = entries.filter((f) => f !== indexPath);
    if (siblings.length === 0) continue;
    if (!existsSync(indexPath)) {
      violations.push({
        kind: 'missing-index',
        file: relative(REPO_ROOT, dir).replace(/\\/g, '/'),
        detail: 'directory has markdown files but no index.md',
      });
      continue;
    }
    const indexText = readFileSync(indexPath, 'utf8');
    const linked = new Set();
    for (const target of extractLinkTargets(indexText)) {
      const abs = resolveTarget(indexPath, target);
      if (abs) linked.add(abs);
    }
    for (const sibling of siblings) {
      if (!linked.has(sibling)) {
        violations.push({
          kind: 'unlisted',
          file: relative(REPO_ROOT, sibling).replace(/\\/g, '/'),
          detail: 'not linked from its directory index.md',
        });
      }
    }
  }
  return violations;
}

export function checkNumbering(root) {
  const violations = [];
  const groups = [
    { dir: join(root, 'specs'), re: /^(\d{3})-[a-z0-9-]+\.md$/ },
    { dir: join(root, 'adr'), re: /^(\d{4})-[a-z0-9-]+\.md$/ },
  ];
  for (const { dir, re } of groups) {
    if (!existsSync(dir)) continue;
    const seen = new Map();
    for (const name of readdirSync(dir)) {
      if (!re.test(name)) continue;
      const num = name.match(re)[1];
      if (seen.has(num)) {
        violations.push({
          kind: 'duplicate-number',
          file: relative(REPO_ROOT, join(dir, name)).replace(/\\/g, '/'),
          detail: `prefix ${num} also used by ${seen.get(num)}`,
        });
      } else {
        seen.set(num, name);
      }
    }
  }
  return violations;
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

function main() {
  const args = process.argv.slice(2);
  const json = args.includes('--json');
  const rootArg = args.find((a) => !a.startsWith('-')) ?? 'docs';
  const root = resolve(REPO_ROOT, rootArg);
  const entry = join(root, 'index.md');

  if (!existsSync(entry)) {
    console.error(`doc-trace: entry not found: ${entry}`);
    process.exit(2);
  }

  const violations = [
    ...checkReachability(root, entry),
    ...checkIndexCoverage(root),
    ...checkNumbering(root),
  ];

  if (json) {
    console.log(JSON.stringify({ root: relative(REPO_ROOT, root), violations }, null, 2));
  } else if (violations.length === 0) {
    console.log(`OK: doc-trace passed (${walkMarkdown(root).length} files reachable, indexes complete, numbers unique)`);
  } else {
    console.error(`FAIL: doc-trace found ${violations.length} violation(s)`);
    for (const v of violations) console.error(`  [${v.kind}] ${v.file} — ${v.detail}`);
  }
  process.exit(violations.length === 0 ? 0 : 1);
}

if (process.argv[1] && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url))) {
  main();
}
