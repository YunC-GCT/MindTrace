/**
 * RunContext.ets — 一次 run 的运行身份 / 截止时间 / 取消令牌 / 共享预算。
 *
 * 路径: common/src/main/ets/workflow/RunContext.ets
 * 职责: 把 runId、parentRunId、deadlineAt、CancellationToken、RunBudget 组合成一次 run 的只读上下文，
 *       并提供统一的停止检查 throwIfStopped()。本切片只定义类型，不接任何调用方。
 * 依赖: ../llm/CancellationToken（common 内部依赖，无 Kit）、./RunBudget、./RunErrors
 *
 * 数据流:
 *   Dispatcher（步骤 4 接线）→ createRootRunContext → StateGraph.run(context)
 *   父图节点 → createChildRunContext(parent, childRunId) → 子图；子图与父图共享同一个 budget 实例
 *
 * 契约要点（issue #243 §1）:
 *   - createChildRunContext 传的是同一个 RunBudget 实例，不是复制、不是新 new；
 *     父子累计天然成立，不需要任何「传下去的数字」。
 *   - deadlineAt 用绝对时间戳（epoch ms），0 = 不设截止；跨节点、跨子图不会被重复扣减。
 *   - throwIfStopped() 先查 token，再查 deadline；两者都成立时先抛取消。
 *   - runId 允许空串（调用方还没接），不为它抛错。
 *
 * ArkTS 1.1 strict 适配:
 *   - 显式字段 + 构造器赋值；不使用构造器参数属性简写。
 *   - token 用 `CancellationToken | null` 显式表达「可能没有」，不做可选字段。
 */
import { CancellationToken } from '../llm/CancellationToken';
import { RunBudget, createRunBudget } from './RunBudget';
import { CancellationError, DeadlineExceededError } from './RunErrors';

export class RunContext {
  readonly runId: string;
  readonly parentRunId: string;
  readonly deadlineAt: number;
  readonly token: CancellationToken | null;
  readonly budget: RunBudget;

  constructor(runId: string, parentRunId: string, deadlineAt: number, token: CancellationToken | null,
    budget: RunBudget) {
    this.runId = runId;
    this.parentRunId = parentRunId;
    this.deadlineAt = deadlineAt;
    this.token = token;
    this.budget = budget;
  }

  throwIfStopped(): void {
    const token: CancellationToken | null = this.token;
    if (token !== null && token.isCancelled()) {
      throw new CancellationError('run cancelled');
    }
    if (this.deadlineAt > 0 && Date.now() >= this.deadlineAt) {
      throw new DeadlineExceededError('run deadline exceeded');
    }
  }
}

// 顶层 run：自己创建预算，parentRunId 为 ''。
export function createRootRunContext(runId: string, limit: number, deadlineAt: number,
  token: CancellationToken | null): RunContext {
  return new RunContext(runId, '', deadlineAt, token, createRunBudget(limit));
}

// 子 run：共享父的 budget 实例，继承 deadlineAt 与 token，parentRunId 指向父的 runId。
export function createChildRunContext(parent: RunContext, childRunId: string): RunContext {
  return new RunContext(childRunId, parent.runId, parent.deadlineAt, parent.token, parent.budget);
}
