// MindTrace - PersistNode
// 2026-09-05 · D2 Ticket #5
import { AgentState, CaptureNode, CaptureGraphError, CaptureNodeResult, copyAgentState } from '../AgentState';
import { NoteCommitResult, NoteDaoInterface } from '../../models/NoteDaoInterface';
import { NotePortError, NoteGenerationCommitResult, RunContext } from 'common';
import type { NoteWriteCommand, NoteWriteOutcome, NoteWritePort } from 'common';

export class PersistNodeFactory {
  static create(dao: NoteDaoInterface): CaptureNode {
    return async (input: AgentState, context?: RunContext | null): Promise<CaptureNodeResult> => {
      context?.throwIfStopped();
      if (!input.persist) {
        return { state: input };
      }
      if (!input.knowledgeUnit) {
        const error: CaptureGraphError = {
          kind: 'PERSIST_NO_UNIT',
          message: 'persist requested but knowledgeUnit is missing',
          step: 'persist',
          retriable: false,
        };
        const next: AgentState = copyAgentState(input);
        next.error = error;
        return { state: next };
      }
      if (input.preparedCandidate?.commitKey !== undefined && input.preparedCandidate.updateExisting === true
        && dao.updateWithCommitKey !== undefined && input.preparedCandidate.expectedVersion !== undefined) {
        const commit: NoteGenerationCommitResult = {
          commitKey: input.preparedCandidate.commitKey,
          runId: input.preparedCandidate.runId,
          checkpointId: input.preparedCandidate.checkpointId,
          noteId: input.knowledgeUnit.id,
          version: input.preparedCandidate.expectedVersion + 1,
          sourceIds: input.preparedCandidate.pendingSourceIds ?? [],
          candidateJson: JSON.stringify(input.knowledgeUnit),
          committedAt: Date.now(),
          generationMetadata: input.preparedCandidate.incrementalManifest === undefined
            ? '' : JSON.stringify(input.preparedCandidate.incrementalManifest),
        };
        const commitResult = await dao.updateWithCommitKey(input.knowledgeUnit, input.preparedCandidate.expectedVersion, commit);
        context?.throwIfStopped();
        const next: AgentState = copyAgentState(input);
        if (commitResult.success === false) {
          next.error = {
            kind: commitResult.errorCode ?? 'PERSIST_ERROR',
            message: commitResult.errorMessage ?? 'KnowledgeUnit update failed',
            step: 'persist',
            retriable: false,
          };
          return { state: next };
        }
        next.commitResult = commitResult;
        return PersistNodeFactory.withStopCheck(context, next);
      }
      if (input.preparedCandidate?.updateExisting === true) {
        const next: AgentState = copyAgentState(input);
        next.error = {
          kind: 'PERSIST_UPDATE_UNSUPPORTED',
          message: 'incremental update requires the KnowledgeUnit update seam',
          step: 'persist',
          retriable: false,
        };
        return { state: next };
      }
      if (input.preparedCandidate?.commitKey !== undefined && dao.insertWithCommitKey !== undefined) {
        const commit: NoteGenerationCommitResult = {
          commitKey: input.preparedCandidate.commitKey,
          runId: input.preparedCandidate.runId,
          checkpointId: input.preparedCandidate.checkpointId,
          noteId: input.knowledgeUnit.id,
          version: input.knowledgeUnit.version,
          sourceIds: input.preparedCandidate.pendingSourceIds ?? [],
          candidateJson: JSON.stringify(input.knowledgeUnit),
          committedAt: Date.now(),
          generationMetadata: input.preparedCandidate.incrementalManifest === undefined
            ? '' : JSON.stringify(input.preparedCandidate.incrementalManifest),
        };
        const commitResult = await dao.insertWithCommitKey(input.knowledgeUnit, commit);
        context?.throwIfStopped();
        const next: AgentState = copyAgentState(input);
        if (commitResult.success === false) {
          next.error = {
            kind: commitResult.errorCode ?? 'PERSIST_ERROR',
            message: commitResult.errorMessage ?? 'KnowledgeUnit insert failed',
            step: 'persist',
            retriable: false,
          };
          return { state: next };
        }
        next.commitResult = commitResult;
        return PersistNodeFactory.withStopCheck(context, next);
      } else {
        const rowId: number = await dao.insert(input.knowledgeUnit);
        const next: AgentState = copyAgentState(input);
        next.commitResult = {
          commitKey: '',
          rowId: rowId,
          noteId: input.knowledgeUnit.id,
          version: input.knowledgeUnit.version,
          duplicate: false,
          success: true,
        };
        return PersistNodeFactory.withStopCheck(context, next);
      }
    };
  }

  /**
   * #238 / 分层迁移切片 A1：通过 NoteWritePort 落库（幂等 / CAS / 结构化错误）。
   * 普通 capture 没有外部 commitKey 时，用 `capture:<noteId>` 合成稳定幂等键；
   * preparedCandidate 分支沿用其 commitKey 与 expectedVersion。
   * 注意：审批哈希（HITL）尚未接线 —— 当前写入路径没有持久化的 approved 哈希可比，
   * 传 candidateHash 会让所有 preparedCandidate 写入被拒，故本切片不传；待 v18 加列后补。
   */
  static createWithWritePort(port: NoteWritePort): CaptureNode {
    return async (input: AgentState, context?: RunContext | null): Promise<CaptureNodeResult> => {
      context?.throwIfStopped();
      if (!input.persist) {
        return { state: input };
      }
      if (!input.knowledgeUnit) {
        const next: AgentState = copyAgentState(input);
        next.error = {
          kind: 'PERSIST_NO_UNIT',
          message: 'persist requested but knowledgeUnit is missing',
          step: 'persist',
          retriable: false,
        };
        return { state: next };
      }
      const command: NoteWriteCommand = {
        commitKey: PersistNodeFactory.deriveCommitKey(input),
      };
      const candidate = input.preparedCandidate;
      if (candidate !== undefined) {
        command.runId = candidate.runId;
        command.checkpointId = candidate.checkpointId;
        command.sourceIds = candidate.pendingSourceIds !== undefined ? candidate.pendingSourceIds : (candidate.sourceIds ?? []);
        command.generationMetadata = candidate.incrementalManifest === undefined
          ? '' : JSON.stringify(candidate.incrementalManifest);
        if (candidate.updateExisting === true && candidate.expectedVersion !== undefined) {
          command.expectedVersion = candidate.expectedVersion;
        }
        // v18：HITL 审批哈希随命令下发，端口写前校验（ADR-0019 (d)）。
        if (candidate.candidateHash.length > 0) {
          command.approvedCheckpointHash = candidate.candidateHash;
        }
      }
      try {
        const outcome: NoteWriteOutcome = await port.commit(input.knowledgeUnit, command);
        const next: AgentState = copyAgentState(input);
        const commitResult: NoteCommitResult = {
          commitKey: outcome.commitKey,
          rowId: 0,
          noteId: outcome.noteId,
          version: outcome.version,
          duplicate: outcome.duplicate,
          success: true,
        };
        next.commitResult = commitResult;
        return PersistNodeFactory.withStopCheck(context, next);
      } catch (e) {
        const next: AgentState = copyAgentState(input);
        if (e instanceof NotePortError) {
          next.error = {
            kind: e.code,
            message: e.message,
            step: 'persist',
            retriable: e.retryable,
          };
        } else {
          next.error = {
            kind: 'PERSIST_ERROR',
            message: e instanceof Error ? e.message : String(e),
            step: 'persist',
            retriable: false,
          };
        }
        return { state: next };
      }
    };
  }

  /**
   * ADR-0019 (e)：写成功后再检查取消。命中时把「已落库」的 commitResult 留在 state 里并返回
   * CANCELLED 错误，而不是抛出去丢掉事务结果 —— 这样命令 seam 才能报 cancelled(committed=true)。
   */
  private static withStopCheck(context: RunContext | null | undefined, next: AgentState): CaptureNodeResult {
    try {
      context?.throwIfStopped();
      return { state: next };
    } catch (e) {
      const message: string = e instanceof Error ? e.message : String(e);
      const kind: string = message.indexOf('deadline') >= 0 ? 'DEADLINE_EXCEEDED' : 'CANCELLED';
      next.error = {
        kind: kind,
        message: message,
        step: 'persist',
        retriable: false,
      };
      return { state: next };
    }
  }

  private static deriveCommitKey(input: AgentState): string {
    // 036 幂等：命令层显式 commitKey（capture-set:<setId>:<fingerprint>）优先。
    if (input.commitKey !== undefined && input.commitKey.length > 0) {
      return input.commitKey;
    }
    const candidate = input.preparedCandidate;
    if (candidate !== undefined && candidate.commitKey !== undefined && candidate.commitKey.length > 0) {
      return candidate.commitKey;
    }
    const unit = input.knowledgeUnit;
    if (unit !== undefined && unit.id.length > 0) {
      return 'capture:' + unit.id;
    }
    return 'capture:' + Date.now().toString();
  }
}
