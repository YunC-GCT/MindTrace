/**
 * NoteWriteStoreDao.ets — NoteWriteStore 的生产实现（NoteDao + generation commit 表）
 *
 * 路径: entry/src/main/ets/database/NoteWriteStoreDao.ets
 * 职责: 把 NoteWriteStore 的四个方法落到真实 RDB：commitKey 查 note_generation_commit、
 *       版本查 knowledge_unit、写入走 NoteDao 的带 commitKey 事务方法。
 * 依赖: NoteDao / NoteGenerationRepository / 写模型错误类型 / common 的 uuid。
 *
 * 数据流:
 *   NoteWritePortAdapter → queryCommit / querySnapshot → RDB 读
 *   NoteWritePortAdapter → insert / update → NoteDao 事务（knowledge_unit + note_revision + commit 记录）
 *
 * 要点:
 *   - insert 分支在 unit.id 为空时**必须**生成 id：NoteDao.toBucket 原样存 id，空串会落地成空主键。
 *   - 新 note 的版本归一到 1（调用方传 0 也不允许落 0）。
 *   - 事务内发现重放（DAO 返回 duplicate=true）时回填 duplicate / committedAt，端口据此报告竞态。
 *   - DAO 的 VERSION_CONFLICT 原样映射成 NotePortError 且 retryable=false，不得压成可重试错误。
 *
 * 已知缺口（需单开迁移票，不在本切片伪造）:
 *   - approvedCheckpointHash 目前没有任何持久化列/记录；querySnapshot 只能返回 noteId / version。
 *     因此带审批哈希的写入会被端口层判成 APPROVAL_HASH_MISMATCH —— 这是安全默认（宁可拒绝），
 *     要放行必须先决定哈希存哪（note 行加列 / commit 记录加字段）并写迁移与回滚。
 */
import { NotePortError, NOTE_WRITE_ERROR_FAILED, uuid } from 'common';
import type {
  KnowledgeUnit,
  NoteGenerationCommitResult,
  NoteWriteCommand,
  NoteWriteSnapshot,
  NoteWriteStore,
} from 'common';
import { KnowledgeUnitWriteError, KnowledgeUnitWriteErrorCode } from '../models/KnowledgeUnitWriteModels';
import type { KnowledgeUnitPersistenceResult } from '../models/KnowledgeUnitWriteModels';
import type { NoteDao } from './NoteDao';
import type { NoteGenerationRepository } from './NoteGenerationRepository';

const WRITE_PORT_RUN_ID: string = 'note-write-port';

export class NoteWriteStoreDao implements NoteWriteStore {
  private readonly dao: NoteDao;
  private readonly repository: NoteGenerationRepository;

  constructor(dao: NoteDao, repository: NoteGenerationRepository) {
    this.dao = dao;
    this.repository = repository;
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
    if (commit.committedAt !== undefined) {
      snapshot.committedAt = commit.committedAt;
    }
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
    if (unit.id.length === 0) {
      unit.id = uuid();
    }
    if (unit.version <= 0) {
      unit.version = 1;
    }
    const commit: NoteGenerationCommitResult = NoteWriteStoreDao.buildCommit(unit, command, unit.version);
    try {
      const result: KnowledgeUnitPersistenceResult = await this.dao.createWithRevisionAndCommitKey(unit, '', commit);
      return NoteWriteStoreDao.toSnapshot(result, command.commitKey, commit);
    } catch (e) {
      if (e instanceof KnowledgeUnitWriteError) {
        const writeError: KnowledgeUnitWriteError = e as KnowledgeUnitWriteError;
        const retryable: boolean = writeError.code !== KnowledgeUnitWriteErrorCode.VERSION_CONFLICT;
        throw new NotePortError(writeError.code, writeError.message, retryable);
      }
      const message: string = e instanceof Error ? e.message : String(e);
      throw new NotePortError(NOTE_WRITE_ERROR_FAILED, message, true);
    }
  }

  async update(unit: KnowledgeUnit, expectedVersion: number, command: NoteWriteCommand): Promise<NoteWriteSnapshot> {
    const commit: NoteGenerationCommitResult = NoteWriteStoreDao.buildCommit(unit, command, expectedVersion + 1);
    try {
      const result: KnowledgeUnitPersistenceResult =
        await this.dao.updateWithRevisionAndCommitKey(unit, expectedVersion, '', commit);
      return NoteWriteStoreDao.toSnapshot(result, command.commitKey, commit);
    } catch (e) {
      if (e instanceof KnowledgeUnitWriteError) {
        const writeError: KnowledgeUnitWriteError = e as KnowledgeUnitWriteError;
        const retryable: boolean = writeError.code !== KnowledgeUnitWriteErrorCode.VERSION_CONFLICT;
        throw new NotePortError(writeError.code, writeError.message, retryable);
      }
      const message: string = e instanceof Error ? e.message : String(e);
      throw new NotePortError(NOTE_WRITE_ERROR_FAILED, message, true);
    }
  }

  private static toSnapshot(result: KnowledgeUnitPersistenceResult, commitKey: string,
    commit: NoteGenerationCommitResult): NoteWriteSnapshot {
    const snapshot: NoteWriteSnapshot = {
      noteId: result.unit.id,
      version: result.unit.version,
      commitKey: commitKey,
    };
    if (result.duplicate === true) {
      snapshot.duplicate = true;
    }
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

  // VERSION_CONFLICT 是「重读后再提交」类错误，必须保持 retryable=false；其余归为可重试。
}
