/**
 * NoteCaptureWorkflow.ets — capture / captureSet / analysisOnly 的 workflow（spec 039）
 *
 * 路径: agents/src/main/ets/workflows/NoteCaptureWorkflow.ets
 * 职责: capture 命令的编排入口。S1 只做「骨架 + 委托」：图装配仍由 CaptureBranch / NoteAgent 承担，
 *       S2 再把采集图直接收进本 workflow 并删除 CaptureBranch。
 * 依赖: common（NoteCommand / NoteOutcome / BranchRequest 类型）、core/dispatch/CaptureBranch、WorkflowContext。
 * 数据流: CommandExecutor.dispatchCommand() → CommandRouter.resolve()=capture → 本类 run() → CaptureBranch → CaptureGraph
 *
 * 边界: 不发 run 级事件（run.started/terminal 由 CommandExecutor 统一发）。
 */
import type { NoteCommand, NoteOutcome } from 'common';
import { CaptureBranch } from '../core/dispatch/CaptureBranch';
import type { NoteWorkflow, WorkflowContext } from './WorkflowContext';

export class NoteCaptureWorkflow implements NoteWorkflow {
  async run(command: NoteCommand, context: WorkflowContext): Promise<NoteOutcome> {
    return await CaptureBranch.dispatchCapture(
      context.request,
      context.options,
      context.runContext,
      context.startedAt,
    );
  }
}
