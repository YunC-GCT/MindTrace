// 路径: scripts/arkts-lint/tests/conversation-formatting.test.mjs
// 职责: 对话来源块展示——隐藏内部 noteId/version，保留角色与标题。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const mod = loadNoteReviewEtsModule('agents/src/main/ets/conversation/ConversationFormatting.ets');
const citation = loadNoteReviewEtsModule('common/src/main/ets/utils/CitationText.ets');
const { evidenceFooter } = mod;
const { stripCitationMarkers } = citation;

test('来源块隐藏 noteId/version 标记', () => {
  const raw = '参考来源：\n- [关键词命中] [noteId=galaxy_preview_derivative_definition version=1] 《导数定义与几何意义》：导数是差商极限。';
  const cleaned = stripCitationMarkers(raw);
  assert.equal(cleaned.includes('noteId='), false);
  assert.ok(cleaned.includes('[关键词命中] 《导数定义与几何意义》'));
});

test('无标记文本保持原样', () => {
  assert.equal(stripCitationMarkers('笔记检索：未命中已保存笔记。'), '笔记检索：未命中已保存笔记。');
});

test('流式中的半个标记也被隐藏', () => {
  assert.equal(stripCitationMarkers('结论见 [noteId=KB-mvw99'), '结论见 ');
});

test('evidenceFooter 命中时只输出标题索引', () => {
  const fakePort = {
    formatSources: () => '- [关键词命中] [noteId=n1 version=2] 《极限》：内容',
    formatRetrievalStatus: () => '笔记检索：命中 1 条。',
  };
  const evidence = { citations: [{ noteId: 'n1', title: '极限' }], relations: [] };
  assert.equal(evidenceFooter(fakePort, evidence), '参考来源：《极限》');
});

test('evidenceFooter 未命中时保留检索状态', () => {
  const fakePort = {
    formatSources: () => '',
    formatRetrievalStatus: () => '笔记检索：未命中已保存笔记。',
  };
  const evidence = { citations: [], relations: [] };
  assert.equal(evidenceFooter(fakePort, evidence), '笔记检索：未命中已保存笔记。');
});
