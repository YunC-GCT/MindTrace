/**
 * CommandRouter.ets — 命令形状校验 + 路由（spec 039）
 *
 * 路径: agents/src/main/ets/core/CommandRouter.ets
 * 职责: 命令 seam 的 preflight（取消检查 / preparedCandidate 审批哈希前置）与 `kind → workflow` 路由；
 *       不执行节点、不写库、不调另一条 workflow。
 * 依赖: common（NoteCommand / NoteOutcome / PreparedCandidate / NoteGenerationRepository / NoteGenerationCheckpoint 类型）、
 *       ./dispatch/DispatchOptions、./dispatch/NoteOutcomeMapper。
 * 数据流: CommandExecutor.dispatchCommand() → router.preflight() → router.resolve() → Note*Workflow
 */
import type {
  NoteCommand,
  NoteOutcome,
  NoteGenerationCheckpoint,
  NoteGenerationRepository,
  PreparedCandidate,
} from 'common';
import type { DispatchOptions } from './dispatch/DispatchOptions';
import { NoteOutcomeMapper } from './dispatch/NoteOutcomeMapper';

export type NoteWorkflowId = 'capture' | 'generation' | 'regenerate' | 'prepared';

/** preflight 结果：outcome=终止终态（取消）；errorCode=拒绝（不进 workflow）；空=放行。 */
export interface RouterPreflightResult {
  outcome?: NoteOutcome;
  errorCode?: string;
  errorMessage?: string;
  retryable?: boolean;
}

export class CommandRouter {
  /** 写前前置校验：取消令牌优先，其次 preparedCandidate 的检查点/审批哈希。 */
  async preflight(command: NoteCommand, options: DispatchOptions): Promise<RouterPreflightResult> {
    const token = options.cancellationToken;
    if (token !== undefined && token.isCancelled()) {
      return { outcome: NoteOutcomeMapper.fromThrown(command, new Error('CONVERSATION_CANCELLED')) };
    }
    const approval = await CommandRouter.preflightApproval(command, options);
    if (approval !== undefined) {
      return approval;
    }
    return {};
  }

  /** 纯路由：按 NoteCommand.kind（及 generation.mode）选 workflow，不做业务判断。 */
  resolve(command: NoteCommand): NoteWorkflowId {
    if (command.kind === 'preparedCandidate') {
      return 'prepared';
    }
    if (command.kind === 'regenerate') {
      return 'regenerate';
    }
    if (command.kind === 'generation') {
      const mode: string = command.generation !== undefined ? command.generation.mode : 'create';
      return mode === 'regenerate' ? 'regenerate' : 'generation';
    }
    // capture / analysisOnly 共用采集 workflow（analysisOnly 由 DispatchOptions.analysisOnly 决定不落库）
    return 'capture';
  }

  /**
   * preparedCandidate 的写前审批前置：
   * - 检查点不存在 / hash 不符 / 未审批 → 拒绝（不再走到写入才失败）
   * - approvedAt 缺省（v18 前的历史检查点 / 测试桩）放行，由写端口兜底
   */
  private static async preflightApproval(
    command: NoteCommand,
    options: DispatchOptions,
  ): Promise<RouterPreflightResult | undefined> {
    if (command.kind !== 'preparedCandidate') {
      return undefined;
    }
    const prepared: PreparedCandidate | undefined = command.preparedCandidate;
    if (prepared === undefined) {
      return undefined;
    }
    const repository: NoteGenerationRepository | undefined = options.generationRepository;
    if (repository === undefined) {
      return undefined;
    }
    const recovery = await repository.restore(prepared.runId);
    if (recovery === undefined) {
      return {
        errorCode: 'PREPARED_CHECKPOINT_MISSING',
        errorMessage: '草稿检查点不存在，请重新预览确认',
        retryable: false,
      };
    }
    let checkpoint: NoteGenerationCheckpoint | undefined = undefined;
    for (const item of recovery.checkpoints) {
      if (item.id === prepared.checkpointId) {
        checkpoint = item;
        break;
      }
    }
    if (checkpoint === undefined) {
      return {
        errorCode: 'PREPARED_CHECKPOINT_MISSING',
        errorMessage: '草稿检查点不存在，请重新预览确认',
        retryable: false,
      };
    }
    if (checkpoint.candidateHash !== prepared.candidateHash) {
      return {
        errorCode: 'APPROVAL_HASH_MISMATCH',
        errorMessage: '候选内容已变化，请重新预览确认',
        retryable: false,
      };
    }
    const approvedAt: number | undefined = checkpoint.approvedAt;
    if (approvedAt !== undefined && approvedAt <= 0) {
      return {
        errorCode: 'APPROVAL_HASH_MISMATCH',
        errorMessage: '该检查点尚未审批，无法写入',
        retryable: false,
      };
    }
    return undefined;
  }
}
