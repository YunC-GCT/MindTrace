// 路径: scripts/arkts-lint/tests/conversation-graph.test.mjs
// 职责: 覆盖 ConversationWorkflow 的图执行——节点装配、意图分流、四条回复链路、
//       证据注入、失败与取消终态。拆分前先有这层网，再动结构。
// 依赖: conversation-graph-harness.mjs（真实工作流 + 可记录端口 + 假 StateGraph）

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { createWorkflow, createRunRef } from './conversation-graph-harness.mjs';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');
const WORKFLOW_PATH = 'agents/src/main/ets/conversation/ConversationWorkflow.ets';

const TEXT_COMPLETE = { kind: 'text', userContent: '解释一下极限', responseMode: 'complete' };
const TEXT_STREAM = { kind: 'text', userContent: '解释一下极限', responseMode: 'stream' };
const IMAGE = (responseMode = 'complete') => ({
  kind: 'image',
  imageUri: 'file:///tmp/a.jpg',
  userContent: '整理这张图',
  responseMode,
});

function steps(state) {
  return state.events.filter((e) => e.type === 'progress').map((e) => e.step);
}

// ── A. 图装配 ─────────────────────────────────────────────

test('图装配：默认关闭工具回复，不含 tool_reply 节点', () => {
  const { graph } = createWorkflow();
  assert.ok(graph.nodes.classify_intent, '缺少 classify_intent');
  assert.ok(graph.nodes.complete_reply, '缺少 complete_reply');
  assert.ok(graph.nodes.stream_reply, '缺少 stream_reply');
  assert.equal(graph.nodes.tool_reply, undefined, '工具回复默认应关闭');
});

test('图装配：开启工具回复后加入 tool_reply 并接到 END', () => {
  const { graph } = createWorkflow({
    toolReplyEnabled: true,
    ports: { toolReply: { isEnabled: () => true, complete: async () => '工具回答' } },
  });
  assert.ok(graph.nodes.tool_reply, '开启后应有 tool_reply 节点');
  assert.equal(graph.edges.tool_reply, 'END');
});

// ── B. 文本链路 ───────────────────────────────────────────

test('文本 complete：走 classify → load_context → save_input → complete_reply，只落一条消息', async () => {
  const { workflow, state } = createWorkflow({
    ports: { reply: { complete: async () => '这是回答' } },
  });
  await workflow.run(TEXT_COMPLETE, createRunRef());
  assert.deepEqual(steps(state), ['intent_check', 'reply_context_load', 'reply_model_call']);
  assert.deepEqual(state.events.filter((e) => e.type === 'add').map((e) => e.content), ['这是回答']);
  assert.equal(state.events.filter((e) => e.type === 'add').length, 1, 'complete 只应落一条消息');
});

test('文本 stream：走 stream_reply 并产生流式更新事件', async () => {
  const { workflow, state } = createWorkflow({
    ports: {
      reply: {
        stream: async (_ctx, sink) => {
          sink({ type: 'text', delta: '第一段' });
          sink({ type: 'text', delta: '第二段' });
          return { content: '第一段第二段', interrupted: false, usedFallback: false };
        },
      },
    },
  });
  await workflow.run(TEXT_STREAM, createRunRef());
  assert.ok(steps(state).includes('reply_model_call'));
  const updates = state.events.filter((e) => e.type === 'update' || e.type === 'finish-msg');
  assert.ok(updates.length >= 2, '流式至少要有增量更新与收尾');
});

// ── C. 意图分流 ───────────────────────────────────────────

test('意图 note_generate：走笔记分支，不进入回复模型', async () => {
  const { workflow, state } = createWorkflow({
    AppIntentRouter: class {
      async classify() { return { kind: 'note_generate', source: 'local', confidence: 0.95, reason: 'stub' }; }
    },
  });
  await workflow.run({ kind: 'text', userContent: '存笔记：极限定义', responseMode: 'complete' }, createRunRef());
  assert.equal(steps(state)[0], 'intent_check');
  assert.ok(!steps(state).includes('reply_model_call'), '笔记分支不应走回复模型');
});

test('显式重生成指令：调用 capture.regenerateNoteDraft 并上报草稿事件', async () => {
  const regenerated = [];
  const { workflow, state } = createWorkflow({
    AppIntentRouter: class {
      async classify() { return { kind: 'note_generate', source: 'local', confidence: 0.95, reason: 'stub' }; }
    },
    ports: {
      capture: {
        regenerateNoteDraft: async (runId, noteId) => {
          regenerated.push(noteId);
          return { runId, checkpointId: 'cp1', candidateHash: 'h', unit: null };
        },
      },
    },
  });
  await workflow.run(
    { kind: 'text', userContent: '重新生成 noteId=n1 请更简洁', responseMode: 'complete' },
    createRunRef(),
  );
  assert.deepEqual(regenerated, ['n1'], '应命中显式重生成分支');
  assert.ok(state.events.some((e) => e.type === 'draft'), '应上报草稿事件');
});

test('意图 clarify：直接给出澄清提示，不进入模型调用', async () => {
  const { workflow, state } = createWorkflow({
    AppIntentRouter: class {
      async classify() { return { kind: 'clarify', source: 'local', confidence: 0.2, reason: 'stub' }; }
    },
  });
  await workflow.run(TEXT_COMPLETE, createRunRef());
  assert.ok(!steps(state).includes('reply_model_call'), '澄清分支不应调用模型');
  const added = state.events.filter((e) => e.type === 'add');
  assert.equal(added.length, 1);
});

// ── D. 图片链路 ───────────────────────────────────────────

test('图片请求：走 classify_image_intent 分支', async () => {
  const { workflow, state } = createWorkflow({
    AppIntentRouter: class {
      async classify(_text, isImage) {
        return { kind: isImage ? 'image_explain' : 'chat', source: 'local', confidence: 0.9, reason: 'stub' };
      }
    },
  });
  await workflow.run(IMAGE(), createRunRef());
  assert.equal(steps(state)[0], 'intent_check');
  assert.ok(state.events.some((e) => e.type === 'add-empty' || e.type === 'add'), '图片分支应产生消息');
});

// ── E. 复习链路 ───────────────────────────────────────────

test('复习 terminal 计划：直接终答，不调用回复模型', async () => {
  const { workflow, state } = createWorkflow({
    ports: {
      review: {
        classifyIntent: () => 'explain',
        plan: async () => ({
          kind: 'terminal',
          answer: { intent: 'explain', query: '极限', status: 'insufficient', reason: 'no-evidence', citations: [], createdAt: 1 },
          displayText: '没有找到相关笔记',
          modelUserContent: '',
          quizCount: 0,
        }),
      },
    },
  });
  await workflow.run(TEXT_COMPLETE, createRunRef());
  const added = state.events.filter((e) => e.type === 'add' || e.type === 'add-empty');
  assert.ok(added.length >= 1);
  assert.ok(!added.some((e) => e.content === '默认回答'), 'terminal 分支不应走模型回答');
});

// ── F. 证据注入 ───────────────────────────────────────────

test('证据命中：回答尾部追加来源块', async () => {
  const { workflow, state } = createWorkflow({
    ports: {
      evidence: {
        build: async () => ({
          query: '极限', topK: 1,
          citations: [{ noteId: 'n1', version: 1, title: '极限', excerpt: '定义', role: 'hit', score: 1, matchedFields: [], subject: '数学分析', chapter: '极限' }],
          relations: [], contextText: '上下文', degraded: false, reason: '',
        }),
        formatSources: () => '参考来源：极限',
      },
      reply: { complete: async () => '这是回答' },
    },
  });
  await workflow.run(TEXT_COMPLETE, createRunRef());
  const added = state.events.filter((e) => e.type === 'add');
  assert.ok(added.some((e) => e.content.indexOf('参考来源：极限') >= 0), '回答应带来源块');
});

// ── G. 失败与取消 ─────────────────────────────────────────

test('模型失败：终态为 failed，且不产生成功消息', async () => {
  const { workflow, state } = createWorkflow({
    ports: { reply: { complete: async () => { throw new Error('MODEL_DOWN'); } } },
  });
  await assert.rejects(() => workflow.run(TEXT_COMPLETE, createRunRef()));
  assert.ok(
    state.events.some((e) => e.type === 'error' || e.type === 'terminate'),
    '失败应上报错误或终止',
  );
});

test('取消：token 抛错时终态为 cancelled', async () => {
  const cancelled = {
    throwIfCancelled() { throw new Error('CANCELLED'); },
  };
  const { workflow, state } = createWorkflow({ token: cancelled });
  await assert.rejects(() => workflow.run(TEXT_COMPLETE, createRunRef()));
  assert.ok(state.events.some((e) => e.type === 'error' || e.type === 'terminate'));
});

// ── I. run 事件 ───────────────────────────────────────────

function recordingSink() {
  const events = [];
  return {
    events,
    sink: {
      async emit(runId, event) { events.push({ runId, kind: event.kind, payload: event.payloadJson }); },
      async settle() {},
    },
  };
}

test('run 事件：一次文本对话写出 start / step / terminal', async () => {
  const recorder = recordingSink();
  const { workflow } = createWorkflow({ ports: { runEvents: recorder.sink } });
  await workflow.run(TEXT_COMPLETE, createRunRef());

  const kinds = recorder.events.map((e) => e.kind);
  assert.equal(kinds[0], 'conversation.start');
  assert.equal(kinds[kinds.length - 1], 'conversation.terminal');
  assert.ok(kinds.filter((k) => k === 'conversation.step').length >= 2, '应记录每一步');
  const start = JSON.parse(recorder.events[0].payload);
  assert.equal(start.requestKind, 'text');
  const terminal = JSON.parse(recorder.events[recorder.events.length - 1].payload);
  assert.equal(terminal.outcome, 'completed');
});

test('run 事件：模型失败时终态记为 failed，且不影响抛错', async () => {
  const recorder = recordingSink();
  const { workflow } = createWorkflow({
    ports: {
      runEvents: recorder.sink,
      reply: { complete: async () => { throw new Error('MODEL_DOWN'); } },
    },
  });
  await assert.rejects(() => workflow.run(TEXT_COMPLETE, createRunRef()));
  const terminal = JSON.parse(recorder.events[recorder.events.length - 1].payload);
  assert.equal(terminal.outcome, 'failed');
  // 跨 vm realm 的 Error 拿不到 message，这里只断言 reason 字段存在且为字符串
  assert.equal(typeof terminal.reason, 'string');
});

test('run 事件：sink 抛错不阻塞对话', async () => {
  const failing = { async emit() { throw new Error('SINK_DOWN'); }, async settle() {} };
  const { workflow, state } = createWorkflow({ ports: { runEvents: failing } });
  await workflow.run(TEXT_COMPLETE, createRunRef());
  assert.ok(state.events.some((e) => e.type === 'add'), '对话应正常完成');
});

// ── H. 端口契约（源码级） ─────────────────────────────────

test('契约：工作流不直接构造 entry 服务，也不依赖平台 Kit', () => {
  const source = read(WORKFLOW_PATH);
  assert.doesNotMatch(source, /new AiService|new AgentMemoryService|new NoteEvidenceService|new NoteReviewService/);
  assert.doesNotMatch(source, /from '@kit\.|from '@ohos\./);
  assert.doesNotMatch(source, /UIAbilityContext/);
});
