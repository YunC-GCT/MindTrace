/**
 * scripts/link-check/sync-renames.mjs
 *
 * Updates markdown links when files are renamed or when the referencing
 * document itself is moved with `git mv`. See README.md for the full
 * contract.
 *
 * Usage:
 *   node scripts/link-check/sync-renames.mjs --base <git-ref>
 *   node scripts/link-check/sync-renames.mjs --base <git-ref> --write
 *   node scripts/link-check/sync-renames.mjs --help
 *
 * Exit codes:
 *   0 = dry-run produced (or would produce) suggestions, or --write applied
 *   2 = usage / git error (missing --base, bad ref, not a git repo, ...)
 */

import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync, realpathSync } from 'node:fs';
import { join, relative, isAbsolute, sep } from 'node:path';
import { extractInlineLinks, classifyHref, resolveRel, relativeHref } from './sync-links.mjs';

const LEGACY_PREFIX = 'docs/legacy/';

// ----------------------------------------------------------------------------
// Git plumbing
// ----------------------------------------------------------------------------

function git(args, cwd) {
  return execFileSync('git', args, {
    cwd,
    encoding: 'buffer',
    maxBuffer: 256 * 1024 * 1024,
  }).toString('utf8');
}

function repoRoot(cwd) {
  try {
    return git(['rev-parse', '--show-toplevel'], cwd).trim();
  } catch {
    return null;
  }
}

function verifyRef(root, ref) {
  try {
    git(['rev-parse', '--verify', `${ref}^{commit}`], root);
    return true;
  } catch {
    return false;
  }
}

/**
 * Parse `git diff --name-status -z --find-renames BASE` output.
 * Returns { renames: Map(old->new), renamedFrom: Map(new->old) }.
 * Only explicit renames (status R) are used; copies (C) keep the old path.
 */
function readRenames(root, base) {
  const out = git(['diff', '--name-status', '-z', '--find-renames', base], root);
  const tokens = out.split('\0');
  const renames = new Map();
  const renamedFrom = new Map();

  let i = 0;
  while (i < tokens.length) {
    const status = tokens[i++];
    if (status === '' || status === undefined) continue;
    const kind = status[0];
    if (kind === 'R') {
      const oldPath = tokens[i++];
      const newPath = tokens[i++];
      if (oldPath && newPath) {
        renames.set(oldPath, newPath);
        renamedFrom.set(newPath, oldPath);
      }
    } else if (kind === 'C') {
      // copy: old path still exists — not treated as a rename
      i += 2;
    } else {
      i += 1; // M / A / D / T: single path
    }
  }
  return { renames, renamedFrom };
}

function trackedMarkdownFiles(root) {
  const out = git(['ls-files', '-z'], root);
  const files = out.split('\0').filter(Boolean);
  return files.filter((p) => p.endsWith('.md') && !p.startsWith(LEGACY_PREFIX));
}

// ----------------------------------------------------------------------------
// Filesystem helpers
// ----------------------------------------------------------------------------

function dirOf(relPath) {
  const i = relPath.lastIndexOf('/');
  return i >= 0 ? relPath.slice(0, i) : '';
}

function existsInRepo(root, relPath) {
  if (relPath === '' || relPath.startsWith('..')) return false;
  return existsSync(join(root, relPath));
}

/** Reject targets that are symlinks escaping the repo (or outside it). */
function safeTarget(root, relPath) {
  let abs;
  let real;
  try {
    abs = join(root, relPath);
    real = realpathSync(abs);
  } catch {
    return false;
  }
  try {
    const rootReal = realpathSync(root);
    const rel = relative(rootReal, real);
    if (rel === '') return true;
    return !rel.startsWith('..') && !isAbsolute(rel);
  } catch {
    return false;
  }
}

// ----------------------------------------------------------------------------
// Recovery
// ----------------------------------------------------------------------------

function currentLocation(root, path, renames) {
  let cur = path;
  let guard = 0;
  while (guard++ < 10) {
    if (existsInRepo(root, cur)) return cur;
    const next = renames.get(cur);
    if (!next) return null;
    cur = next;
  }
  return null;
}

// ----------------------------------------------------------------------------
// Main
// ----------------------------------------------------------------------------

function usage() {
  return [
    'Usage: node scripts/link-check/sync-renames.mjs --base <git-ref> [--write]',
    '',
    'Synchronizes relative markdown links after `git mv` renames.',
    '  --base <ref>   Git ref to diff against the working tree (e.g. HEAD, origin/develop, <sha>).',
    '  --write        Apply href replacements. Without it, only a dry-run plan is printed.',
    '  --help         Show this help.',
    '',
    'Exit codes: 0 = suggestions produced (dry-run) / applied (--write); 2 = usage or git error.',
  ].join('\n');
}

function main() {
  const args = process.argv.slice(2);
  if (args.includes('--help') || args.includes('-h')) {
    console.log(usage());
    return 0;
  }

  const baseIdx = args.indexOf('--base');
  const write = args.includes('--write');
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '--base') {
      i++;
      continue;
    }
    if (arg === '--write') continue;
    console.error(`sync-renames: unknown argument "${arg}"`);
    console.error(usage());
    return 2;
  }
  if (baseIdx === -1 || args[baseIdx + 1] === undefined || args[baseIdx + 1].startsWith('--')) {
    console.error('sync-renames: missing required --base <git-ref>');
    console.error(usage());
    return 2;
  }
  const base = args[baseIdx + 1];

  const cwd = process.cwd();
  const root = repoRoot(cwd);
  if (!root) {
    console.error('sync-renames: not a git repository (or git is unavailable)');
    return 2;
  }

  if (!verifyRef(root, base)) {
    console.error(`sync-renames: invalid or unknown git ref for --base: "${base}"`);
    return 2;
  }

  const { renames, renamedFrom } = readRenames(root, base);
  const mdFiles = trackedMarkdownFiles(root);

  const editsByFile = new Map(); // relPath -> { edits: [{line, hrefStart, hrefEnd, oldHref, newHref}], eol, lines }
  const unfixable = [];
  const unsupported = [];
  let renameCount = renames.size;

  for (const file of mdFiles) {
    const abs = join(root, file);
    if (!existsSync(abs)) continue;

    let content;
    try {
      content = readFileSync(abs, 'utf8');
    } catch {
      continue;
    }

    const { links, eol } = extractInlineLinks(content);
    if (links.length === 0) continue;

    const fileEdits = [];
    const fromDir = dirOf(file);
    const oldDir = renamedFrom.has(file) ? dirOf(renamedFrom.get(file)) : fromDir;

    for (const link of links) {
      const cls = classifyHref(link.href);
      if (cls.kind !== 'file') continue;

      // Explicitly unsupported: literal spaces or percent-encoded spaces.
      if (/\s/.test(cls.path) || cls.path.includes('%20')) {
        unsupported.push({ file, line: link.line + 1, href: link.href, reason: 'URL-encoded/space path' });
        continue;
      }

      const resolvedNew = resolveRel(fromDir, cls.path);
      if (resolvedNew === null) {
        unsupported.push({ file, line: link.line + 1, href: link.href, reason: 'resolves outside the repo' });
        continue;
      }
      if (existsInRepo(root, resolvedNew)) continue; // valid — keep as-is

      // Broken: try to recover from the source's old location and/or renames.
      const resolvedOld = resolveRel(oldDir, cls.path);
      const target = resolvedOld === null ? null : currentLocation(root, resolvedOld, renames);
      if (target === null || !existsInRepo(root, target)) {
        unfixable.push({ file, line: link.line + 1, href: link.href, reason: 'no recoverable target' });
        continue;
      }
      if (!safeTarget(root, target)) {
        unsupported.push({ file, line: link.line + 1, href: link.href, reason: 'target escapes repo via symlink' });
        continue;
      }

      const newHref = relativeHref(fromDir, target) + cls.fragment;
      if (newHref === link.href) continue;

      fileEdits.push({
        line: link.line,
        hrefStart: link.hrefStart,
        hrefEnd: link.hrefEnd,
        oldHref: link.href,
        newHref,
      });
    }

    if (fileEdits.length > 0) {
      editsByFile.set(file, { eol, lines: content.split(eol), edits: fileEdits });
    }
  }

  const filesToModify = editsByFile.size;
  let hrefReplacements = 0;
  for (const d of editsByFile.values()) hrefReplacements += d.edits.length;

  // --- Output -----------------------------------------------------------------
  console.log(`# sync-renames ${write ? '(write)' : '(dry-run)'}`);
  console.log(`repo:  ${root}`);
  console.log(`base:  ${base}`);
  console.log(`renames detected: ${renameCount}`);
  console.log(`markdown files scanned: ${mdFiles.length}`);
  console.log('');

  if (filesToModify === 0) {
    console.log('No href replacements needed.');
  } else {
    console.log('Planned href replacements:');
    for (const [file, d] of editsByFile) {
      console.log(`  ${file}`);
      const sorted = [...d.edits].sort((a, b) => a.line - b.line);
      for (const e of sorted) {
        console.log(`    line ${e.line + 1}: ${e.oldHref}  ->  ${e.newHref}`);
      }
    }
    console.log('');
  }

  if (unfixable.length > 0) {
    console.log(`Unfixable broken links (left for link-check): ${unfixable.length}`);
    for (const u of unfixable) {
      console.log(`  ${u.file}:${u.line}  ${u.href}  (${u.reason})`);
    }
    console.log('');
  }

  if (unsupported.length > 0) {
    console.log(`Unsupported paths (not auto-fixed): ${unsupported.length}`);
    for (const u of unsupported) {
      console.log(`  ${u.file}:${u.line}  ${u.href}  (${u.reason})`);
    }
    console.log('');
  }

  console.log(`summary: ${filesToModify} file(s), ${hrefReplacements} href replacement(s), ` +
    `${unfixable.length} unfixable, ${unsupported.length} unsupported`);

  if (write && filesToModify > 0) {
    for (const [file, d] of editsByFile) {
      const lines = d.lines.slice();
      const byLine = new Map();
      for (const e of d.edits) {
        if (!byLine.has(e.line)) byLine.set(e.line, []);
        byLine.get(e.line).push(e);
      }
      for (const [lineIdx, edits] of byLine) {
        edits.sort((a, b) => b.hrefStart - a.hrefStart); // right-to-left
        for (const e of edits) {
          const line = lines[lineIdx];
          lines[lineIdx] = line.slice(0, e.hrefStart) + e.newHref + line.slice(e.hrefEnd);
        }
      }
      writeFileSync(join(root, file), lines.join(d.eol));
    }
    console.log('Applied. (commit is a separate, explicit step)');
  }

  return 0;
}

process.exit(main());
