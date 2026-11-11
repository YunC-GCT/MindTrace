// 路径: scripts/arkts-lint/tests/a2a-draft-checkpoint.test.mjs
// 职责: A2A 草稿确认契约——命令解析、预览内容、对象型 section 内容、控制器接线。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

const draftModels = loadNoteReviewEtsModule('entry/src/main/ets/services/A2ADraftModels.ets');
const draftSupport = loadNoteReviewEtsModule('agents/src/main/ets/subagents/GenerationDraftSupport.ets', {
  mocks: {
    'common/src/main/ets/Index': {
      LlmConfig: {
        getInstance() {
          return { supportsStrictStructuredOutput() { return false; } };
        },
      },
      NOTE_DRAFT_JSON_SCHEMA: '{}',
    },
  },
});

function fakeEvent(content) {
  return {
    candidate: {
      title: '柯西中值定理',
      subject: '数学分析',
      category: '定理',
      summary: '柯西中值定理的条件与结论',
      content: content ?? '## 核心内容\n需要两个函数在闭区间连续、开区间可导。\n\n## 补充内容2\n它是拉格朗日中值定理的推广。\n\n## 原文\n原题文字',
    },
  };
}

test('确认/取消命令只认短命令，不把提问误判为确认', () => {
  assert.equal(draftModels.parseA2ADraftCommand('确认'), 'confirm');
  assert.equal(draftModels.parseA2ADraftCommand('保存吧'), 'confirm');
  assert.equal(draftModels.parseA2ADraftCommand('确认保存'), 'confirm');
  assert.equal(draftModels.parseA2ADraftCommand('取消'), 'cancel');
  assert.equal(draftModels.parseA2ADraftCommand('取消吧'), 'cancel');
  assert.equal(draftModels.parseA2ADraftCommand('保存到哪里'), 'none');
  assert.equal(draftModels.parseA2ADraftCommand('怎么证明这个定理'), 'none');
});

test('草稿回复先输出关键内容，最后再问是否整理保存', () => {
  const preview = draftModels.formatA2ADraftReply(fakeEvent());
  assert.match(preview, /「柯西中值定理」（数学分析 · 定理）/);
  assert.match(preview, /需要两个函数在闭区间连续/);
  assert.match(preview, /它是拉格朗日中值定理的推广/);
  assert.match(preview, /要我把这些内容整理成笔记保存吗/);
  assert.match(preview, /回复「确认」保存，或「取消」不用/);
  assert.equal(preview.includes('[object Object]'), false);
  assert.equal(preview.includes('\\'), false);
});

test('长回复分块：拼接等于原文，块数/块长受限', () => {
  const text = '第一段内容。第二段内容！第三段内容？第四段内容；第五段内容。';
  const chunks = draftModels.splitReplyText(text, 40, 8);
  assert.equal(chunks.join(''), text);
  assert.ok(chunks.length <= 8);
  assert.ok(chunks.every((chunk) => chunk.length <= 40));
});

test('草稿二次操作：详细 / 简洁 / 重新生成命令', () => {
  assert.equal(draftModels.parseA2ADraftRefine('详细一点'), 'more');
  assert.equal(draftModels.parseA2ADraftRefine('展开讲讲'), 'more');
  assert.equal(draftModels.parseA2ADraftRefine('简洁一点'), 'less');
  assert.equal(draftModels.parseA2ADraftRefine('重新生成'), 'regenerate');
  assert.equal(draftModels.parseA2ADraftRefine('这题怎么证明'), 'none');
  const handler = read('entry/src/main/ets/services/A2AIngestHandler.ets');
  assert.match(handler, /refinePendingDraft\(/);
  assert.match(handler, /整理得更详细/);
  assert.match(handler, /整理得更简洁/);
  assert.match(handler, /draftWithDeadline\(runId, sourceText, \[\], token, instruction, mode === 'more'\)/);
  const controller = read('entry/src/main/ets/services/A2AController.ets');
  assert.match(controller, /parseA2ADraftRefine\(text\)/);
  assert.match(controller, /refinePendingDraft\(input\.taskId, conversationKey, pendingDraft, refine\)/);
});

test('超时/失败只回一条：入队回执不再和调用方各发一条', () => {
  const handler = read('entry/src/main/ets/services/A2AIngestHandler.ets');
  assert.match(handler, /const reply: string = e\.message\.indexOf\('A2A_DRAFT_TIMEOUT'\) >= 0/);
  assert.match(handler, /this\.enqueueForIngest\(taskId, request\.text, reply\)/);
  assert.match(handler, /private enqueueForIngest\(taskId: string, query: string, replyText\?: string\): void/);
  assert.doesNotMatch(handler, /this\.enqueueForIngest\(taskId, request\.text\);\s*\n\s*this\.host\.sendIngestAnswer/);
  assert.doesNotMatch(handler, /batch\.totalProblems > 1 \? batch\.queuedTexts : \[request\.text\]/);
});

test('对象型 section.content 被抽成字符串，不再生成 [object Object]', () => {
  const document = draftSupport.parseDraftDocument({
    schemaVersion: '1',
    title: { text: '标题' },
    summary: '摘要',
    sections: [
      { id: 's1', label: { text: '陈述' }, content: { text: '第一段内容' } },
      { id: 's2', label: '条件', content: { value: '第二段内容' } },
    ],
  });
  assert.equal(document.title, '标题');
  assert.equal(document.sections[0].label, '陈述');
  assert.equal(document.sections[0].content, '第一段内容');
  assert.equal(document.sections[1].content, '第二段内容');
  assert.equal(document.sections.map((s) => s.content).join(' ').includes('[object Object]'), false);
});

test('控制器与处理器接线：单题先草稿，确认才入库，取消丢弃', () => {
  const controller = read('entry/src/main/ets/services/A2AController.ets');
  assert.match(controller, /A2ADraftStore\.load\(this\.context, conversationKey\)/);
  assert.match(controller, /parseA2ADraftCommand\(text\)/);
  assert.match(controller, /confirmPendingDraft\(input\.taskId, conversationKey, pendingDraft\)/);
  assert.match(controller, /cancelPendingDraft\(input\.taskId, conversationKey, pendingDraft\)/);
  assert.match(controller, /beginDraftCheckpoint\(input\.taskId, conversationKey, ingest\)/);
  const handler = read('entry/src/main/ets/services/A2AIngestHandler.ets');
  assert.match(handler, /this\.host\.sendIngestAnswer\(taskId, formatA2ADraftReply\(event\), 0\)/);
  assert.match(controller, /sendStreamingAnswer\(taskId: string, text: string\): void/);
  assert.match(controller, /text\.length > 70/);
  assert.match(controller, /splitReplyText\(text\)/);
  assert.match(controller, /this\.reply\.streamChunk\(finalTaskId, chunks\[index\], index > 0, lastChunk\)/);
  assert.match(handler, /generateNoteDraftWithSources\(/);
  assert.match(handler, /'light'\)/);
  assert.match(handler, /'standard'\)/);
  assert.match(handler, /A2A_DRAFT light-empty retry=standard/);
  assert.match(handler, /draftUseful\(/);
  assert.match(handler, /cleanDraftSource\(/);
  assert.match(handler, /A2AConversationStore\.load\(this\.host\.ingestContext\(\), conversationKey\)/);
  assert.match(handler, /historySources\(/);
  assert.match(handler, /sourceFingerprint/);
  assert.match(handler, /generateNoteDraftWithSources\(/);
  assert.match(handler, /service\.confirmDraft\(draft\.event, draft\.event\.candidate\)/);
  assert.match(handler, /A2ADraftStore\.clear\(this\.host\.ingestContext\(\), conversationKey\)/);
  const store = read('entry/src/main/ets/services/A2ADraftStore.ets');
  assert.match(store, /DRAFT_FILE_PREFIX: string = 'draft-'/);
  assert.match(store, /DRAFT_MAX_AGE_MS/);
  assert.match(store, /conversationKey !== 'default'/);
  assert.match(store, /parsed\.conversationKey = conversationKey/);
});
