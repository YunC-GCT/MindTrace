// ADR-0022 / schema v15：复习独立表的源码级契约测试。
// 只读 DatabaseHelper 源码，防止迁移丢表 / 丢索引 / 误改 study_plan 语义。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');

const db = read('common/src/main/ets/DatabaseHelper.ets');
const adr = read('docs/adr/0022-review-and-video-scope.md');

const reviewItemBlock = db.match(/const SQL_CREATE_REVIEW_ITEM[\s\S]*?\)`;/);
const reviewLogBlock = db.match(/const SQL_CREATE_REVIEW_LOG[\s\S]*?\)`;/);
const studyPlanBlock = db.match(/const SQL_CREATE_STUDY_PLAN[\s\S]*?\)`;/);

test('schema version is bumped to 15 by ADR-0022', () => {
  assert.match(db, /const DB_SCHEMA_VERSION: number = 15;/);
});

test('review_item table carries the SM-2 fields', () => {
  assert.ok(reviewItemBlock !== null, 'SQL_CREATE_REVIEW_ITEM missing');
  const block = reviewItemBlock[0];
  for (const column of ['id TEXT PRIMARY KEY', 'unit_id TEXT NOT NULL', 'status TEXT NOT NULL',
    'next_review_at INTEGER', 'interval_days INTEGER', 'ease_factor REAL', 'repetitions INTEGER',
    'lapses INTEGER', 'last_reviewed_at INTEGER', 'created_at INTEGER', 'updated_at INTEGER']) {
    assert.ok(block.includes(column), 'review_item missing column: ' + column);
  }
});

test('review_log table records grade, correctness and interval transition', () => {
  assert.ok(reviewLogBlock !== null, 'SQL_CREATE_REVIEW_LOG missing');
  const block = reviewLogBlock[0];
  for (const column of ['review_item_id TEXT NOT NULL', 'unit_id TEXT NOT NULL', 'reviewed_at INTEGER',
    'grade TEXT NOT NULL', 'correct INTEGER NOT NULL', 'duration_ms INTEGER',
    'interval_before INTEGER', 'interval_after INTEGER']) {
    assert.ok(block.includes(column), 'review_log missing column: ' + column);
  }
});

test('both tables and their indexes are wired into the creation statement list', () => {
  assert.match(db, /SQL_CREATE_REVIEW_ITEM,/);
  assert.match(db, /SQL_CREATE_REVIEW_LOG,/);
  assert.match(db, /SQL_INDEX_REVIEW_ITEM_DUE,/);
  assert.match(db, /SQL_INDEX_REVIEW_ITEM_UNIT,/);
  assert.match(db, /SQL_INDEX_REVIEW_LOG_ITEM,/);
  assert.match(db, /idx_review_item_due ON review_item\(next_review_at\)/);
  assert.match(db, /idx_review_log_item ON review_log\(review_item_id\)/);
});

test('study_plan keeps the todo semantics: no review fields were added to it', () => {
  assert.ok(studyPlanBlock !== null, 'SQL_CREATE_STUDY_PLAN missing');
  const block = studyPlanBlock[0];
  for (const forbidden of ['ease_factor', 'next_review_at', 'repetitions', 'review_item_id']) {
    assert.ok(!block.includes(forbidden), 'study_plan must not gain review field: ' + forbidden);
  }
});

test('ADR-0022 records both #242 decisions and is registered in the ADR index', () => {
  assert.ok(existsSync(resolve(root, 'docs/adr/0022-review-and-video-scope.md')));
  assert.match(adr, /只产脚本/);
  assert.match(adr, /review_item/);
  assert.match(adr, /review_log/);
  const index = read('docs/adr/index.md');
  assert.match(index, /0022-review-and-video-scope\.md/);
});
