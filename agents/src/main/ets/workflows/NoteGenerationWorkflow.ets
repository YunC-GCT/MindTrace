/**
 * NoteGenerationWorkflow.ets — generation（新建/标准/深度）的 workflow（spec 039）
 *
 * 路径: agents/src/main/ets/workflows/NoteGenerationWorkflow.ets
 * 职责: generation 命令的编排入口（S1 骨架 + 委托 GenerationBranch；后续切片把分支内容收进 workflow）。
 * 依赖: common（NoteGenerationRequest 类型 / NoteCommand / NoteOutcome）、core/dispatch/GenerationBranch、WorkflowContext。
 * 数据流: CommandExecutor.dispatchCommand() → CommandRouter.resolve()=generation → 本类 run() → GenerationBranch → GenerationEvaluator
 *
 * 边界: 不发 run 级事件；分支内部错误由调用方（CommandExecutor）映射终态。
 *
 * 当前状态（2026-11-02）: 本类是转发壳，真实逻辑在 core/dispatch/GenerationBranch。
 *       spec 039 的分支内容迁移尚未完成；改业务请改 branch，不要在壳里加逻辑。
 */
import type { NoteCommand, NoteOutcome, NoteGenerationRequest } from 'common';
import { GenerationBranch } from '../core/dispatch/GenerationBranch';
import type { NoteWorkflow, WorkflowContext } from './WorkflowContext';

export class NoteGenerationWorkflow implements NoteWorkflow {
  async run(command: NoteCommand, context: WorkflowContext): Promise<NoteOutcome> {
    const request: NoteGenerationRequest = command.generation !== undefined
      ? command.generation
      : { runId: command.operationId, instruction: '', mode: 'create', route: 'light', sources: { fragments: [] } };
    return await GenerationBranch.dispatchGeneration(
      request,
      context.request,
      context.options,
      context.runContext,
      context.startedAt,
    );
  }
}
