// 路径: scripts/arkts-lint/tests/v7-legacy-cleanup.test.mjs
// 职责: 历史数据清理契约——旧学科推断（别名/关键词/兜底）与「完全重复」分组（只删完全一致）。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');
const taxonomy = loadNoteReviewEtsModule('agents/src/main/ets/agents/KnowledgeTaxonomy.ets');
const mod = loadNoteReviewEtsModule('agents/src/main/ets/note/LegacyNoteNormalizer.ets', {
  mocks: { agents: taxonomy },
});
const normalizer = mod;
const arr = (value) => Array.from(value);

const input = (subject, title, content) => ({
  id: 'x',
  subject,
  chapter: '',
  title,
  contentExcerpt: content,
});

test('历史学科推断：数学 + 初中题面 → 初中数学', () => {
  assert.equal(normalizer.normalizeLegacySubject(input('数学', '解一元二次方程 x^2-5x+6=0', '因式分解')), '初中数学');
  assert.equal(normalizer.normalizeLegacySubject(input('数学', '求根号7的近似值', '保留两位小数')), '初中数学');
});

test('历史学科推断：数学 + 微积分/线代/概率关键词', () => {
  assert.equal(normalizer.normalizeLegacySubject(input('数学', '用洛必达法则求极限', '0/0 型')), '高等数学');
  assert.equal(normalizer.normalizeLegacySubject(input('数学', '矩阵的秩与行列式', '高斯消元')), '线性代数');
  assert.equal(normalizer.normalizeLegacySubject(input('数学', '随机变量的期望与方差', '正态分布')), '概率论');
});

test('历史学科推断：别名优先、无法判断→其他、已是标准→不改', () => {
  assert.equal(normalizer.normalizeLegacySubject(input('微积分', '连续函数的性质', '')), '高等数学');
  assert.equal(normalizer.normalizeLegacySubject(input('数学', '随便聊聊', '你好')), '其他');
  assert.equal(normalizer.normalizeLegacySubject(input('高等数学', '极限', '')), '');
  assert.equal(normalizer.normalizeLegacySubject(input('初中数学', '方程', '')), '');
});

test('完全重复分组：同标题同正文只保留最早一条', () => {
  const entries = [
    { id: 'a', titleKey: '解一元二次方程', contentKey: '## 问题\n求根', createdAt: 100 },
    { id: 'b', titleKey: '解一元二次方程', contentKey: '## 问题\n求根', createdAt: 200 },
    { id: 'c', titleKey: '解一元二次方程', contentKey: '## 问题\n求根', createdAt: 50 },
    { id: 'd', titleKey: '解一元二次方程', contentKey: '## 问题\n不同内容', createdAt: 300 },
  ];
  const groups = arr(normalizer.groupExactDuplicates(entries));
  assert.equal(groups.length, 1);
  assert.equal(groups[0].keepId, 'c');
  assert.deepEqual(arr(groups[0].removeIds).sort(), ['a', 'b']);
});

test('清理接线：审计/应用两个 e2e，应用时才 UPDATE/DELETE', () => {
  const runner = read('entry/src/main/ets/services/DebugCaptureRunner.ets');
  assert.ok(runner.includes('static async runLegacyCleanup(ctx: common.UIAbilityContext, apply: boolean)'));
  assert.ok(runner.includes('UPDATE knowledge_unit SET subject = ?, updated_at = ? WHERE id = ?'));
  assert.ok(runner.includes('dao.deleteById(group.removeIds[k])'));
  const entry = read('entry/src/main/ets/entryability/EntryAbility.ets');
  assert.match(entry, /mode === 'legacyCleanupAudit'/);
  assert.match(entry, /mode === 'legacyCleanupApply'/);
});
