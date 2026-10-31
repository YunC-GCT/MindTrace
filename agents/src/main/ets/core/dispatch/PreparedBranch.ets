/**
 * PreparedBranch.ets — preparedCandidate 确认提交分支（从 Dispatcher.ets 抽出）
 *
 * 路径: agents/src/main/ets/core/dispatch/PreparedBranch.ets
 * 职责: 校验候选指纹 / 检查点 → 幂等提交（commitKey 或端口）→ 写 commit 记录与生命周期日志 → 返回 DispatchResult。
 * 依赖: CaptureGraph（truth_check + persist）、PreparedCandidate / generationRepository 契约。
 *
 * 边界:
 *   - 只负责「已确认候选的提交」；路由、运行上下文与结果外壳由 Dispatcher 负责。
 *   - 写路径：注入 NoteWritePort 时走端口（切片 A2），否则 legacy DAO。
 *   - 幂等：先查 commitKey 已有记录，命中直接返回首次候选（并补写生命周期日志）。
 */
import {
  sourceFingerprint,
} from 'common';
import type {
  BranchRequest,
  IncrementalDiffItem,
  KnowledgeUnit,
  NoteGenerationCheckpoint,
  NoteGenerationCommitResult,
  NoteWritePort,
  PreparedCandidate,
  RunContext,
} from 'common';
import { CaptureGraph } from '../../graph/CaptureGraph';
import { AgentState, copyAgentState } from '../../graph/AgentState';
import type { CaptureNodeResult, CaptureStep } from '../../graph/AgentState';
import { TruthCheckNodeFactory } from '../../graph/nodes/TruthCheckNode';
import { PersistNodeFactory } from '../../graph/nodes/PersistNode';
import { TruthCheckService } from '../../agents/TruthCheckService';
import type { NoteDaoInterface } from '../../models/NoteDaoInterface';
import type { DispatchOptions } from './DispatchOptions';
import type { NoteOutcome } from 'common';
import { copyRegeneratedUnit, seedTextFromRequest } from './UnitSupport';

export class PreparedBranch {
  static async dispatch(
    req: BranchRequest,
    prepared: PreparedCandidate,
    options: DispatchOptions,
    startedAt: number,
    runContext: RunContext,
  ): Promise<NoteOutcome> {
    const operationId: string = req.operationId !== undefined ? req.operationId : 'legacy';
    const failedOutcome = (message: string, code: string): NoteOutcome => {
      const outcome: NoteOutcome = {
        kind: 'failed', operationId: operationId, route: 'D1',
        durationMs: Date.now() - startedAt, code: code, message: message,
      };
      return outcome;
    };
    const actualHash: string = sourceFingerprint(JSON.stringify(prepared.candidate));
    if (actualHash !== prepared.candidateHash) {
      return failedOutcome('候选内容已变化', '');
    }
    if (options.generationRepository === undefined) {
      return failedOutcome('缺少草稿检查点', '');
    }
    const commitKey: string = prepared.commitKey ?? prepared.runId + ':' + prepared.checkpointId + ':' + prepared.candidateHash;
    const existingCommit: NoteGenerationCommitResult | undefined =
      await options.generationRepository.getCommitResult(commitKey);
    if (existingCommit !== undefined && existingCommit.candidateJson !== undefined
      && existingCommit.candidateJson.length > 0) {
      const restoredCandidate: KnowledgeUnit = JSON.parse(existingCommit.candidateJson) as KnowledgeUnit;
      // Re-saving an idempotent commit also heals a stale ready-preview run left
      // by a process interruption between the durable note commit and run update.
      await options.generationRepository.saveCommitResult(existingCommit);
      await options.generationRepository.appendLifecycleLog({
        runId: prepared.runId,
        event: 'duplicate-confirm',
        checkpointId: prepared.checkpointId,
        sourceCount: prepared.pendingSourceIds?.length ?? 0,
      });
      const duplicate: NoteOutcome = {
        kind: 'committed', operationId: operationId, route: 'D1',
        durationMs: Date.now() - startedAt, noteId: restoredCandidate.id,
        version: restoredCandidate.version, commitKey: commitKey, unit: restoredCandidate,
      };
      return duplicate;
    }
    const recovery = await options.generationRepository.restore(prepared.runId);
    if (recovery === undefined) {
      return failedOutcome('草稿运行不存在', '');
    }
    let checkpoint: NoteGenerationCheckpoint | undefined = undefined;
    for (const item of recovery.checkpoints) {
      if (item.id === prepared.checkpointId) {
        checkpoint = item;
        break;
      }
    }
    if (checkpoint === undefined || checkpoint.runId !== prepared.runId
      || checkpoint.candidateHash !== prepared.candidateHash) {
      return failedOutcome('草稿检查点不匹配', '');
    }
    const initial: AgentState = {
      captureText: seedTextFromRequest(req),
      source: 'note_generation',
      payload: req.payload,
      currentStep: 'START',
      persist: true,
      analysisOnly: false,
      preparedCandidate: prepared,
      knowledgeUnit: prepared.candidate,
    };
    const graph: CaptureGraph = PreparedBranch.buildGraph(options.dao, options.noteWritePort);
    const finalState: AgentState = await graph.run(initial, runContext);
    if (finalState.error !== undefined) {
      const conflict: boolean = finalState.error.message.indexOf('VERSION_CONFLICT') >= 0;
      return failedOutcome(finalState.error.message, conflict ? 'VERSION_CONFLICT' : '');
    }
    let committedCandidate: KnowledgeUnit = prepared.candidate;
    if (finalState.commitResult !== undefined) {
      committedCandidate = copyRegeneratedUnit(prepared.candidate, prepared.candidate.content);
      committedCandidate.version = finalState.commitResult.version;
      const contentChanged: boolean = prepared.incrementalDiff?.some(
        (item: IncrementalDiffItem): boolean => item.kind === 'changed' || item.kind === 'added',
      ) === true;
      if (prepared.updateExisting === true && contentChanged) {
        committedCandidate.embedding = [];
      }
      const commit: NoteGenerationCommitResult = {
        commitKey: commitKey,
        runId: prepared.runId,
        checkpointId: prepared.checkpointId,
        noteId: finalState.commitResult.noteId,
        version: finalState.commitResult.version,
        sourceIds: prepared.pendingSourceIds ?? prepared.sourceIds ?? [],
        candidateJson: JSON.stringify(committedCandidate),
        committedAt: Date.now(),
      };
      await options.generationRepository.saveCommitResult(commit);
      await options.generationRepository.appendLifecycleLog({
        runId: prepared.runId,
        event: finalState.commitResult.duplicate ? 'duplicate-confirm' : 'committed',
        checkpointId: prepared.checkpointId,
        sourceCount: commit.sourceIds.length,
      });
    }
    const committed: NoteOutcome = {
      kind: 'committed', operationId: operationId, route: 'D1',
      durationMs: Date.now() - startedAt, noteId: committedCandidate.id,
      version: committedCandidate.version, commitKey: commitKey, unit: committedCandidate,
    };
    return committed;
  }

  static buildGraph(dao?: NoteDaoInterface, noteWritePort?: NoteWritePort): CaptureGraph {
    const graph: CaptureGraph = new CaptureGraph();
    const truth: TruthCheckService = new TruthCheckService();
    graph.addNode('truth_check', TruthCheckNodeFactory.create(truth));
    if (noteWritePort !== undefined) {
      // #238 链路迁移 A2：preparedCandidate 的持久化也走端口（commitKey / CAS / 结构化错误）。
      graph.addNode('persist', PersistNodeFactory.createWithWritePort(noteWritePort));
    } else if (dao !== undefined) {
      graph.addNode('persist', PersistNodeFactory.create(dao));
    } else {
      graph.addNode('persist', async (input: AgentState): Promise<CaptureNodeResult> => {
        const next: AgentState = copyAgentState(input);
        next.error = {
          kind: 'PERSIST_DAO_REQUIRED',
          message: 'persist requested but no NoteDaoInterface was provided',
          step: 'persist',
          retriable: false,
        };
        const result: CaptureNodeResult = { state: next };
        return result;
      });
    }
    graph.addEdge('START', 'truth_check');
    graph.addConditionalEdge('truth_check', (input: AgentState): CaptureStep => input.persist ? 'persist' : 'END');
    graph.addEdge('persist', 'END');
    return graph;
  }
}
