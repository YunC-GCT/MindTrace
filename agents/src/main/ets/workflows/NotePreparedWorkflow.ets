/**
 * NotePreparedWorkflow.ets — preparedCandidate（确认后提交）的 workflow（spec 039）
 *
 * 路径: agents/src/main/ets/workflows/NotePreparedWorkflow.ets
 * 职责: preparedCandidate 命令的完整编排：校验候选指纹 / 检查点 → 幂等提交（commitKey 或端口）
 *       → 写 commit 记录与生命周期日志 → 返回 NoteOutcome 终态。
 * 依赖: common（PreparedCandidate / KnowledgeUnit / NoteOutcome / 仓储契约）、
 *       graph/CaptureGraph + truth_check/persist 节点、core/dispatch/UnitSupport、WorkflowContext。
 * 数据流: CommandExecutor.dispatchCommand() → CommandRouter.preflight(审批哈希) → resolve()=prepared
 *       → 本类 run() → commitPrepared() → CaptureGraph → NoteOutcome
 *
 * 边界: 不持有扁平 DispatchOptions；只消费 context.writePorts / context.runContext；
 *       审批拒绝由 router 前置返回（不会进到本 workflow）。
 */
import { sourceFingerprint } from 'common';
import type {
  BranchRequest,
  IncrementalDiffItem,
  KnowledgeUnit,
  NoteCommand,
  NoteGenerationCheckpoint,
  NoteGenerationCommitResult,
  NoteOutcome,
  NoteWritePort,
  PreparedCandidate,
} from 'common';
import { CaptureGraph } from '../graph/CaptureGraph';
import { AgentState, copyAgentState } from '../graph/AgentState';
import type { CaptureNodeResult, CaptureStep } from '../graph/AgentState';
import { TruthCheckNodeFactory } from '../graph/nodes/TruthCheckNode';
import { PersistNodeFactory } from '../graph/nodes/PersistNode';
import { TruthCheckService } from '../subagents/TruthCheckService';
import type { NoteDaoInterface } from '../models/NoteDaoInterface';
import { copyRegeneratedUnit, seedTextFromRequest } from '../core/dispatch/UnitSupport';
import type { NoteWorkflow, WorkflowContext } from './WorkflowContext';

export class NotePreparedWorkflow implements NoteWorkflow {
  async run(command: NoteCommand, context: WorkflowContext): Promise<NoteOutcome> {
    const prepared: PreparedCandidate | undefined = command.preparedCandidate;
    if (prepared === undefined) {
      throw new Error('PREPARED_CANDIDATE_MISSING: preparedCandidate workflow requires command.preparedCandidate');
    }
    return await this.commitPrepared(context.request, prepared, context);
  }

  private async commitPrepared(
    req: BranchRequest,
    prepared: PreparedCandidate,
    context: WorkflowContext,
  ): Promise<NoteOutcome> {
    const startedAt: number = context.startedAt;
    const operationId: string = req.operationId !== undefined ? req.operationId : 'legacy';
    const repository = context.writePorts.generationRepository;
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
    if (repository === undefined) {
      return failedOutcome('缺少草稿检查点', '');
    }
    const commitKey: string = prepared.commitKey ?? prepared.runId + ':' + prepared.checkpointId + ':' + prepared.candidateHash;
    const existingCommit: NoteGenerationCommitResult | undefined = await repository.getCommitResult(commitKey);
    if (existingCommit !== undefined && existingCommit.candidateJson !== undefined
      && existingCommit.candidateJson.length > 0) {
      const restoredCandidate: KnowledgeUnit = JSON.parse(existingCommit.candidateJson) as KnowledgeUnit;
      // Re-saving an idempotent commit also heals a stale ready-preview run left
      // by a process interruption between the durable note commit and run update.
      await repository.saveCommitResult(existingCommit);
      await repository.appendLifecycleLog({
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
    const recovery = await repository.restore(prepared.runId);
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
    const graph: CaptureGraph = this.buildGraph(context.writePorts.dao, context.writePorts.noteWritePort);
    const finalState: AgentState = await graph.run(initial, context.runContext);
    if (finalState.error !== undefined) {
      const conflict: boolean = finalState.error.message.indexOf('VERSION_CONFLICT') >= 0;
      return failedOutcome(finalState.error.message, conflict ? 'VERSION_CONFLICT' : '');
    }
    let committedCandidate: KnowledgeUnit = prepared.candidate;
    if (finalState.commitResult !== undefined) {
      const duplicateCommit: boolean = finalState.commitResult.duplicate === true;
      committedCandidate = copyRegeneratedUnit(prepared.candidate, prepared.candidate.content);
      committedCandidate.version = finalState.commitResult.version;
      // 判重命中时端口返回的是已有笔记 id；不能再用候选 id 覆盖，否则上层
      // 无法判断「已复用」，A2A / UI 的重复提示都会失效。
      if (duplicateCommit) {
        committedCandidate.id = finalState.commitResult.noteId;
      }
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
      await repository.saveCommitResult(commit);
      await repository.appendLifecycleLog({
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

  private buildGraph(dao?: NoteDaoInterface, noteWritePort?: NoteWritePort): CaptureGraph {
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
