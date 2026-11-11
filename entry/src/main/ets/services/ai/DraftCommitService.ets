/**
 * DraftCommitService.ets — 草稿确认提交（从 AiService 抽出）
 *
 * 路径: entry/src/main/ets/services/ai/DraftCommitService.ets
 * 职责: 确认草稿 = 更新检查点 → preparedCandidate 命令提交（committed 终态）→ pending 素材清理。
 *       AiService 只保留同名 facade 委托。
 * 依赖: CommandExecutor.dispatchCommand / NoteGenerationRepository / AgentMemoryService / AiServicePorts。
 *
 * 拆出原因（2026-10-31）：AiService 拆分切片 3；确认提交是独立事务边界，与采集/生成链路解耦。
 */
import { common } from '@kit.AbilityKit';
import {
  KnowledgeUnit,
  Logger,
  NoteDraftReadyEvent,
  NoteGenerationCheckpoint,
  NoteGenerationRecovery,
  NoteGenerationRepository as NoteGenerationRepositoryContract,
  NoteCommand,
  NoteOutcome,
  PreparedCandidate,
  sourceFingerprint,
} from 'common';
import { CommandExecutor, NoteDaoInterface } from 'agents';
import { AgentMemoryService } from '../AgentMemoryService';
import { NoteGenerationRepositoryFactory } from '../NoteGenerationRepositoryFactory';
import { AiServicePorts } from './AiServicePorts';

const log: Logger = new Logger('AiService');
// 首装冷启动偶发卡死兜底：确认提交最多等 120s；超时快速失败，重试按 commitKey 幂等，不会重复入库。
const CONFIRM_TIMEOUT_MS: number = 120000;

export class DraftCommitService {
  private readonly context: common.Context | undefined;
  private readonly includeUiEffects: boolean;

  constructor(context: common.Context | undefined, includeUiEffects: boolean) {
    this.context = context;
    this.includeUiEffects = includeUiEffects;
  }

  async updateDraftCheckpoint(event: NoteDraftReadyEvent, candidate: KnowledgeUnit): Promise<NoteGenerationCheckpoint> {
    const repository = await NoteGenerationRepositoryFactory.create(AiServicePorts.requireContext(this.context));
    const recovery = await repository.restore(event.runId);
    if (recovery === undefined) {
      throw new Error('草稿运行不存在');
    }
    let previous: NoteGenerationCheckpoint | undefined = undefined;
    for (const checkpoint of recovery.checkpoints) {
      if (checkpoint.id === event.checkpointId) {
        previous = checkpoint;
        break;
      }
    }
    if (previous === undefined || previous.candidateHash !== event.candidateHash) {
      throw new Error('草稿检查点已变化');
    }
    const editedHash: string = sourceFingerprint(JSON.stringify(candidate));
    // 设计修正：用户没改候选 → 直接审批 generation 检查点（不新增行，checkpointId 与草稿事件一致）。
    if (previous.candidateHash === editedHash) {
      return previous;
    }
    // 真编辑 → 新建 hash-keyed 检查点行（同一 run 换候选/重试互不覆盖）。
    const updated: NoteGenerationCheckpoint = {
      id: event.runId + ':user-edit:' + editedHash.substring(0, 8),
      runId: previous.runId,
      iteration: previous.iteration + 1,
      stage: previous.stage,
      parentId: previous.id,
      candidateHash: editedHash,
      documentJson: JSON.stringify(candidate),
      accepted: previous.accepted,
      issueCodes: previous.issueCodes,
      createdAt: previous.createdAt,
    };
    await repository.saveCheckpoint(updated);
    return updated;
  }

  async confirmDraft(event: NoteDraftReadyEvent, candidate: KnowledgeUnit): Promise<KnowledgeUnit> {
    log.info('[ConfirmTrace] step=updateCheckpoint-begin runId=' + event.runId);
    const checkpoint: NoteGenerationCheckpoint = await this.updateDraftCheckpoint(event, candidate);
    log.info('[ConfirmTrace] step=updateCheckpoint-ok');
    const repository = await NoteGenerationRepositoryFactory.create(AiServicePorts.requireContext(this.context));
    log.info('[ConfirmTrace] step=repo-ok');
    const dao: NoteDaoInterface = await AiServicePorts.buildNoteDao(AiServicePorts.requireContext(this.context), this.includeUiEffects);
    log.info('[ConfirmTrace] step=dao-ok');
    const approvedHash: string = sourceFingerprint(JSON.stringify(candidate));
    await repository.markCheckpointApproved(event.runId, checkpoint.id, approvedHash, Date.now());
    log.info('[ConfirmTrace] step=markApproved-ok');
    const prepared: PreparedCandidate = {
      runId: event.runId,
      checkpointId: checkpoint.id,
      candidateHash: approvedHash,
      candidate: candidate,
      commitKey: event.runId + ':' + checkpoint.id + ':' + sourceFingerprint(JSON.stringify(candidate)),
      sourceIds: event.sourceIds,
      pendingSourceIds: event.pendingSourceIds,
      expectedVersion: event.expectedVersion,
      updateExisting: event.result.incrementalPlan !== undefined && event.expectedVersion !== undefined,
      incrementalManifest: event.incrementalManifest,
      incrementalDiff: event.incrementalDiff,
    };
    // A3：确认提交走命令式入口，终态从 NoteOutcome 读（committed 必须带 noteId/version/commitKey）。
    const command: NoteCommand = {
      kind: 'preparedCandidate',
      operationId: 'confirm-' + event.runId,
      preparedCandidate: prepared,
      payload: { kind: 'text', text: candidate.content },
    };
    log.info('[ConfirmTrace] step=dispatch-begin');
    const writePort = await AiServicePorts.buildNoteWritePort(AiServicePorts.requireContext(this.context), this.includeUiEffects);
    log.info('[ConfirmTrace] step=writePort-ok');
    const outcome: NoteOutcome = await DraftCommitService.withConfirmTimeout(new CommandExecutor().dispatchCommand(command, {
      dao: dao,
      noteWritePort: writePort,
      generationRepository: repository,
      runEventSink: AiServicePorts.buildRunEventSinkIfReady(),
    }), CONFIRM_TIMEOUT_MS);
    log.info('[ConfirmTrace] step=dispatch-ok kind=' + outcome.kind);
    const committedUnit: KnowledgeUnit | undefined = outcome.unit;
    if (outcome.kind !== 'committed' || committedUnit === undefined) {
      const prefix: string = outcome.code === 'VERSION_CONFLICT' ? 'VERSION_CONFLICT: ' : '';
      const message: string = outcome.message !== undefined ? outcome.message : '笔记确认失败';
      throw new Error(prefix + message);
    }
    if (event.pendingSourceIds !== undefined && event.pendingSourceIds.length > 0) {
      try {
        const pendingMemoryIds: string[] = await this.resolvePendingMemoryIds(
          repository,
          event.runId,
          event.pendingSourceIds,
        );
        await new AgentMemoryService(AiServicePorts.requireContext(this.context)).markPendingMaterialsUsed(pendingMemoryIds);
      } catch (e) {
        log.warn('pending source cleanup warning runId=' + event.runId + ' count=' + event.pendingSourceIds.length.toString());
      }
    }
    return committedUnit;
  }

  /** 看门狗：确认提交超时快速失败；commitKey 幂等，用户重试不会重复入库。 */
  private static withConfirmTimeout(task: Promise<NoteOutcome>, timeoutMs: number): Promise<NoteOutcome> {
    return new Promise<NoteOutcome>((resolve: (value: NoteOutcome) => void, reject: (reason: Error) => void): void => {
      let settled: boolean = false;
      const timer: number = setTimeout((): void => {
        if (settled) {
          return;
        }
        settled = true;
        log.warn('[ConfirmTrace] confirm timeout after ' + timeoutMs.toString() + 'ms');
        reject(new Error('CONFIRM_TIMEOUT: 确认提交超时，请重试（重复提交不会重复入库）'));
      }, timeoutMs);
      task.then((value: NoteOutcome): void => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timer);
        resolve(value);
      }).catch((error: Error): void => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timer);
        reject(error);
      });
    });
  }

  private async resolvePendingMemoryIds(
    repository: NoteGenerationRepositoryContract,
    runId: string,
    referencedFragmentIds: string[],
  ): Promise<string[]> {
    const recovery: NoteGenerationRecovery | undefined = await repository.restore(runId);
    if (recovery === undefined) {
      return referencedFragmentIds.slice(0);
    }
    const result: string[] = [];
    for (const fragment of recovery.sources.fragments) {
      if (fragment.kind !== 'ocr' || !referencedFragmentIds.includes(fragment.id)) {
        continue;
      }
      const provenanceIds: string[] = fragment.provenanceIds ?? [fragment.id];
      for (const provenanceId of provenanceIds) {
        if (!result.includes(provenanceId)) { result.push(provenanceId); }
      }
    }
    return result.length > 0 ? result : referencedFragmentIds.slice(0);
  }
}
