import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import {
  stripFences,
  extractLinkTargets,
  resolveTarget,
  checkReachability,
  checkIndexCoverage,
  checkNumbering,
} from '../index.mjs';

function fixture() {
  return mkdtempSync(join(tmpdir(), 'doc-trace-'));
}

test('stripFences removes links inside fenced code blocks', () => {
  const text = '[a](./a.md)\n```\n[b](./b.md)\n```\n[c](./c.md)';
  const clean = stripFences(text);
  assert.equal(clean.includes('b.md'), false);
  assert.equal(clean.includes('a.md'), true);
});

test('extractLinkTargets ignores external links and returns local ones in order', () => {
  const targets = extractLinkTargets('[a](./a.md) [x](https://example.com) [b](b.md#x)');
  assert.deepEqual(targets, ['./a.md', 'b.md#x']);
});

test('resolveTarget maps a directory link to its index.md', () => {
  const dir = fixture();
  try {
    mkdirSync(join(dir, 'sub'));
    writeFileSync(join(dir, 'sub', 'index.md'), '# sub\n');
    const abs = resolveTarget(join(dir, 'index.md'), './sub/');
    assert.equal(abs, join(dir, 'sub', 'index.md'));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('checkReachability reports a file not linked from the entry', () => {
  const dir = fixture();
  try {
    writeFileSync(join(dir, 'index.md'), '# index\n[a](./a.md)\n');
    writeFileSync(join(dir, 'a.md'), '# a\n');
    writeFileSync(join(dir, 'b.md'), '# b\n');
    const violations = checkReachability(dir, join(dir, 'index.md'));
    assert.equal(violations.length, 1);
    assert.equal(violations[0].kind, 'unreachable');
    assert.match(violations[0].file, /b\.md$/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('checkIndexCoverage reports a sibling missing from index.md', () => {
  const dir = fixture();
  try {
    writeFileSync(join(dir, 'index.md'), '# index\n[a](./a.md)\n');
    writeFileSync(join(dir, 'a.md'), '# a\n');
    writeFileSync(join(dir, 'b.md'), '# b\n');
    const violations = checkIndexCoverage(dir);
    assert.equal(violations.length, 1);
    assert.equal(violations[0].kind, 'unlisted');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('checkNumbering reports duplicate spec prefixes', () => {
  const dir = fixture();
  try {
    mkdirSync(join(dir, 'specs'));
    writeFileSync(join(dir, 'specs', '001-a.md'), '# a\n');
    writeFileSync(join(dir, 'specs', '001-b.md'), '# b\n');
    const violations = checkNumbering(dir);
    assert.equal(violations.length, 1);
    assert.equal(violations[0].kind, 'duplicate-number');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
