/**
 * KnowledgeUnitWriteService.ets — KnowledgeUnit 统一写入协调服务
 *
 * 路径: entry/src/main/ets/services/KnowledgeUnitWriteService.ets
 * 职责: 协调事务写入、乐观锁冲突和提交后可恢复警告
 * 依赖: KnowledgeUnitWriteModels, WritePathValidator
 *
 * 数据流:
 *   manual / AI adapter → create / update → repository commit → post-commit effects
 */
import { KnowledgeUnit, NoteGenerationCommitResult } from 'common';
import {
  KnowledgeUnitPersistenceResult,
  KnowledgeUnitPostCommitEffect,
  KnowledgeUnitWriteError,
  KnowledgeUnitWriteErrorCode,
  KnowledgeUnitWriteRepository,
  KnowledgeUnitWriteResult,
} from '../models/KnowledgeUnitWriteModels';
import { WritePathValidator } from './WritePathValidator';

export class KnowledgeUnitWriteService {
  private repository: KnowledgeUnitWriteRepository;
  private effects: KnowledgeUnitPostCommitEffect[];

  constructor(repository: KnowledgeUnitWriteRepository, effects: KnowledgeUnitPostCommitEffect[]) {
    this.repository = repository;
    this.effects = effects;
  }

  async create(unit: KnowledgeUnit, generationMetadata: string = ''): Promise<KnowledgeUnitWriteResult> {
    WritePathValidator.validateKnowledgeUnit(unit);
    const persisted: KnowledgeUnitPersistenceResult =
      await this.repository.createWithRevision(unit, generationMetadata);
    const warnings: string[] = await this.runPostCommit(persisted.unit);
    const result: KnowledgeUnitWriteResult = {
      committed: true,
      rowId: persisted.rowId,
      unit: persisted.unit,
      warnings: warnings,
    };
    return result;
  }

  async update(
    unit: KnowledgeUnit,
    expectedVersion: number,
    generationMetadata: string = '',
  ): Promise<KnowledgeUnitWriteResult> {
    WritePathValidator.validateKnowledgeUnit(unit);
    try {
      const persisted: KnowledgeUnitPersistenceResult =
        await this.repository.updateWithRevision(unit, expectedVersion, generationMetadata);
      const warnings: string[] = await this.runPostCommit(persisted.unit);
      const result: KnowledgeUnitWriteResult = {
        committed: true,
        rowId: persisted.rowId,
        unit: persisted.unit,
        warnings: warnings,
      };
      return result;
    } catch (e) {
      if (e instanceof KnowledgeUnitWriteError && e.code === KnowledgeUnitWriteErrorCode.VERSION_CONFLICT) {
        const conflict: KnowledgeUnitWriteResult = {
          committed: false,
          rowId: 0,
          unit: unit,
          warnings: [],
          errorCode: KnowledgeUnitWriteErrorCode.VERSION_CONFLICT,
          errorMessage: e.message,
        };
        return conflict;
      }
      if (e instanceof Error) {
        throw new Error(e.message);
      }
      throw new Error(String(e));
    }
  }

  async createWithCommitKey(
    unit: KnowledgeUnit,
    generationMetadata: string,
    commit: NoteGenerationCommitResult,
  ): Promise<KnowledgeUnitWriteResult> {
    WritePathValidator.validateKnowledgeUnit(unit);
    if (this.repository.createWithRevisionAndCommitKey === undefined) {
      return await this.create(unit, generationMetadata);
    }
    const persisted: KnowledgeUnitPersistenceResult = await this.repository.createWithRevisionAndCommitKey(
      unit,
      generationMetadata,
      commit,
    );
    const warnings: string[] = await this.runPostCommit(persisted.unit);
    return {
      committed: true,
      rowId: persisted.rowId,
      unit: persisted.unit,
      warnings: warnings,
      duplicate: persisted.duplicate === true,
    };
  }

  async updateWithCommitKey(
    unit: KnowledgeUnit,
    expectedVersion: number,
    generationMetadata: string,
    commit: NoteGenerationCommitResult,
  ): Promise<KnowledgeUnitWriteResult> {
    WritePathValidator.validateKnowledgeUnit(unit);
    if (this.repository.updateWithRevisionAndCommitKey === undefined) {
      return await this.update(unit, expectedVersion, generationMetadata);
    }
    try {
      const persisted: KnowledgeUnitPersistenceResult = await this.repository.updateWithRevisionAndCommitKey(
        unit,
        expectedVersion,
        generationMetadata,
        commit,
      );
      const warnings: string[] = await this.runPostCommit(persisted.unit);
      return {
        committed: true,
        rowId: persisted.rowId,
        unit: persisted.unit,
        warnings: warnings,
        duplicate: persisted.duplicate === true,
      };
    } catch (e) {
      if (e instanceof KnowledgeUnitWriteError && e.code === KnowledgeUnitWriteErrorCode.VERSION_CONFLICT) {
        return {
          committed: false,
          rowId: 0,
          unit: unit,
          warnings: [],
          errorCode: KnowledgeUnitWriteErrorCode.VERSION_CONFLICT,
          errorMessage: e.message,
        };
      }
      if (e instanceof Error) {
        throw new Error(e.message);
      }
      throw new Error(String(e));
    }
  }

  private async runPostCommit(unit: KnowledgeUnit): Promise<string[]> {
    const warnings: string[] = [];
    for (const effect of this.effects) {
      try {
        await effect.run(unit);
      } catch (e) {
        const message: string = e instanceof Error ? e.message : String(e);
        warnings.push(effect.name + ': ' + message);
      }
    }
    return warnings;
  }
}
