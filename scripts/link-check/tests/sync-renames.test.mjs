/**
 * scripts/link-check/tests/sync-renames.test.mjs
 *
 * Behaviour tests for the `sync-renames` CLI:
 *
 *   node scripts/link-check/sync-renames.mjs --base <git-ref> [--write]
 *
 * The CLI finds the Git root from the current working directory, reads
 * renames via `git diff --name-status -z --find-renames <base>`, scans
 * tracked markdown links (excluding docs/legacy), and (with --write) fixes
 * only currently-broken hrefs that have a clear rename / old-path basis.
 *
 * Each test builds a throwaway Git repo under os.tmpdir(), commits a known
 * baseline, performs renames, and runs the real CLI via `spawnSync` with the
 * repo as cwd. We assert on observable behaviour (file contents, exit codes),
 * never on a re-implementation of the link-fixing algorithm.
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const __dirname = dirname(fileURLToPath(import.meta.url));
const CLI = resolve(__dirname, '..', 'sync-renames.mjs');

const BODY = 'fixture line one\nfixture line two\nfixture line three\n';
const BODY_B = 'different alpha\ncompletely beta\ngamma delta epsilon\n';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/** Remove a testcase temp dir, but only if it is genuinely inside os.tmpdir(). */
function safeRm(dir) {
  const abs = resolve(dir);
  const tmpBase = resolve(tmpdir()) + sep;
  if (!abs.startsWith(tmpBase)) {
    throw new Error(`refusing to remove path outside tmpdir: ${abs}`);
  }
  rmSync(abs, { recursive: true, force: true });
}

/** Run git in `dir`. Throws if git exits non-zero. */
function git(dir, args) {
  const r = spawnSync('git', args, { cwd: dir, encoding: 'utf8' });
  if (r.status !== 0) {
    throw new Error(`git ${args.join(' ')} failed (${r.status}): ${r.stderr}`);
  }
  return r;
}

/** Create an isolated, identity-configured temp Git repo. */
function makeRepo() {
  const dir = mkdtempSync(join(tmpdir(), 'sync-renames-'));
  git(dir, ['init', '-q']);
  git(dir, ['config', 'user.email', 'sync-renames@example.com']);
  git(dir, ['config', 'user.name', 'sync-renames-test']);
  return dir;
}

function writeFile(dir, rel, content) {
  const abs = join(dir, rel);
  mkdirSync(dirname(abs), { recursive: true });
  writeFileSync(abs, content);
}

function readFile(dir, rel) {
  return readFileSync(join(dir, rel), 'utf8').replace(/\r\n/g, '\n');
}

/** Commit everything and return the commit hash to use as `--base`. */
function commitBase(dir) {
  git(dir, ['add', '-A']);
  git(dir, ['commit', '-q', '-m', 'baseline']);
  return git(dir, ['rev-parse', 'HEAD']).stdout.trim();
}

/** Run the CLI under test. Returns the raw spawnSync result. */
function runCli(cwd, args) {
  if (!existsSync(CLI)) {
    throw new Error('scripts/link-check/sync-renames.mjs is not implemented yet');
  }
  return spawnSync(process.execPath, [CLI, ...args], { cwd, encoding: 'utf8' });
}

/** Assert a successful CLI run; throw a clear error if the CLI is missing. */
function assertExit(res, expectedCode, label) {
  if (res.error) {
    assert.fail(
      `${label}: CLI failed to launch (${res.error.code ?? res.error.message}) — ` +
      `is scripts/link-check/sync-renames.mjs implemented?`,
    );
  }
  assert.equal(res.status, expectedCode, `${label}: stdout=${res.stdout}\nstderr=${res.stderr}`);
  return res;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test('sync-renames CLI is implemented', () => {
  assert.equal(
    existsSync(CLI),
    true,
    'scripts/link-check/sync-renames.mjs does not exist yet (blocking)',
  );
});

test('preview mode (no --write) reports a target move without modifying files', () => {
  const dir = makeRepo();
  try {
    writeFile(dir, 'docs/target.md', BODY);
    writeFile(dir, 'docs/a.md', 'See [T](target.md) for details.\n');
    const base = commitBase(dir);

    git(dir, ['mv', 'docs/target.md', 'docs/renamed.md']);

    const res = runCli(dir, ['--base', base]);
    assertExit(res, 0, 'preview');

    // Preview must not write; the referencing doc keeps its old href.
    assert.equal(readFile(dir, 'docs/a.md'), 'See [T](target.md) for details.\n');
    // A useful preview still names the new location.
    assert.ok(
      (res.stdout + res.stderr).includes('renamed.md'),
      'preview output should mention the new path',
    );
  } finally {
    safeRm(dir);
  }
});

test('--write fixes a moved target href and preserves the fragment', () => {
  const dir = makeRepo();
  try {
    writeFile(dir, 'docs/target.md', BODY);
    writeFile(dir, 'docs/a.md', 'Ref [T](target.md#section-2) here.\n');
    const base = commitBase(dir);

    git(dir, ['mv', 'docs/target.md', 'docs/renamed.md']);

    const res = runCli(dir, ['--base', base, '--write']);
    assertExit(res, 0, 'write');

    assert.equal(readFile(dir, 'docs/a.md'), 'Ref [T](renamed.md#section-2) here.\n');
  } finally {
    safeRm(dir);
  }
});

test('valid links are left untouched', () => {
  const dir = makeRepo();
  try {
    writeFile(dir, 'docs/target.md', BODY);
    writeFile(dir, 'docs/other.md', BODY_B);
    writeFile(dir, 'docs/a.md', '[T](target.md) and [O](other.md)\n');
    const base = commitBase(dir);

    git(dir, ['mv', 'docs/target.md', 'docs/renamed.md']);

    runCli(dir, ['--base', base, '--write']);

    const content = readFile(dir, 'docs/a.md');
    assert.ok(content.includes('[T](renamed.md)'), 'broken link fixed');
    assert.ok(content.includes('[O](other.md)'), 'valid link preserved');
  } finally {
    safeRm(dir);
  }
});

test('a moved referencing document rebases its relative href', () => {
  const dir = makeRepo();
  try {
    writeFile(dir, 'docs/target.md', BODY);
    writeFile(dir, 'docs/a.md', 'See [T](target.md).\n');
    const base = commitBase(dir);

    // The document containing the link moves; the target does not.
    mkdirSync(join(dir, 'docs', 'sub'), { recursive: true });
    git(dir, ['mv', 'docs/a.md', 'docs/sub/a.md']);

    runCli(dir, ['--base', base, '--write']);

    assert.equal(readFile(dir, 'docs/sub/a.md'), 'See [T](../target.md).\n');
  } finally {
    safeRm(dir);
  }
});

test('target and referencing document moving together recomputes the href', () => {
  const dir = makeRepo();
  try {
    writeFile(dir, 'docs/target.md', BODY);
    writeFile(dir, 'docs/a.md', 'See [T](target.md).\n');
    const base = commitBase(dir);

    mkdirSync(join(dir, 'docs', 'sub'), { recursive: true });
    git(dir, ['mv', 'docs/target.md', 'docs/renamed.md']);
    git(dir, ['mv', 'docs/a.md', 'docs/sub/a.md']);

    runCli(dir, ['--base', base, '--write']);

    assert.equal(readFile(dir, 'docs/sub/a.md'), 'See [T](../renamed.md).\n');
  } finally {
    safeRm(dir);
  }
});

test('external URLs and pure anchor links are skipped', () => {
  const dir = makeRepo();
  try {
    writeFile(dir, 'docs/target.md', BODY);
    writeFile(
      dir,
      'docs/a.md',
      '[T](target.md)\n[E](https://example.com/target.md)\n[A](#section)\n',
    );
    const base = commitBase(dir);

    git(dir, ['mv', 'docs/target.md', 'docs/renamed.md']);

    runCli(dir, ['--base', base, '--write']);

    const content = readFile(dir, 'docs/a.md');
    assert.ok(content.includes('[T](renamed.md)'), 'file link fixed');
    assert.ok(content.includes('[E](https://example.com/target.md)'), 'external link preserved');
    assert.ok(content.includes('[A](#section)'), 'anchor link preserved');
  } finally {
    safeRm(dir);
  }
});

test('links inside fenced code blocks and inline code spans are skipped', () => {
  const dir = makeRepo();
  try {
    writeFile(dir, 'docs/target.md', BODY);
    writeFile(
      dir,
      'docs/a.md',
      [
        '[T](target.md)',
        '',
        '```',
        '[F](target.md)',
        '```',
        '',
        'Use `[C](target.md)` inline.',
        '',
      ].join('\n'),
    );
    const base = commitBase(dir);

    git(dir, ['mv', 'docs/target.md', 'docs/renamed.md']);

    runCli(dir, ['--base', base, '--write']);

    const content = readFile(dir, 'docs/a.md');
    assert.ok(content.includes('[T](renamed.md)'), 'real link fixed');
    assert.ok(content.includes('[F](target.md)'), 'fenced code link preserved');
    assert.ok(content.includes('`[C](target.md)`'), 'inline code link preserved');
  } finally {
    safeRm(dir);
  }
});

test('a real link whose label contains backticks is still fixed', () => {
  const dir = makeRepo();
  try {
    writeFile(dir, 'docs/target.md', BODY);
    writeFile(dir, 'docs/a.md', 'See [`T`](target.md).\n');
    const base = commitBase(dir);

    git(dir, ['mv', 'docs/target.md', 'docs/renamed.md']);

    runCli(dir, ['--base', base, '--write']);

    assert.equal(readFile(dir, 'docs/a.md'), 'See [`T`](renamed.md).\n');
  } finally {
    safeRm(dir);
  }
});

test('invalid arguments or refs exit non-zero', () => {
  const dir = makeRepo();
  try {
    writeFile(dir, 'docs/target.md', BODY);
    commitBase(dir);

    assert.notEqual(runCli(dir, []).status, 0, 'missing --base should fail');
    assert.notEqual(runCli(dir, ['--base']).status, 0, 'missing ref value should fail');
    assert.notEqual(runCli(dir, ['--base', 'no-such-ref']).status, 0, 'unknown ref should fail');
  } finally {
    safeRm(dir);
  }
});

test('no renames produce no changes and exit zero', () => {
  const dir = makeRepo();
  try {
    writeFile(dir, 'docs/target.md', BODY);
    writeFile(dir, 'docs/a.md', 'See [T](target.md).\n');
    const base = commitBase(dir);

    const res = runCli(dir, ['--base', base, '--write']);
    assertExit(res, 0, 'no-rename');

    assert.equal(readFile(dir, 'docs/a.md'), 'See [T](target.md).\n');
  } finally {
    safeRm(dir);
  }
});

test('docs/legacy is not auto-modified', () => {
  const dir = makeRepo();
  try {
    writeFile(dir, 'docs/target.md', BODY);
    writeFile(dir, 'docs/a.md', 'See [T](target.md).\n');
    writeFile(dir, 'docs/legacy/old.md', 'Archived [T](target.md).\n');
    const base = commitBase(dir);

    git(dir, ['mv', 'docs/target.md', 'docs/renamed.md']);

    runCli(dir, ['--base', base, '--write']);

    assert.equal(readFile(dir, 'docs/a.md'), 'See [T](renamed.md).\n');
    assert.equal(readFile(dir, 'docs/legacy/old.md'), 'Archived [T](target.md).\n');
  } finally {
    safeRm(dir);
  }
});

test('running --write again after a fix is idempotent', () => {
  const dir = makeRepo();
  try {
    writeFile(dir, 'docs/target.md', BODY);
    writeFile(dir, 'docs/a.md', 'See [T](target.md).\n');
    const base = commitBase(dir);

    git(dir, ['mv', 'docs/target.md', 'docs/renamed.md']);

    assertExit(runCli(dir, ['--base', base, '--write']), 0, 'first write');
    const afterFirst = readFile(dir, 'docs/a.md');

    assertExit(runCli(dir, ['--base', base, '--write']), 0, 'second write');
    assert.equal(readFile(dir, 'docs/a.md'), afterFirst, 'no further changes on second run');
  } finally {
    safeRm(dir);
  }
});

test('a user-modified link is preserved and not overwritten', () => {
  const dir = makeRepo();
  try {
    writeFile(dir, 'docs/target.md', BODY);
    writeFile(dir, 'docs/alt.md', BODY_B);
    writeFile(dir, 'docs/a.md', '[A](target.md)\n[B](target.md)\n');
    const base = commitBase(dir);

    git(dir, ['mv', 'docs/target.md', 'docs/renamed.md']);

    // Simulate the user manually re-pointing one of the two links elsewhere.
    writeFile(dir, 'docs/a.md', '[A](target.md)\n[B](alt.md)\n');

    runCli(dir, ['--base', base, '--write']);

    const content = readFile(dir, 'docs/a.md');
    assert.ok(content.includes('[A](renamed.md)'), 'still-broken link fixed');
    assert.ok(content.includes('[B](alt.md)'), 'user-modified link preserved');
  } finally {
    safeRm(dir);
  }
});

test('does not guess a same-named target without rename evidence', () => {
  const dir = makeRepo();
  try {
    writeFile(dir, 'docs/target.md', BODY);
    writeFile(dir, 'docs/other/target.md', BODY_B);
    writeFile(dir, 'docs/a.md', 'See [T](target.md).\n');
    const base = commitBase(dir);

    // Delete (not rename) docs/target.md. docs/other/target.md remains, but
    // there is no rename evidence tying the broken link to it.
    git(dir, ['rm', '-q', 'docs/target.md']);

    runCli(dir, ['--base', base, '--write']);

    assert.equal(
      readFile(dir, 'docs/a.md'),
      'See [T](target.md).\n',
      'broken link must not be guessed onto docs/other/target.md',
    );
  } finally {
    safeRm(dir);
  }
});
