/**
 * KnowledgeUnitNoteWriteStore.ets — NoteWriteStore 的生产实现（走 KnowledgeUnitWriteService）
 *
 * 路径: entry/src/main/ets/database/KnowledgeUnitNoteWriteStore.ets
 * 职责: 让端口写入复用既有写服务：事务写入 + post-commit effects（卡片刷新/关系边）都保留；
 *       commitKey 查询走 NoteGenerationRepository，版本快照走 NoteDao。
 * 依赖: KnowledgeUnitWriteService（写）、NoteGenerationRepository（commit 查询）、NoteDao（快照）。
 *
 * 数据流:
 *   PersistNode → NoteWritePortAdapter → 本类 → KnowledgeUnitWriteService → NoteDao 事务 + post-commit
 *
 * 为什么不用 NoteWriteStoreDao：
 *   NoteWriteStoreDao 直接吃 NoteDao，会绕过 KnowledgeUnitWriteService 的 post-commit effects；
 *   端口接入链路（A1）必须行为等价，所以生产实现走写服务，DAO 版只用于契约测试。
 *
 * 已知缺口：approvedCheckpointHash 没有持久化列，querySnapshot 只能返回 noteId / version。
 */
import { Logger, NotePortError } from 'common';
import type {
  KnowledgeUnit,
  NoteGenerationCommitResult,
  NoteWriteSnapshot,
  NoteWriteCommand,
  NoteWriteStore,
} from 'common';
import type { KnowledgeUnitWriteResult } from '../models/KnowledgeUnitWriteModels';
import type { KnowledgeUnitWriteService } from '../services/KnowledgeUnitWriteService';
import type { NoteDao } from './NoteDao';
import type { NoteGenerationRepository } from './NoteGenerationRepository';

const WRITE_PORT_RUN_ID: string = 'note-write-port';
const log: Logger = new Logger('KnowledgeUnitNoteWriteStore');

export class KnowledgeUnitNoteWriteStore implements NoteWriteStore {
  private readonly service: KnowledgeUnitWriteService;
  private readonly repository: NoteGenerationRepository;
  private readonly dao: NoteDao;

  constructor(service: KnowledgeUnitWriteService, repository: NoteGenerationRepository, dao: NoteDao) {
    this.service = service;
    this.repository = repository;
    this.dao = dao;
  }

  async queryCommit(commitKey: string): Promise<NoteWriteSnapshot | null> {
    const commit: NoteGenerationCommitResult | undefined = await this.repository.getCommitResult(commitKey);
    if (commit === undefined) {
      return null;
    }
    const snapshot: NoteWriteSnapshot = {
      noteId: commit.noteId,
      version: commit.version,
      commitKey: commit.commitKey,
    };
    return snapshot;
  }

  async querySnapshot(noteId: string): Promise<NoteWriteSnapshot | null> {
    const unit: KnowledgeUnit | null = await this.dao.queryById(noteId);
    if (unit === null) {
      return null;
    }
    const snapshot: NoteWriteSnapshot = { noteId: unit.id, version: unit.version };
    return snapshot;
  }

  async insert(unit: KnowledgeUnit, command: NoteWriteCommand): Promise<NoteWriteSnapshot> {
    await this.validateApproval(command);
    const commit: NoteGenerationCommitResult = KnowledgeUnitNoteWriteStore.buildCommit(unit, command, unit.version);
    const metadata: string = command.generationMetadata !== undefined ? command.generationMetadata : '';
    log.info('[ConfirmTrace] store=insert-begin noteId=' + unit.id);
    const result: KnowledgeUnitWriteResult = await this.service.createWithCommitKey(unit, metadata, commit);
    log.info('[ConfirmTrace] store=insert-ok');
    return KnowledgeUnitNoteWriteStore.toSnapshot(result, command.commitKey, commit);
  }

  async update(unit: KnowledgeUnit, expectedVersion: number, command: NoteWriteCommand): Promise<NoteWriteSnapshot> {
    await this.validateApproval(command);
    const commit: NoteGenerationCommitResult = KnowledgeUnitNoteWriteStore.buildCommit(unit, command, expectedVersion + 1);
    const metadata: string = command.generationMetadata !== undefined ? command.generationMetadata : '';
    log.info('[ConfirmTrace] store=update-begin noteId=' + unit.id);
    const result: KnowledgeUnitWriteResult =
      await this.service.updateWithCommitKey(unit, expectedVersion, metadata, commit);
    log.info('[ConfirmTrace] store=update-ok');
    if (result.committed !== true) {
      // 写服务把版本冲突作为结果返回，不抛错；端口层必须还原成结构化错误。
      const code: string = result.errorCode !== undefined ? result.errorCode : 'NOTE_WRITE_FAILED';
      const retryable: boolean = code !== 'VERSION_CONFLICT';
      throw new NotePortError(code, result.errorMessage !== undefined ? result.errorMessage : code, retryable);
    }
    return KnowledgeUnitNoteWriteStore.toSnapshot(result, command.commitKey, commit);
  }

  /** v18：命令携带审批哈希时，要求对应检查点已审批且 candidate_hash 一致。 */
  private async validateApproval(command: NoteWriteCommand): Promise<void> {
    const hash: string | undefined = command.approvedCheckpointHash;
    if (hash === undefined || hash.length === 0) {
      return;
    }
    const runId: string = command.runId !== undefined ? command.runId : '';
    const checkpointId: string = command.checkpointId !== undefined ? command.checkpointId : '';
    if (runId.length === 0 || checkpointId.length === 0) {
      throw new NotePortError('APPROVAL_HASH_MISMATCH', '审批哈希缺少运行/检查点标识', false);
    }
    const checkpoint = await this.repository.getCheckpoint(runId, checkpointId);
    const approvedAt: number = checkpoint !== null && checkpoint.approvedAt !== undefined ? checkpoint.approvedAt : 0;
    if (checkpoint === null || approvedAt <= 0 || checkpoint.candidateHash !== hash) {
      log.warn('approval mismatch runId=' + runId + ' checkpointId=' + checkpointId
        + ' approvedAt=' + approvedAt.toString()
        + ' rowHash=' + (checkpoint !== null ? checkpoint.candidateHash.substring(0, 12) : 'none')
        + ' cmdHash=' + hash.substring(0, 12));
      throw new NotePortError('APPROVAL_HASH_MISMATCH', '候选内容已变化或检查点未批准', false);
    }
  }

  private static toSnapshot(result: KnowledgeUnitWriteResult, commitKey: string,
    commit: NoteGenerationCommitResult): NoteWriteSnapshot {
    const snapshot: NoteWriteSnapshot = {
      noteId: result.unit.id,
      version: result.unit.version,
      commitKey: commitKey,
      duplicate: result.duplicate === true,
    };
    if (commit.committedAt !== undefined) {
      snapshot.committedAt = commit.committedAt;
    }
    return snapshot;
  }

  private static buildCommit(unit: KnowledgeUnit, command: NoteWriteCommand,
    version: number): NoteGenerationCommitResult {
    const commit: NoteGenerationCommitResult = {
      commitKey: command.commitKey,
      runId: command.runId !== undefined && command.runId.length > 0 ? command.runId : WRITE_PORT_RUN_ID,
      checkpointId: command.checkpointId ?? '',
      noteId: unit.id,
      version: version,
      sourceIds: command.sourceIds ?? [],
      candidateJson: JSON.stringify(unit),
      committedAt: Date.now(),
    };
    if (command.generationMetadata !== undefined) {
      commit.generationMetadata = command.generationMetadata;
    }
    return commit;
  }
}
