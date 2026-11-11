// #243 步骤 1：RunBudget / RunErrors / RunContext 契约测试。
// 用 note-review-ets-loader 装载真实 .ets（TypeScript 转译 + 独立 vm realm），不复制实现。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const budgetModule = loadNoteReviewEtsModule('common/src/main/ets/workflow/RunBudget.ets');
const errorsModule = loadNoteReviewEtsModule('common/src/main/ets/workflow/RunErrors.ets');
const contextModule = loadNoteReviewEtsModule('common/src/main/ets/workflow/RunContext.ets');
const tokenModule = loadNoteReviewEtsModule('common/src/main/ets/llm/CancellationToken.ets');

const createRunBudget = budgetModule.createRunBudget;
const createRootRunContext = contextModule.createRootRunContext;
const createChildRunContext = contextModule.createChildRunContext;
const isCancellationError = errorsModule.isCancellationError;
const isDeadlineExceededError = errorsModule.isDeadlineExceededError;

function newToken() {
  return new tokenModule.CancellationToken();
}

function captureThrow(run) {
  try {
    run();
  } catch (error) {
    return error;
  }
  return null;
}

test('createRunBudget(2) allows exactly two takes and then refuses', () => {
  const budget = createRunBudget(2);
  assert.equal(budget.limit, 2, 'a finite non-negative limit is kept as given');
  assert.equal(budget.used, 0, 'a fresh budget starts unused');
  assert.equal(budget.hasRemaining(), true, 'limit=2 has remaining budget before any take');
  assert.equal(budget.take(), true, 'first take succeeds while used=0 < limit=2');
  assert.equal(budget.take(), true, 'second take succeeds while used=1 < limit=2');
  assert.equal(budget.take(), false, 'third take fails because used=2 is not < limit=2');
  assert.equal(budget.used, 2, 'used only advances on successful takes');
  assert.equal(budget.hasRemaining(), false, 'an exhausted budget reports no remaining');
});

test('take returns false, never throws, once the budget is exhausted', () => {
  const budget = createRunBudget(1);
  assert.equal(budget.take(), true, 'the single allowed take succeeds');
  assert.doesNotThrow(() => budget.take(), 'an exhausted take must not throw; the caller decides');
  assert.equal(budget.take(), false, 'every later take still reports false');
  assert.equal(budget.used, 1, 'failed takes never increment used');
});

test('negative limits normalize to zero', () => {
  const budget = createRunBudget(-5);
  assert.equal(budget.limit, 0, '#243 step 1: limit < 0 is normalized to 0');
  assert.equal(budget.hasRemaining(), false, 'a zero budget has nothing to spend');
  assert.equal(budget.take(), false, 'a zero budget refuses the first take');
});

test('non-finite limits normalize to zero', () => {
  const nan = createRunBudget(Number.NaN);
  const infinite = createRunBudget(Number.POSITIVE_INFINITY);
  assert.equal(nan.limit, 0, 'NaN is not a finite budget and normalizes to 0');
  assert.equal(infinite.limit, 0, 'Infinity is not a finite budget and normalizes to 0');
  assert.equal(nan.take(), false, 'a NaN budget refuses take');
  assert.equal(infinite.take(), false, 'an Infinity budget refuses take');
});

test('a child context shares the parent budget instance', () => {
  const root = createRootRunContext('r1', 4, 0, null);
  const child = createChildRunContext(root, 'c1');
  assert.equal(child.budget, root.budget, 'createChildRunContext must reuse the instance, not copy it');
  assert.equal(child.budget.take(), true, 'child take 1 spends from the shared budget');
  assert.equal(child.budget.take(), true, 'child take 2 spends from the shared budget');
  assert.equal(root.budget.used, 2, 'the parent sees the child spending: one shared counter');
  assert.equal(root.budget.hasRemaining(), true, 'limit=4 still has 2 left after two child takes');
});

test('a child context inherits identity fields, deadline and token', () => {
  const token = newToken();
  const root = createRootRunContext('r1', 4, 4102444800000, token);
  const child = createChildRunContext(root, 'c1');
  assert.equal(root.parentRunId, '', 'a root context has no parent');
  assert.equal(child.parentRunId, 'r1', 'a child points at its parent runId');
  assert.equal(child.runId, 'c1', 'a child keeps the supplied child runId');
  assert.equal(child.deadlineAt, 4102444800000, 'a child inherits the absolute deadline unchanged');
  assert.equal(child.token, token, 'a child inherits the same token instance');
});

test('a child of a token-less root keeps token null and deadlineAt 0', () => {
  const root = createRootRunContext('r2', 2, 0, null);
  const child = createChildRunContext(root, 'c2');
  assert.equal(child.token, null, 'a null token stays null, never a fabricated token');
  assert.equal(child.deadlineAt, 0, 'deadlineAt=0 (no deadline) is inherited unchanged');
});

test('an empty runId is accepted because callers are not wired yet', () => {
  const root = createRootRunContext('', 1, 0, null);
  assert.equal(root.runId, '', 'step 1 must not throw on an empty runId');
});

test('a cancelled token makes throwIfStopped throw CancellationError', () => {
  const token = newToken();
  const context = createRootRunContext('r-cancel', 4, 0, token);
  assert.doesNotThrow(() => context.throwIfStopped(), 'a fresh token is not cancelled');
  token.cancel();
  const thrown = captureThrow(() => context.throwIfStopped());
  assert.notEqual(thrown, null, 'a cancelled token must stop the run');
  assert.equal(thrown.name, 'CancellationError', 'the boundary classifies by name');
  assert.equal(thrown.code, 'CANCELLED', 'CancellationError carries the ADR-0019 CANCELLED code');
  assert.equal(thrown.message, 'CONVERSATION_CANCELLED', 'cancel keeps the token message so existing consumers still match');
});

test('an expired deadline makes throwIfStopped throw DeadlineExceededError', () => {
  const context = createRootRunContext('r-deadline', 4, Date.now() - 1, null);
  const thrown = captureThrow(() => context.throwIfStopped());
  assert.notEqual(thrown, null, 'an already-expired deadline must stop the run');
  assert.equal(thrown.name, 'DeadlineExceededError', 'the boundary classifies by name');
  assert.equal(thrown.code, 'DEADLINE_EXCEEDED', 'DeadlineExceededError carries the new ADR-0019 code');
  assert.equal(thrown.message, 'run deadline exceeded', 'the default English message matches the repo style');
});

test('deadlineAt=0 means no deadline at all', () => {
  const context = createRootRunContext('r-no-deadline', 4, 0, null);
  assert.doesNotThrow(() => context.throwIfStopped(), '0 disables the deadline check');
});

test('cancellation wins when the token is cancelled and the deadline has passed', () => {
  const token = newToken();
  token.cancel();
  const context = createRootRunContext('r-both', 4, Date.now() - 1, token);
  const thrown = captureThrow(() => context.throwIfStopped());
  assert.notEqual(thrown, null, 'both stop reasons are present, so the run must stop');
  assert.equal(thrown.name, 'CancellationError', 'throwIfStopped checks the token before the deadline');
  assert.equal(thrown.code, 'CANCELLED', 'the first stop reason wins');
});

test('a healthy run context returns silently', () => {
  const context = createRootRunContext('r-healthy', 4, Date.now() + 60000, newToken());
  assert.doesNotThrow(() => context.throwIfStopped(), 'no cancellation and a future deadline must not throw');
});

test('isCancellationError recognizes its own type across the loader realm', () => {
  const token = newToken();
  token.cancel();
  const cancellation = captureThrow(() => createRootRunContext('r-x', 1, 0, token).throwIfStopped());
  const deadline = captureThrow(() => createRootRunContext('r-y', 1, Date.now() - 1, null).throwIfStopped());
  assert.equal(cancellation instanceof errorsModule.CancellationError, false,
    'the loader realms differ, so instanceof is false; name+code is the real contract');
  assert.equal(isCancellationError(cancellation), true, 'name+code makes this a cancellation');
  assert.equal(isCancellationError(deadline), false, 'a deadline error is a different type');
});

test('isDeadlineExceededError recognizes its own type across the loader realm', () => {
  const token = newToken();
  token.cancel();
  const cancellation = captureThrow(() => createRootRunContext('r-x2', 1, 0, token).throwIfStopped());
  const deadline = captureThrow(() => createRootRunContext('r-y2', 1, Date.now() - 1, null).throwIfStopped());
  assert.equal(deadline instanceof errorsModule.DeadlineExceededError, false,
    'the loader realms differ, so instanceof is false; name+code is the real contract');
  assert.equal(isDeadlineExceededError(deadline), true, 'name+code makes this a deadline error');
  assert.equal(isDeadlineExceededError(cancellation), false, 'a cancellation is a different type');
});
