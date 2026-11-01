/**
 * WorkflowContext.ets — 命令 workflow 的运行时上下文（spec 039）
 *
 * 路径: agents/src/main/ets/workflows/WorkflowContext.ets
 * 职责: 把一个 NoteCommand 的执行上下文（BranchRequest / DispatchOptions / RunContext / 起始时间）
 *       传给具体 workflow；workflow 只消费、不创建 run（run 生命周期由 CommandExecutor 负责）。
 * 依赖: common（BranchRequest / NoteCommand / NoteOutcome 类型）、core/dispatch/DispatchOptions、common RunContext。
 * 数据流: CommandExecutor.dispatchCommand() → new WorkflowContext → workflow.run(command, context) → NoteOutcome
 */
import type { BranchRequest, NoteCommand, NoteOutcome, RunContext } from 'common';
import type { DispatchOptions } from '../core/dispatch/DispatchOptions';

export interface WorkflowContext {
  request: BranchRequest;
  options: DispatchOptions;
  runContext: RunContext;
  startedAt: number;
}

/** 所有 note workflow 的统一契约：吃一条命令 + 上下文，返回唯一终态。 */
export interface NoteWorkflow {
  run(command: NoteCommand, context: WorkflowContext): Promise<NoteOutcome>;
}
