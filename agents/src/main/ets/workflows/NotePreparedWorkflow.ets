/**
 * NotePreparedWorkflow.ets — preparedCandidate（确认后提交）的 workflow（spec 039）
 *
 * 路径: agents/src/main/ets/workflows/NotePreparedWorkflow.ets
 * 职责: preparedCandidate 命令的编排入口（S1 骨架 + 委托 PreparedBranch；审批哈希前置在 CommandRouter.preflight）。
 * 依赖: common（PreparedCandidate / NoteCommand / NoteOutcome）、core/dispatch/PreparedBranch、WorkflowContext。
 * 数据流: CommandExecutor.dispatchCommand() → CommandRouter.preflight(审批哈希) → resolve()=prepared → 本类 run() → PreparedBranch
 *
 * 边界: 不发 run 级事件；审批拒绝由 router 前置返回（不会进到本 workflow）。
 *
 * 当前状态（2026-11-02）: 本类是转发壳，真实逻辑在 core/dispatch/PreparedBranch。
 *       spec 039 的分支内容迁移尚未完成；改业务请改 branch，不要在壳里加逻辑。
 */
import type { NoteCommand, NoteOutcome, PreparedCandidate } from 'common';
import { PreparedBranch } from '../core/dispatch/PreparedBranch';
import type { NoteWorkflow, WorkflowContext } from './WorkflowContext';

export class NotePreparedWorkflow implements NoteWorkflow {
  async run(command: NoteCommand, context: WorkflowContext): Promise<NoteOutcome> {
    const prepared: PreparedCandidate | undefined = command.preparedCandidate;
    if (prepared === undefined) {
      throw new Error('PREPARED_CANDIDATE_MISSING: preparedCandidate workflow requires command.preparedCandidate');
    }
    return await PreparedBranch.dispatch(
      context.request,
      prepared,
      context.options,
      context.startedAt,
      context.runContext,
    );
  }
}
