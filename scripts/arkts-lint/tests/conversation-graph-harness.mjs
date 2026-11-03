// 路径: scripts/arkts-lint/tests/conversation-graph-harness.mjs
// 职责: 在 Node 里加载真实的 ConversationWorkflow，用可记录端口 + 假 StateGraph 驱动图执行，
//       给「对话图拆分」提供回归网。
// 约束: 只替换平台/服务实现，工作流自身的代码一律用真实文件。

import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

/** 最小 StateGraph：按 addEdge / addConditionalEdge 真实走图，带步数上限防死循环。 */
export class FakeStateGraph {
  constructor(start, end) {
    this.start = start;
    this.end = end;
    this.nodes = {};
    this.edges = {};
    this.conditionals = {};
    this.visited = [];
  }

  addNode(name, handler) { this.nodes[name] = handler; }

  addEdge(from, to) { this.edges[from] = to; }

  addConditionalEdge(from, resolver) { this.conditionals[from] = resolver; }

  next(state, step) {
    if (this.conditionals[step] !== undefined) { return this.conditionals[step](state); }
    return this.edges[step];
  }

  async run(initial) {
    let state = initial;
    let step = this.next(state, this.start);
    let guard = 0;
    while (step !== undefined && step !== this.end) {
      guard += 1;
      if (guard > 50) { throw new Error('GRAPH_STEP_LIMIT'); }
      this.visited.push(step);
      const handler = this.nodes[step];
      if (handler === undefined) { throw new Error('GRAPH_NODE_MISSING:' + step); }
      state = await handler(state);
      step = this.next(state, step);
    }
    return state;
  }
}

const NOOP_LOGGER = class {
  constructor(_tag) {}
  debug() {}
  info() {}
  warn() {}
  error() {}
};

const LLM_ERROR_FORMATTER = {
  redactSensitiveText(text) { return text; },
  format(text) { return text; },
  decodeFull(text) { return text; },
};

/**
 * 加载真实 ConversationWorkflow。
 * @param {object} options.common 覆盖 common 桩（如 StateGraph）
 * @param {object} options.agents 覆盖 agents 桩（如 AppIntentRouter）
 */
export function loadConversationGraph(options = {}) {
  const module = loadNoteReviewEtsModule('agents/src/main/ets/conversation/ConversationWorkflow.ets', {
    mocks: {
      common: {
        StateGraph: options.StateGraph ?? FakeStateGraph,
        Logger: options.Logger ?? NOOP_LOGGER,
        LlmErrorBodyFormatter: LLM_ERROR_FORMATTER,
        LlmError: class LlmError extends Error {},
        ...(options.common ?? {}),
      },
      agents: {
        ...(options.agents ?? {}),
      },
      // 相对导入的模块必须按文件路径打桩才生效
      'agents/src/main/ets/conversation/ConversationToolReplyFlags.ets': options.toolReplyEnabled === true
        ? { ConversationToolReplyFlags: { isEnabled: () => true }, CHAT_TOOL_REPLY_ENABLED: true }
        : { ConversationToolReplyFlags: { isEnabled: () => false }, CHAT_TOOL_REPLY_ENABLED: false },
      'agents/src/main/ets/chat/AppIntentRouter.ets': {
        AppIntentRouter: options.AppIntentRouter ?? class {
          async classify() {
            return { kind: 'chat', source: 'local', confidence: 0.9, reason: 'stub' };
          }
        },
      },
    },
  });
  return module.ConversationWorkflow;
}

/** 记录回调：所有 UI 副作用都落进 events，便于断言顺序。 */
export function createCallbacks(overrides = {}) {
  const events = [];
  const state = {
    events,
    nextMessageId: 1,
    terminalOutcomes: [],
  };
  const callbacks = {
    onStart(ref) { events.push({ type: 'start', runId: ref.runId }); },
    onFinish(ref) { events.push({ type: 'finish', runId: ref.runId }); },
    onProgress(ref, step) { events.push({ type: 'progress', step }); },
    completeProgress(ref) { events.push({ type: 'complete-progress' }); },
    onError(ref, error) { events.push({ type: 'error', message: String(error && error.message ? error.message : error) }); },
    isCurrentRun() { return true; },
    getContext() { return {}; },
    getCancellationToken() { return overrides.token ?? { throwIfCancelled() {} }; },
    registerCancellationHook() { return () => {}; },
    commitHistory() { return Promise.resolve(true); },
    getUserMessageId() { return 1; },
    getConversationText() { return ''; },
    reportDiagnostic(ref, diagnostic) { events.push({ type: 'diagnostic', diagnostic }); },
    addUserMsg() { return 1; },
    addAiMsg(ref, content, origin) {
      const id = state.nextMessageId++;
      events.push({ type: 'add', id, content, origin });
      return id;
    },
    addAiMsgEmpty(ref) {
      const id = state.nextMessageId++;
      events.push({ type: 'add-empty', id });
      return id;
    },
    updateAiMsg(ref, id, event) { events.push({ type: 'update', id, event }); },
    updateRunEvent(ref, event) { events.push({ type: 'run-event', event }); },
    finishAiMsg(ref, id, outcome) {
      state.terminalOutcomes.push(outcome);
      events.push({ type: 'finish-msg', id, outcome });
    },
    terminateAiRun(ref, outcome) {
      state.terminalOutcomes.push(outcome);
      events.push({ type: 'terminate', outcome });
    },
    onDraftReady(ref, event) { events.push({ type: 'draft', event }); },
    onNoteReviewReady(ref, id, review) { events.push({ type: 'review', id, review }); },
    ...overrides.callbacks,
  };
  return { callbacks, state };
}

/** 端口桩：默认全部「成功但不做事」，测试按需覆盖单项。 */
export function createPorts(overrides = {}) {
  const calls = [];
  const record = (name) => (...args) => {
    calls.push({ name, args });
    return undefined;
  };
  const ports = {
    calls,
    intent: {
      classify: async () => 'chat',
      classifyWithCancellation: async () => 'chat',
      classifyLocalIntent: () => undefined,
      inlineNoteMaterial: () => '',
      ...(overrides.intent ?? {}),
    },
    reply: {
      isConfigured: async () => true,
      complete: async () => '默认回答',
      completeRouted: async () => ({ text: '默认回答', degraded: false }),
      stream: async (_context, sink) => {
        sink({ type: 'text', delta: '默认回答' });
        return { content: '默认回答', interrupted: false, usedFallback: false };
      },
      normalize: (value) => value,
      ...(overrides.reply ?? {}),
    },
    capture: {
      analyzeImage: async () => ({ category: '概念', subject: '数学分析', chapter: '连续性', confidence: 0.9, cleaned_text: '内容' }),
      generateNoteDraftWithSources: record('generateNoteDraftWithSources'),
      generateNoteDraftWithBundle: record('generateNoteDraftWithBundle'),
      saveNoteContextClarification: record('saveNoteContextClarification'),
      resumeNoteContextClarification: record('resumeNoteContextClarification'),
      regenerateNoteDraft: record('regenerateNoteDraft'),
      ...(overrides.capture ?? {}),
    },
    noteRoute: { select: () => undefined, ...(overrides.noteRoute ?? {}) },
    draftService: {
      restoreDraft: async () => ({}),
      confirmDraft: async (_event, candidate) => candidate,
      cancelDraft: async () => {},
      retryDraft: async () => ({}),
      listRecoverableDrafts: async () => [],
      regenerateNoteDraft: async () => ({}),
      ...(overrides.draftService ?? {}),
    },
    memoryService: {
      saveMessage: async () => { calls.push({ name: 'saveMessage', args: [] }); },
      saveOcrResult: async () => '',
      getStructuredContextForNoteGeneration: async () => ({
        bundle: { fragments: [], sources: [] },
        candidates: [],
        degraded: false,
        reason: '',
      }),
      updateLearnerProfileIfNeeded: async () => {},
      summarizeSessionIfNeeded: async () => {},
      getPendingNoteMaterials: async () => [],
      getContextForReply: async () => '',
      getContextForNoteGeneration: async () => '',
      getLearnerProfileContext: async () => '',
      ...(overrides.memoryService ?? {}),
    },
    evidence: {
      build: async () => undefined,
      formatRetrievalStatus: () => '笔记检索：未命中',
      formatSources: () => '参考来源：',
      sanitizeAnswer: (_ctx, answer) => answer,
      createStreamFilter: () => ({ push: (delta) => delta, flush: () => '' }),
      createStrictStreamFilter: () => ({ push: (delta) => delta, flush: () => '' }),
      hasVerifiedCitation: () => false,
      ...(overrides.evidence ?? {}),
    },
    review: {
      classifyIntent: () => undefined,
      plan: async () => ({
        kind: 'none',
        answer: { intent: 'explain', query: '', status: 'insufficient', reason: 'none', citations: [], createdAt: 0 },
        displayText: '',
        modelUserContent: '',
        quizCount: 0,
      }),
      createStreamFilter: () => ({ push: (delta) => delta, flush: () => '' }),
      finalizeModelAnswer: () => ({
        answer: { intent: 'explain', query: '', status: 'grounded', reason: 'grounded', citations: [], createdAt: 0 },
        displayText: '',
      }),
      fallbackFailure: () => ({
        answer: { intent: 'explain', query: '', status: 'unavailable', reason: 'model-failed', citations: [], createdAt: 0 },
        displayText: '',
      }),
      ...(overrides.review ?? {}),
    },
    toolReply: overrides.toolReply,
  };
  return ports;
}

/** 合法运行标识：session /^[0-9a-z]{2,64}$/，run /^r[0-9a-z]{2,63}$/。 */
export function createRunRef(runId = 'run1', sessionId = 'sess1') {
  return { sessionId, runId };
}

/** 构造一个已装配好的工作流实例。 */
export function createWorkflow(options = {}) {
  const WorkflowClass = loadConversationGraph(options);
  const { callbacks, state } = createCallbacks(options);
  const ports = createPorts(options.ports ?? {});
  const workflow = new WorkflowClass(callbacks, ports);
  const graph = workflow.buildGraph();
  return { workflow, graph, callbacks, state, ports, WorkflowClass };
}
