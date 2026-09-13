/**
 * KnowledgeUnitWriteModels.ets — KnowledgeUnit 写入契约
 *
 * 路径: entry/src/main/ets/models/KnowledgeUnitWriteModels.ets
 * 职责: 定义事务仓储、revision、写入结果和写后副作用边界
 * 依赖: common KnowledgeUnit
 *
 * 数据流:
 *   写入调用方 → KnowledgeUnitWriteService → repository / post-commit effects
 */
import { KnowledgeUnit, NoteGenerationCommitResult } from 'common';

export enum KnowledgeUnitWriteErrorCode {
  VERSION_CONFLICT = 'VERSION_CONFLICT',
}

export interface KnowledgeUnitRevision {
  noteId: string;
  version: number;
  unit: KnowledgeUnit;
  generationMetadata: string;
  revisedAt: number;
}

export interface KnowledgeUnitPersistenceResult {
  rowId: number;
  unit: KnowledgeUnit;
  duplicate?: boolean;
}

export interface KnowledgeUnitWriteResult {
  committed: boolean;
  rowId: number;
  unit: KnowledgeUnit;
  warnings: string[];
  errorCode?: KnowledgeUnitWriteErrorCode;
  errorMessage?: string;
  duplicate?: boolean;
}

export interface KnowledgeUnitWriteRepository {
  createWithRevision(unit: KnowledgeUnit, generationMetadata: string): Promise<KnowledgeUnitPersistenceResult>;
  updateWithRevision(
    unit: KnowledgeUnit,
    expectedVersion: number,
    generationMetadata: string,
  ): Promise<KnowledgeUnitPersistenceResult>;
  createWithRevisionAndCommitKey?(
    unit: KnowledgeUnit,
    generationMetadata: string,
    commit: NoteGenerationCommitResult,
  ): Promise<KnowledgeUnitPersistenceResult>;
  updateWithRevisionAndCommitKey?(
    unit: KnowledgeUnit,
    expectedVersion: number,
    generationMetadata: string,
    commit: NoteGenerationCommitResult,
  ): Promise<KnowledgeUnitPersistenceResult>;
}

export interface NoteGenerationBaseProvider {
  queryCurrentUnit(noteId: string): Promise<KnowledgeUnit | null>;
  queryLatestRevision(noteId: string): Promise<KnowledgeUnitRevision | null>;
  queryLatestGeneratedRevision?(noteId: string): Promise<KnowledgeUnitRevision | null>;
}

export interface KnowledgeUnitPostCommitEffect {
  name: string;
  run(unit: KnowledgeUnit): Promise<void>;
}

export class KnowledgeUnitWriteError extends Error {
  code: KnowledgeUnitWriteErrorCode;

  constructor(code: KnowledgeUnitWriteErrorCode, message: string) {
    super(message);
    this.code = code;
  }
}
