// 路径: scripts/arkts-lint/tests/seed-cleanup.test.mjs
// 职责: 测试语料清理只按 seed 标记删除，不能退化成清空全库。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

test('种子清理只匹配 seed-math/bulk/file_import，不按全表删除', () => {
  const runner = read('entry/src/main/ets/debug/DebugCaptureRunner.ets');
  const start = runner.indexOf('static async runClearSeedCorpus(');
  const end = runner.indexOf('static async runRagSearch(', start);
  assert.notEqual(start, -1);
  assert.notEqual(end, -1);
  const body = runner.slice(start, end);
  assert.match(body, /source = 'file_import'/);
  assert.match(body, /id LIKE 'seed-%'/);
  assert.match(body, /id LIKE 'bulk-%'/);
  assert.doesNotMatch(body, /DELETE FROM knowledge_unit/);
  assert.match(body, /removeSeedDerivedRows/);
  assert.match(body, /NoteVectorIndex\.invalidate\(\)/);

  const derived = runner.match(/private static async removeSeedDerivedRows[\s\S]*?\n  \}/);
  assert.ok(derived !== null);
  assert.match(derived[0], /DELETE FROM rag_chunk WHERE unit_id = \?/);
  assert.match(derived[0], /DELETE FROM note_revision WHERE note_id = \?/);
  assert.match(derived[0], /DELETE FROM review_item WHERE unit_id = \?/);

  const ability = read('entry/src/main/ets/entryability/EntryAbility.ets');
  assert.match(ability, /mode === 'clearSeedCorpusAudit'/);
  assert.match(ability, /mode === 'clearSeedCorpus'/);
  assert.match(ability, /runClearSeedCorpus\(this\.context, false\)/);
  assert.match(ability, /runClearSeedCorpus\(this\.context, true\)/);
});
