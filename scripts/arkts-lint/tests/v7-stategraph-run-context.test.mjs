// #243 步骤 2：StateGraph 接 RunContext 的行为测试。
// 用 note-review-ets-loader 装载真实 .ets（TypeScript 转译 + 独立 vm realm），不复制实现。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const cache = new Map();
const graphModule = loadNoteReviewEtsModule('common/src/main/ets/workflow/StateGraph.ets', { cache });
const contextModule = loadNoteReviewEtsModule('common/src/main/ets/workflow/RunContext.ets', { cache });
const errorsModule = loadNoteReviewEtsModule('common/src/main/ets/workflow/RunErrors.ets', { cache });
const tokenModule = loadNoteReviewEtsModule('common/src/main/ets/llm/CancellationToken.ets', { cache });

const StateGraph = graphModule.StateGraph;
const createRootRunContext = contextModule.createRootRunContext;
const createChildRunContext = contextModule.createChildRunContext;
const isCancellationError = errorsModule.isCancellationError;
const isDeadlineExceededError = errorsModule.isDeadlineExceededError;

async function captureAsyncThrow(run) {
  try {
    await run();
  } catch (error) {
    return error;
  }
  return null;
}

// 线性图：START -> names[0] -> ... -> names[last] -> END。
function buildLinearGraph(names, handlers) {
  const graph = new StateGraph('START', 'END');
  for (const name of names) {
    graph.addNode(name, handlers[name]);
  }
  graph.addEdge('START', names[0]);
  for (let index = 0; index < names.length - 1; index += 1) {
    graph.addEdge(names[index], names[index + 1]);
  }
  graph.addEdge(names[names.length - 1], 'END');
  return graph;
}

// 记录调用顺序并原样返回 state 的节点。
function recordingNode(calls, name) {
  return async (state) => {
    calls.push(name);
    return state;
  };
}

test('parent and child graphs spend one shared budget (#243 acceptance 1)', async () => {
  const root = createRootRunContext('root', 4, 0, null);
  const parentCalls = [];
  const childCalls = [];

  const child = buildLinearGraph(
    ['c1', 'c2', 'c3'],
    {
      c1: recordingNode(childCalls, 'c1'),
      c2: recordingNode(childCalls, 'c2'),
      c3: recordingNode(childCalls, 'c3'),
    },
  );

  const graph = new StateGraph('START', 'END');
  graph.addNode('p1', recordingNode(parentCalls, 'p1'));
  graph.addNode('p2', async (state) => {
    parentCalls.push('p2');
    const childContext = createChildRunContext(root, 'c1');
    return child.run(state, 0, childContext);
  });
  graph.addNode('p3', recordingNode(parentCalls, 'p3'));
  graph.addEdge('START', 'p1');
  graph.addEdge('p1', 'p2');
  graph.addEdge('p2', 'p3');
  graph.addEdge('p3', 'END');

  const error = await captureAsyncThrow(() => graph.run({ count: 0 }, 128, root));
  assert.notEqual(error, null, 'the fifth take must fail');
  assert.equal(error.name, 'StateGraphError');
  assert.equal(error.kind, 'MAX_NODE_RUNS');
  assert.equal(error.step, 'c3', 'the overflow is detected inside the child graph, not at the parent');
  assert.equal(root.budget.used, 4, 'four takes succeeded across parent and child; the failed fifth did not spend');
  assert.deepEqual(parentCalls, ['p1', 'p2'], 'parent p3 never starts after the child throws');
  assert.deepEqual(childCalls, ['c1', 'c2'], 'child c3 is rejected before its node function runs');
});

test('budget exhaustion is reported before the over-limit node runs', async () => {
  const root = createRootRunContext('root-2', 2, 0, null);
  const calls = [];
  const graph = buildLinearGraph(
    ['n1', 'n2', 'n3'],
    {
      n1: recordingNode(calls, 'n1'),
      n2: recordingNode(calls, 'n2'),
      n3: recordingNode(calls, 'n3'),
    },
  );

  const error = await captureAsyncThrow(() => graph.run({ count: 0 }, 128, root));
  assert.notEqual(error, null, 'the third node must be rejected');
  assert.equal(error.name, 'StateGraphError');
  assert.equal(error.kind, 'MAX_NODE_RUNS');
  assert.equal(error.step, 'n3', 'the failing step is the third node');
  assert.equal(error.message, 'Workflow exceeded run budget=2', 'the message reports the limit, not used');
  assert.deepEqual(calls, ['n1', 'n2'], 'the over-limit node never executes');
  assert.equal(root.budget.used, 2, 'the failed take did not spend');
});

test('an expired deadline stops before the first node and before any take (#243 acceptance 3)', async () => {
  const root = createRootRunContext('root-deadline', 4, Date.now() - 1, null);
  const calls = [];
  const graph = buildLinearGraph(['n1'], { n1: recordingNode(calls, 'n1') });

  const error = await captureAsyncThrow(() => graph.run({ count: 0 }, 128, root));
  assert.notEqual(error, null, 'an already-expired deadline must stop the run');
  assert.equal(isDeadlineExceededError(error), true, 'classified by name+code, not instanceof');
  assert.equal(error.name, 'DeadlineExceededError');
  assert.equal(error.code, 'DEADLINE_EXCEEDED');
  assert.equal(calls.length, 0, 'no node ran, so no LLM call is issued');
  assert.equal(root.budget.used, 0, 'the stop check runs before budget.take()');
});

test('a pre-cancelled token stops before the first node and before any take', async () => {
  const token = new tokenModule.CancellationToken();
  token.cancel();
  const root = createRootRunContext('root-cancel', 4, 0, token);
  const calls = [];
  const graph = buildLinearGraph(['n1'], { n1: recordingNode(calls, 'n1') });

  const error = await captureAsyncThrow(() => graph.run({ count: 0 }, 128, root));
  assert.notEqual(error, null, 'a cancelled token must stop the run');
  assert.equal(isCancellationError(error), true, 'classified by name+code, not instanceof');
  assert.equal(error.name, 'CancellationError');
  assert.equal(error.code, 'CANCELLED');
  assert.equal(calls.length, 0, 'no node ran');
  assert.equal(root.budget.used, 0, 'a cancelled run must not consume budget');
});

test('cancelling inside a node stops the graph before the next node', async () => {
  const token = new tokenModule.CancellationToken();
  const root = createRootRunContext('root-mid-cancel', 4, 0, token);
  const calls = [];
  const graph = buildLinearGraph(
    ['n1', 'n2'],
    {
      n1: async (state) => {
        calls.push('n1');
        token.cancel();
        return state;
      },
      n2: recordingNode(calls, 'n2'),
    },
  );

  const error = await captureAsyncThrow(() => graph.run({ count: 0 }, 128, root));
  assert.notEqual(error, null, 'the post-node stop check must throw');
  assert.equal(isCancellationError(error), true);
  assert.equal(error.name, 'CancellationError');
  assert.equal(calls.length, 1, 'the second node is never called');
  assert.deepEqual(calls, ['n1']);
  assert.equal(root.budget.used, 1, 'the node that ran did spend its take');
});

test('the legacy path keeps its maxNodeRuns text and counting', async () => {
  const calls = [];
  const graph = buildLinearGraph(
    ['n1', 'n2'],
    {
      n1: recordingNode(calls, 'n1'),
      n2: recordingNode(calls, 'n2'),
    },
  );

  const error = await captureAsyncThrow(() => graph.run({ count: 0 }, 1));
  assert.notEqual(error, null, 'maxNodeRuns=1 rejects the second node');
  assert.equal(error.name, 'StateGraphError');
  assert.equal(error.kind, 'MAX_NODE_RUNS');
  assert.equal(error.step, 'n2');
  assert.equal(error.message, 'Workflow exceeded maxNodeRuns=1', 'the legacy message text is unchanged');
  assert.deepEqual(calls, ['n1'], 'only the first node ran');
});

test('maxNodeRuns is ignored when a context supplies the budget', async () => {
  const root = createRootRunContext('root-ignore', 4, 0, null);
  const calls = [];
  const graph = buildLinearGraph(
    ['n1', 'n2'],
    {
      n1: recordingNode(calls, 'n1'),
      n2: recordingNode(calls, 'n2'),
    },
  );

  const result = await graph.run({ count: 7 }, 0, root);
  assert.deepEqual(calls, ['n1', 'n2'], 'maxNodeRuns=0 must not reject the first node');
  assert.equal(root.budget.used, 2);
  assert.equal(result.count, 7);
});
