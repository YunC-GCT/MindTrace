// #243 步骤 4：Dispatcher 捕获路径接 RunContext（A4 4c Step4：改走命令 seam）。
// 用现成的 knowledge-dispatch-runtime.mjs（真实 Dispatcher + 真实 CaptureGraph，只假外部 LLM/平台/存储边界）。
//
// 四个用例的分工：
// - 用例 1 是「漏转发守卫」：如果 Dispatcher 忘了把 runContext 传给 graph.run，预算 0 就不会生效，
//   会走分支失败而不是抛 exceeded run budget=0，用例必红。
// - 用例 2 钉住「不传 runContext 也能自建上下文并进入图」：默认 responder 直接抛，
//   新契约下失败是终态（kind=failed），不再静默 success。
// - 用例 3 同时钉住「取消先于扣预算」和「外部 context 不被替换」。
// - 用例 4 钉住「失败的 capture run 不会把预算泄漏给下一次 dispatch」。
import assert from 'node:assert/strict';
import test from 'node:test';
import { createRuntime } from './knowledge-dispatch-runtime.mjs';

let seq = 0;
const captureCommand = (extra) => ({
  kind: 'capture',
  operationId: 'op-run-context-' + (++seq),
  source: 'app',
  payload: { kind: 'text', text: '函数在一点连续。' },
  ...extra,
});

test('the capture path refuses to run once the supplied budget is gone', async () => {
  const runtime = createRuntime();
  const { createRootRunContext, CancellationToken } = runtime.common;
  const context = createRootRunContext('run-budget-0', 0, 0, new CancellationToken());
  const outcome = await runtime.dispatcher.dispatchCommand(captureCommand(), {
    analysisOnly: true,
    runContext: context,
  });
  assert.equal(outcome.kind, 'failed');
  assert.match(outcome.message, /exceeded run budget=0/);
  // 预算耗尽发生在任何节点执行之前，被拒的 run 不消耗配额。
  assert.equal(context.budget.used, 0);
});

test('a dispatch without a context still builds one and reaches the end of the graph', async () => {
  const runtime = createRuntime();
  const outcome = await runtime.dispatcher.dispatchCommand(captureCommand(), { analysisOnly: true });
  // 分类 LLM 失败后走 fallback；新契约把分支失败表达为 failed 终态（带错误信息）。
  assert.equal(outcome.kind, 'failed');
  assert.ok(typeof outcome.message === 'string' && outcome.message.length > 0);
});

test('a cancelled context stops the run before any node spends budget', async () => {
  const runtime = createRuntime();
  const { createRootRunContext, CancellationToken } = runtime.common;
  const context = createRootRunContext('run-cancel-first', 8, 0, new CancellationToken());
  context.token.cancel();
  const outcome = await runtime.dispatcher.dispatchCommand(captureCommand(), {
    analysisOnly: true,
    runContext: context,
  });
  assert.equal(outcome.kind, 'cancelled');
  assert.equal(context.budget.used, 0); // 取消先于扣配额
});

test('each dispatch gets its own budget, none leaks into the next', async () => {
  const runtime = createRuntime();
  const { createRootRunContext, CancellationToken } = runtime.common;
  const first = createRootRunContext('run-a', 128, 0, new CancellationToken());
  const second = createRootRunContext('run-b', 128, 0, new CancellationToken());
  await runtime.dispatcher.dispatchCommand(captureCommand(), { analysisOnly: true, runContext: first });
  await runtime.dispatcher.dispatchCommand(captureCommand(), { analysisOnly: true, runContext: second });
  assert.ok(first.budget.used > 0, 'the first run must actually spend its budget');
  assert.equal(first.budget.used, second.budget.used); // 两个 run 走同样的节点数
  assert.ok(first.budget.hasRemaining(), 'the first run must keep budget to spare');
});
