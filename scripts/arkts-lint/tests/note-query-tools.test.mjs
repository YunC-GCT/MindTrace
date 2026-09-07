import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');

const tools = read('common/src/main/ets/tools/NoteQueryTools.ets');
const commonIndex = read('common/src/main/ets/Index.ets');

// spec 014 §4: P1 只读工具 — note_query / note_get / review_due_query。

test('P1 tools: note_query / note_get / review_due_query exist with exact names', () => {
  assert.match(tools, /export class NoteQueryTool/);
  assert.match(tools, /export class NoteGetTool/);
  assert.match(tools, /export class ReviewDueQueryTool/);
  assert.match(tools, /'note_query'/);
  assert.match(tools, /'note_get'/);
  assert.match(tools, /'review_due_query'/);
  assert.match(tools, /export function createReadOnlyNoteTools\(\): AgentTool\[\]/);
});

test('read-only guarantee: no write calls anywhere in the tool file', () => {
  assert.doesNotMatch(tools, /\.insert\(/);
  assert.doesNotMatch(tools, /\.update\(/);
  assert.doesNotMatch(tools, /\.delete\(/);
  assert.doesNotMatch(tools, /INSERT INTO|DELETE FROM/);
});

test('topology red line: no entry imports', () => {
  assert.doesNotMatch(tools, /from ['"].*entry/);
});

test('schema source-of-truth credited to NoteDao (spec 014 §4 drift guard)', () => {
  assert.match(tools, /source-of-truth[\s\S]{0,80}NoteDao/);
  assert.match(tools, /knowledge_unit/);
});

test('store-not-ready guard before any query (spec 014 §4 prerequisite)', () => {
  assert.match(tools, /store not ready/);
  assert.match(tools, /DatabaseHelper\.getStore\(\)/);
});

test('note_query: LIMIT 20 + keyword covers title and content + status validation via ReviewStatus enum', () => {
  assert.match(tools, /MAX_QUERY_RESULTS: number = 20/);
  assert.match(tools, /limitAs\(MAX_QUERY_RESULTS\)/);
  assert.match(tools, /contains\('title', kw\)/);
  assert.match(tools, /contains\('content', kw\)/);
  assert.match(tools, /review_status must be one of: /);
  assert.match(tools, /ReviewStatus\.NEW/);
  assert.match(tools, /ReviewStatus\.LAPSED/);
});

test('review_due_query aggregates by review_status via GROUP BY', () => {
  assert.match(tools, /GROUP BY review_status/);
  assert.match(tools, /querySql/);
});

test('common Index exports the P1 tool factory and classes', () => {
  assert.match(commonIndex, /createReadOnlyNoteTools/);
  assert.match(commonIndex, /NoteQueryTool/);
  assert.match(commonIndex, /NoteGetTool/);
  assert.match(commonIndex, /ReviewDueQueryTool/);
});
