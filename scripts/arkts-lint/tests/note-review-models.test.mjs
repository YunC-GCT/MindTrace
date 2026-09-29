import test from 'node:test';
import assert from 'node:assert/strict';

import {
  chatModelsDependencyMocks,
  loadNoteReviewEtsModule,
} from './note-review-ets-loader.mjs';

function citation(overrides = {}) {
  return {
    noteId: overrides.noteId ?? 'note-limit',
    version: overrides.version ?? 3,
    title: overrides.title ?? '极限定义',
    excerpt: overrides.excerpt ?? '数列极限用 epsilon-N 语言描述。',
    role: overrides.role ?? 'hit',
    score: overrides.score ?? 0.91,
    matchedFields: overrides.matchedFields ?? ['title', 'content'],
    subject: overrides.subject ?? '数学分析',
    chapter: overrides.chapter ?? '极限与连续',
  };
}

function review(overrides = {}) {
  return {
    intent: overrides.intent ?? 'explain',
    query: overrides.query ?? '根据我的笔记解释极限',
    status: overrides.status ?? 'grounded',
    reason: overrides.reason ?? 'matched note evidence',
    citations: overrides.citations ?? [citation()],
    createdAt: overrides.createdAt ?? 1790400000000,
    feedback: overrides.feedback,
  };
}

function chatMessage(overrides = {}) {
  return {
    id: overrides.id ?? 101,
    role: overrides.role ?? 'ai',
    content: overrides.content ?? '极限描述的是趋近过程。',
    ts: overrides.ts ?? 1790400000001,
    streaming: overrides.streaming ?? false,
    reasoning: overrides.reasoning ?? '检索极限笔记',
    noteReview: overrides.noteReview ?? review({ feedback: 'helpful' }),
  };
}

function assertJsonEqual(actual, expected) {
  assert.equal(JSON.stringify(actual), JSON.stringify(expected));
}

test('NoteReviewModels copies answer citations and feedback without shared mutable state', async () => {
  const { copyNoteReviewAnswer } = loadNoteReviewEtsModule(
    'entry/src/main/ets/models/NoteReviewModels.ets',
  );
  const original = review({ feedback: 'citation-incorrect' });

  const copied = copyNoteReviewAnswer(original);
  assertJsonEqual(copied, original);
  assert.notEqual(copied, original);
  assert.notEqual(copied.citations, original.citations);
  assert.notEqual(copied.citations[0], original.citations[0]);
  assert.notEqual(copied.citations[0].matchedFields, original.citations[0].matchedFields);

  copied.feedback = 'helpful';
  copied.citations[0].version = 4;
  copied.citations[0].matchedFields.push('summary');

  assert.equal(original.feedback, 'citation-incorrect');
  assert.equal(original.citations[0].version, 3);
  assertJsonEqual(original.citations[0].matchedFields, ['title', 'content']);
});

test('ChatModels keeps noteReview metadata in memory and persistence snapshots', async () => {
  const {
    copyChatMsgForMemory,
    copyChatMsgForPersistence,
    copyChatSessionsForMemory,
    copyChatSessionsForPersistence,
  } = loadNoteReviewEtsModule(
    'entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatModels.ets',
    { mocks: chatModelsDependencyMocks },
  );
  const message = chatMessage();
  const session = { id: 's-note-review', name: '复习', messages: [message] };

  const memoryMessage = copyChatMsgForMemory(message);
  const persistedMessage = copyChatMsgForPersistence(message);
  const memorySessions = copyChatSessionsForMemory([session]);
  const persistedSessions = copyChatSessionsForPersistence([session]);

  assertJsonEqual(memoryMessage.noteReview, message.noteReview);
  assertJsonEqual(persistedMessage.noteReview, message.noteReview);
  assertJsonEqual(memorySessions[0].messages[0].noteReview, message.noteReview);
  assertJsonEqual(persistedSessions[0].messages[0].noteReview, message.noteReview);

  assert.notEqual(memoryMessage.noteReview, message.noteReview);
  assert.notEqual(persistedMessage.noteReview, message.noteReview);
  memoryMessage.noteReview.feedback = 'unhelpful';
  memoryMessage.noteReview.citations[0].matchedFields.push('summary');

  assert.equal(message.noteReview.feedback, 'helpful');
  assertJsonEqual(message.noteReview.citations[0].matchedFields, ['title', 'content']);
});

test('ChatModels preserves noteReview while streaming, replacing, and finishing an answer', async () => {
  const {
    applyStreamEventToChatMsg,
    finishChatMsg,
    replaceChatMsgContent,
  } = loadNoteReviewEtsModule(
    'entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatModels.ets',
    { mocks: chatModelsDependencyMocks },
  );
  const message = chatMessage({ content: '', streaming: true });

  const streamed = applyStreamEventToChatMsg(message, { type: 'text', delta: '第一句' });
  const replaced = replaceChatMsgContent(streamed, '完整回答');
  const finished = finishChatMsg(replaced);

  assert.equal(streamed.content, '第一句');
  assert.equal(replaced.content, '完整回答');
  assert.equal(finished.streaming, false);
  assertJsonEqual(streamed.noteReview, message.noteReview);
  assertJsonEqual(replaced.noteReview, message.noteReview);
  assertJsonEqual(finished.noteReview, message.noteReview);

  finished.noteReview.feedback = 'citation-incorrect';
  assert.equal(message.noteReview.feedback, 'helpful');
});

test('ChatModels makes feedback selection idempotent and lets a later choice replace it', async () => {
  const {
    setChatMsgNoteReviewFeedback,
    setChatMsgNoteReviewFeedbackValue,
  } = loadNoteReviewEtsModule(
    'entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatModels.ets',
    { mocks: chatModelsDependencyMocks },
  );
  const message = chatMessage();

  const first = setChatMsgNoteReviewFeedback(message, 'helpful');
  const repeated = setChatMsgNoteReviewFeedback(first, 'helpful');
  const changed = setChatMsgNoteReviewFeedback(repeated, 'unhelpful');
  const cleared = setChatMsgNoteReviewFeedbackValue(changed, undefined);

  assert.equal(first.noteReview.feedback, 'helpful');
  assert.equal(repeated.noteReview.feedback, 'helpful');
  assert.equal(changed.noteReview.feedback, 'unhelpful');
  assert.equal(cleared.noteReview.feedback, undefined);
  assert.equal(message.noteReview.feedback, 'helpful');
});

test('ChatModels drops malformed optional review metadata while preserving valid session isolation', async () => {
  const {
    copyChatMsgForMemory,
    copyChatSessionForMemory,
    sanitizeNoteReviewAnswer,
  } = loadNoteReviewEtsModule(
    'entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatModels.ets',
    { mocks: chatModelsDependencyMocks },
  );
  const malformed = chatMessage({
    noteReview: {
      intent: 'explain',
      query: '极限',
      status: 'grounded',
      reason: 'bad citation',
      citations: [{ noteId: 'note-limit', version: '3' }],
      createdAt: 1,
      feedback: 'unknown',
    },
  });
  const valid = chatMessage({ id: 102 });

  assert.equal(sanitizeNoteReviewAnswer(malformed.noteReview), undefined);
  assert.equal(copyChatMsgForMemory(malformed).noteReview, undefined);

  const session = {
    id: 'session-a',
    name: '复习',
    messages: [valid],
  };
  const copied = copyChatSessionForMemory(session);
  copied.messages[0].noteReview.feedback = 'citation-incorrect';
  copied.messages[0].noteReview.citations[0].excerpt = '已修改副本';

  assert.equal(session.messages[0].noteReview.feedback, 'helpful');
  assert.equal(session.messages[0].noteReview.citations[0].excerpt, '数列极限用 epsilon-N 语言描述。');
});
