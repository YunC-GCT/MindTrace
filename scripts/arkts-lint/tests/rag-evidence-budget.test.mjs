// 路径: scripts/arkts-lint/tests/rag-evidence-budget.test.mjs
// 职责: 044 R4 契约——证据字符预算：超出预算时从尾部裁剪，citations 与 contextText 保持对齐。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const mod = loadNoteReviewEtsModule('agents/src/main/ets/evidence/NoteEvidenceService.ets');
const { NoteEvidenceService } = mod;

function citation(index, excerptLength) {
  return {
    noteId: 'n' + index,
    version: 1,
    title: '笔记' + index,
    excerpt: '内'.repeat(excerptLength),
    role: 'hit',
    score: 10 - index,
    matchedFields: ['content'],
    subject: '数学',
    chapter: '',
  };
}

function buildService(count, excerptLength) {
  const citations = [];
  for (let i = 0; i < count; i += 1) {
    citations.push(citation(i, excerptLength));
  }
  const search = {
    search: async () => citations,
  };
  const graph = {
    expandAcceptedNeighborhood: async () => ({ nodes: [], edges: [] }),
    expandAcceptedPrerequisites: async () => ({ nodes: [], edges: [] }),
  };
  return new NoteEvidenceService(search, graph);
}

test('超出字符预算时从尾部裁剪并标记 budget-truncated', async () => {
  const service = buildService(5, 200);
  const context = await service.build('连续性', { topK: 5, maxContextChars: 400, graphMode: 'none' });
  assert.ok(context.citations.length < 5, '应裁掉部分引用');
  assert.ok(context.contextText.length <= 400, '注入文本不超过预算');
  assert.equal(context.reason, 'budget-truncated');
});

test('不传预算时保留全部命中', async () => {
  const service = buildService(3, 50);
  const context = await service.build('连续性', { topK: 5, graphMode: 'none' });
  assert.equal(context.citations.length, 3);
  assert.equal(context.reason, '');
});

test('contextText 里的 noteId 与 citations 一一对齐', async () => {
  const service = buildService(4, 120);
  const context = await service.build('连续性', { topK: 4, maxContextChars: 600, graphMode: 'none' });
  for (const item of context.citations) {
    assert.ok(context.contextText.includes('[noteId=' + item.noteId), 'citation 出现在上下文里');
  }
  const ids = Array.from(context.contextText.matchAll(/\[noteId=([^\s\]]+)/g))
    .map((m) => m[1])
    .filter((id) => id !== '...');
  for (const id of ids) {
    assert.ok(context.citations.some((c) => c.noteId === id), '上下文里的引用都能在 citations 找到');
  }
});
