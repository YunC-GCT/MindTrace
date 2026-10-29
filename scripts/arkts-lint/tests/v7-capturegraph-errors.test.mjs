// #243 步骤 3：CaptureGraph 边界停止抹平错误类型。
// 用 note-review-ets-loader 装载真实 .ets（TypeScript 转译 + 独立 vm realm），不复制实现。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const cache = new Map();
// Each .ets load gets its own vm realm; inject the host Error so a node defined by
// the test (`throw new Error('boom')`) is `instanceof Error` inside CaptureGraph.
const baseOptions = { cache, globals: { Error } };
const graphRuntime = loadNoteReviewEtsModule('common/src/main/ets/workflow/StateGraph.ets', baseOptions);
const errorsModule = loadNoteReviewEtsModule('common/src/main/ets/workflow/RunErrors.ets', baseOptions);

// CaptureGraph imports the public `common` barrel. The loader has no HSP resolution,
// so map the barrel's runtime exports onto the same loaded modules/functions.
const commonMock = {
  StateGraph: graphRuntime.StateGraph,
  StateGraphError: graphRuntime.StateGraphError,
  isCancellationError: errorsModule.isCancellationError,
  isDeadlineExceededError: errorsModule.isDeadlineExceededError,
};

const stateModule = loadNoteReviewEtsModule('agents/src/main/ets/graph/AgentState.ets', {
  ...baseOptions,
  mocks: { common: commonMock },
});
const contextModule = loadNoteReviewEtsModule('common/src/main/ets/workflow/RunContext.ets', baseOptions);
const tokenModule = loadNoteReviewEtsModule('common/src/main/ets/llm/CancellationToken.ets', baseOptions);
const captureGraphModule = loadNoteReviewEtsModule('agents/src/main/ets/graph/CaptureGraph.ets', {
  ...baseOptions,
  mocks: { common: commonMock },
});

const CaptureGraph = captureGraphModule.CaptureGraph;
const CancellationError = errorsModule.CancellationError;
const DeadlineExceededError = errorsModule.DeadlineExceededError;
const CancellationToken = tokenModule.CancellationToken;
const createRootRunContext = contextModule.createRootRunContext;

function initialState() {
  return {
    captureText: 'x + 1 = 2',
    source: 'test',
    currentStep: 'START',
    persist: false,
    analysisOnly: false,
  };
}

function graphWithNode(node) {
  const graph = new CaptureGraph();
  graph.addNode('capture', node);
  graph.addEdge('START', 'capture');
  graph.addEdge('capture', 'END');
  return graph;
}

function stateNode() {
  return async (state) => ({ state });
}

function throwingNode(error) {
  return async () => {
    throw error;
  };
}

test('node-thrown CancellationError lands as CANCELLED', async () => {
  const graph = graphWithNode(throwingNode(new CancellationError('CONVERSATION_CANCELLED')));
  const result = await graph.run(initialState());
  assert.equal(result.error.kind, 'CANCELLED');
  assert.match(result.error.message, /CONVERSATION_CANCELLED/);
});

test('CancellationToken.throwIfCancelled is still recognized as cancellation', async () => {
  const token = new CancellationToken();
  const graph = graphWithNode(async () => {
    token.cancel();
    token.throwIfCancelled();
    return { state: initialState() };
  });
  const context = createRootRunContext('err-run', 8, 0, token);
  const result = await graph.run(initialState(), context);
  assert.equal(result.error.kind, 'CANCELLED');
  assert.match(result.error.message, /CONVERSATION_CANCELLED/);
});

test('node-thrown DeadlineExceededError lands as DEADLINE_EXCEEDED', async () => {
  const graph = graphWithNode(throwingNode(new DeadlineExceededError('deadline')));
  const result = await graph.run(initialState());
  assert.equal(result.error.kind, 'DEADLINE_EXCEEDED');
});

test('a thrown error shape keeps kind, step and retriable', async () => {
  // 节点用对象字面量抛错误（CaptureGraphError 是 interface，不能 new），
  // 边界必须原样保留三个字段，不能改写成 NODE_ERROR / 当前 step / false。
  const graph = graphWithNode(throwingNode(
    { kind: 'LLM_UNAVAILABLE', message: 'x', step: 'classify', retriable: true },
  ));
  const result = await graph.run(initialState());
  assert.equal(result.error.kind, 'LLM_UNAVAILABLE');
  assert.equal(result.error.step, 'classify');
  assert.equal(result.error.retriable, true);
});

test('an unknown node error still becomes NODE_ERROR with its message', async () => {
  const graph = graphWithNode(throwingNode(new Error('boom')));
  const result = await graph.run(initialState());
  assert.equal(result.error.kind, 'NODE_ERROR');
  assert.equal(result.error.message, 'boom');
});

test('a zero context budget lands as MAX_NODE_RUNS', async () => {
  const graph = graphWithNode(stateNode());
  const context = createRootRunContext('r', 0, 0, null);
  const result = await graph.run(initialState(), context);
  assert.equal(result.error.kind, 'MAX_NODE_RUNS');
});

test('a graph missing an edge still lands as INVALID_GRAPH', async () => {
  const graph = new CaptureGraph();
  graph.addNode('capture', stateNode());
  const result = await graph.run(initialState());
  assert.equal(result.error.kind, 'INVALID_GRAPH');
});
