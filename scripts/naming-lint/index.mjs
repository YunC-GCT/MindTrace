/**
 * scripts/naming-lint/index.mjs
 *
 * Lints file and directory names against docs/style/naming-conventions.md.
 * Source of truth: docs/style/naming-conventions.md
 *
 * Scanned roots (configurable via argv or .naminglintrc.json):
 *   - docs/         (markdown docs, atomic design, langgraph)
 *   - scripts/      (Node tooling)
 *   - frontend/     (React + Atomic Design) — only if exists
 *   - backend/      (LangGraph Python)      — only if exists
 *
 * Rules (see docs/style/naming-conventions.md for full spec):
 *   1. No spaces in any file/dir name
 *   2. kebab-case for docs (`.md`), configs (`.json`, `.yml`, `.toml`, `.json5`)
 *   3. kebab-case for code: `.ts`, `.mjs`, `.cjs`, `.js`
 *   4. PascalCase for React components: `.tsx`
 *   5. snake_case for Python: `.py`
 *   6. Research files end with `-YYYY-MM-DD.md`
 *   7. ADR/Spec have `NNNN-` / `NNN-` prefix respectively
 *   8. No `.html` in `docs/` (gitignored renders)
 *
 * Exemptions (always allowed):
 *   - `README.md` (UPPERCASE top-level index in any doc dir)
 *   - Files starting with `_` (scaffolds, templates)
 *   - Test files: only the prefix-before-`.test.<ext>` is checked
 *
 * Skipped paths (default; project can ADD to via .naminglintrc.json):
 *   - node_modules/, .git/, .hvigor/, build/, oh_modules/, dist/
 *   - .reasonix/ (agent metadata)
 *   - docs/research/_fetched/ (raw fetched material)
 *   - __generated__/, vendor/, third_party/ (codegen / vendored)
 *
 * Exit code: 0 = pass, 1 = violations found.
 */

import { readdirSync, statSync, existsSync } from 'node:fs';
import { join, relative, basename, extname, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { isKebabCase, isPascalCase, isSnakeCase, isIsoDate } from './rule-checkers.mjs';
import { loadConfig } from './config-loader.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, '..', '..');

// Extension → expected-case rule
const RULES = {
  '.md': 'kebab',
  '.markdown': 'kebab',
  '.json': 'kebab',
  '.json5': 'kebab',
  '.yml': 'kebab',
  '.yaml': 'kebab',
  '.toml': 'kebab',
  '.ts': 'kebab',
  '.mjs': 'kebab',
  '.cjs': 'kebab',
  '.js': 'kebab',
  '.tsx': 'pascal-component',
  '.py': 'snake',
};

// ADR / Spec / Research path-specific regexes
const ADR_RE = /^(\d{4})-.+\.md$/;
const SPEC_RE = /^(\d{3})-.+\.md$/;
const RESEARCH_DATE_RE = /-\d{4}-\d{2}-\d{2}\.md$/;

// ----------------------------------------------------------------------------
// Walker (uses Config)
// ----------------------------------------------------------------------------

function walk(rootPath, config, onEntry) {
  const skipDirs = new Set(config.skip.dirs);
  const skipFiles = new Set(config.skip.files);
  const skipPatterns = config.skip.patterns.map((p) => new RegExp(p));

  function isSkipped(name) {
    if (skipDirs.has(name) || skipFiles.has(name)) return true;
    for (const re of skipPatterns) {
      if (re.test(name)) return true;
    }
    return false;
  }

  function visit(p) {
    let st;
    try { st = statSync(p); } catch { return; }
    if (st.isDirectory()) {
      const base = basename(p);
      if (isSkipped(base)) return;
      onEntry({ absPath: p, relPath: relative(REPO_ROOT, p), name: base, isDir: true });
      let entries;
      try { entries = readdirSync(p); } catch { return; }
      for (const child of entries) {
        visit(join(p, child));
      }
    } else if (st.isFile()) {
      const base = basename(p);
      if (isSkipped(base)) return;
      onEntry({ absPath: p, relPath: relative(REPO_ROOT, p), name: base, isDir: false });
    }
  }
  visit(rootPath);
}

/** Strip a known compound extension like `.test.mjs` or `.test.tsx`. */
function stripTestSuffix(name) {
  return name.replace(/\.test\.[a-z]+$/i, '');
}

/** Strip the last (file) extension. */
function stripExt(name) {
  const idx = name.lastIndexOf('.');
  return idx > 0 ? name.slice(0, idx) : name;
}

// ----------------------------------------------------------------------------
// Violation checks
// ----------------------------------------------------------------------------

function checkEntry({ relPath, name, isDir }, violations) {
  // 1. README.md is the agreed UPPERCASE index name (allowed anywhere)
  if (name === 'README.md') return;

  // 2. Files starting with `_` are scaffolds (e.g. _template.mjs)
  // (already excluded by config.skip.patterns '^_', but kept as defense in depth)
  if (name.startsWith('_')) return;

  // 3. No spaces anywhere
  if (/\s/.test(name)) {
    violations.push({ relPath, name, rule: 'no-spaces', msg: 'file/dir name must not contain whitespace' });
    return;
  }

  const ext = extname(name).toLowerCase();

  // 4. .html in docs/ is gitignored render, not source
  // Normalize to forward slashes — `path.relative()` returns OS-native separators
  // (e.g. `docs\foo` on Windows, `docs/foo` on POSIX), so naive startsWith('docs/')
  // silently misses every file on Windows. Bug fixed 2026-09-04.
  const relPathFwd = relPath.replace(/\\/g, '/');
  if (ext === '.html' && relPathFwd.startsWith('docs/')) {
    violations.push({ relPath, name, rule: 'no-html-in-docs', msg: 'HTML files in docs/ must be gitignored renders, not source' });
    return;
  }

  // 5. Directories: kebab-case (universal)
  if (isDir) {
    if (!isKebabCase(name)) {
      violations.push({ relPath, name, rule: 'dir-kebab', msg: 'directory name must be kebab-case' });
    }
    return;
  }

  // 6. ADR / Spec / Research — special prefix/suffix rules
  // All three use the normalized forward-slash path (see HTML check above for why).
  if (relPathFwd.startsWith('docs/adr/') && ext === '.md' && name !== 'index.md') {
    if (!ADR_RE.test(name)) {
      violations.push({ relPath, name, rule: 'adr-prefix', msg: 'ADR must match NNNN-{slug}.md' });
    }
    return;
  }
  if (relPathFwd.startsWith('docs/specs/') && ext === '.md' && name !== 'index.md') {
    if (!SPEC_RE.test(name)) {
      violations.push({ relPath, name, rule: 'spec-prefix', msg: 'Spec must match NNN-{slug}.md' });
    }
    return;
  }
  if (relPathFwd.startsWith('docs/research/') && ext === '.md' && name !== 'index.md') {
    if (!RESEARCH_DATE_RE.test(name)) {
      violations.push({ relPath, name, rule: 'research-date', msg: 'Research file must end with -YYYY-MM-DD.md' });
    }
    return;
  }

  // 7. Test files: check the name BEFORE .test.<ext>
  let checkName = name;
  if (/\.test\.[a-z]+$/i.test(name)) {
    checkName = stripTestSuffix(name);
  }

  const base = stripExt(checkName);

  // 8. Apply case rule by extension
  const expected = RULES[ext];
  if (!expected) return; // unknown extension, skip

  if (expected === 'kebab' && !isKebabCase(base)) {
    violations.push({ relPath, name, rule: `${ext.slice(1)}-kebab`, msg: `${ext} filename must be kebab-case (got "${base}")` });
  } else if (expected === 'snake' && !isSnakeCase(base)) {
    violations.push({ relPath, name, rule: 'py-snake', msg: `.py filename must be snake_case (got "${base}")` });
  } else if (expected === 'pascal-component' && !isPascalCase(base)) {
    violations.push({ relPath, name, rule: 'tsx-pascal', msg: `.tsx component filename must be PascalCase (got "${base}")` });
  }
}

// ----------------------------------------------------------------------------
// Main
// ----------------------------------------------------------------------------

function main() {
  const args = process.argv.slice(2);
  const jsonMode = args.includes('--json');
  const configPath = (() => {
    const i = args.indexOf('--config');
    if (i >= 0 && args[i + 1]) return args[i + 1];
    return undefined;
  })();
  const positional = args.filter((a) => !a.startsWith('--') && a.length > 0);

  let config;
  try {
    config = loadConfig(configPath);
  } catch (err) {
    console.error(`naming-lint: config error: ${err.message}`);
    process.exit(2);
  }

  const scanRoots = positional.length > 0 ? positional : config.roots;
  const violations = [];

  for (const root of scanRoots) {
    const abs = join(REPO_ROOT, root);
    if (!existsSync(abs)) continue; // skip non-existent roots gracefully
    walk(abs, config, (entry) => checkEntry(entry, violations));
  }

  // JSON output mode for CI integration
  if (jsonMode) {
    const report = {
      tool: 'naming-lint',
      version: '0.1.0',
      timestamp: new Date().toISOString(),
      config: config.source ?? '(defaults)',
      roots: scanRoots,
      passed: violations.length === 0,
      violationCount: violations.length,
      violations: violations.map((v) => ({
        path: v.relPath,
        name: v.name,
        rule: v.rule,
        message: v.msg,
      })),
    };
    console.log(JSON.stringify(report, null, 2));
    process.exit(violations.length === 0 ? 0 : 1);
  }

  // Human-readable output mode
  if (violations.length === 0) {
    console.log(`OK: naming-lint passed (0 violations across ${scanRoots.join(', ')})`);
    process.exit(0);
  }

  // Group by rule
  const byRule = new Map();
  for (const v of violations) {
    if (!byRule.has(v.rule)) byRule.set(v.rule, []);
    byRule.get(v.rule).push(v);
  }

  console.error(`FAIL: naming-lint found ${violations.length} violation(s):\n`);
  for (const [rule, list] of byRule) {
    console.error(`  [${rule}] (${list.length})`);
    for (const v of list) {
      console.error(`    ${v.relPath}`);
      console.error(`        → ${v.msg}`);
    }
    console.error('');
  }
  process.exit(1);
}

main();