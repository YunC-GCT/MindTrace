/**
 * NoteRegenerateWorkflow.ets — regenerate（增量重生成）的 workflow（spec 039）
 *
 * 路径: agents/src/main/ets/workflows/NoteRegenerateWorkflow.ets
 * 职责: regenerate 命令的编排入口（S1 骨架 + 委托 IncrementalBranch；后续切片把分支内容收进 workflow）。
 * 依赖: common（NoteGenerationRequest / NoteCommand / NoteOutcome）、core/dispatch/IncrementalBranch、WorkflowContext。
 * 数据流: CommandExecutor.dispatchCommand() → CommandRouter.resolve()=regenerate → 本类 run() → IncrementalBranch
 *
 * 边界: 不发 run 级事件。
 */
import type { NoteCommand, NoteOutcome, NoteGenerationRequest } from 'common';
import { IncrementalBranch } from '../core/dispatch/IncrementalBranch';
import type { NoteWorkflow, WorkflowContext } from './WorkflowContext';

export class NoteRegenerateWorkflow implements NoteWorkflow {
  async run(command: NoteCommand, context: WorkflowContext): Promise<NoteOutcome> {
    const request: NoteGenerationRequest = command.generation !== undefined
      ? command.generation
      : { runId: command.operationId, instruction: '', mode: 'regenerate', route: 'light', sources: { fragments: [] } };
    return await IncrementalBranch.dispatchIncrementalGeneration(
      request,
      context.request,
      context.options,
      context.startedAt,
    );
  }
}
