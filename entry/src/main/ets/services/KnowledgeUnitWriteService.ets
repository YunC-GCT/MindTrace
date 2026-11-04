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
import { NoteFtsIndex } from '../database/NoteFtsIndex';
import { AsyncMutex } from './AsyncMutex';
import {
  KnowledgeUnitPersistenceResult,
  KnowledgeUnitPostCommitEffect,
  KnowledgeUnitWriteError,
  KnowledgeUnitWriteErrorCode,
  KnowledgeUnitWriteRepository,
  KnowledgeUnitWriteResult,
} from 'common';
import { WritePathValidator } from 'agents/src/main/ets/note/Index';

// 首装冷启动偶发卡死兜底：索引同步/副作用最多等 5s，超时降级为告警，不阻塞主写链路。
const INDEX_SYNC_TIMEOUT_MS: number = 5000;
const POST_COMMIT_EFFECT_TIMEOUT_MS: number = 5000;

export class KnowledgeUnitWriteService {
  /** 全局写区：索引同步 + post-commit effects 串行（S0 并发实验：并发 post-commit 会卡死）。 */
  private static readonly writeSection: AsyncMutex = new AsyncMutex();
  private repository: KnowledgeUnitWriteRepository;
  private effects: KnowledgeUnitPostCommitEffect[];

  constructor(repository: KnowledgeUnitWriteRepository, effects: KnowledgeUnitPostCommitEffect[]) {
    this.repository = repository;
    this.effects = effects;
  }

  async create(unit: KnowledgeUnit, generationMetadata: string = ''): Promise<KnowledgeUnitWriteResult> {
    WritePathValidator.validateKnowledgeUnit(unit);
    const duplicate: KnowledgeUnit | null = await this.findDuplicate(unit);
    if (duplicate !== null) {
      return {
        committed: true,
        rowId: 0,
        unit: duplicate,
        warnings: ['DUPLICATE_SKIPPED'],
        duplicate: true,
      };
    }
    const persisted: KnowledgeUnitPersistenceResult =
      await this.repository.createWithRevision(unit, generationMetadata);
    const warnings: string[] = await this.finalizeWrite(persisted.unit, true);
    const result: KnowledgeUnitWriteResult = {
      committed: true,
      rowId: persisted.rowId,
      unit: persisted.unit,
      warnings: warnings,
    };
    return result;
  }

  /** 读取当前单元（幂等复用/回执需要 title/subject）；仓库未实现时返回 null。 */
  async queryById(id: string): Promise<KnowledgeUnit | null> {
    if (this.repository.queryById === undefined) {
      return null;
    }
    return await this.repository.queryById(id);
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
      const warnings: string[] = await this.finalizeWrite(persisted.unit, false);
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
      if (e instanceof KnowledgeUnitWriteError) {
        throw new KnowledgeUnitWriteError(e.code, e.message);
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
    const duplicate: KnowledgeUnit | null = await this.findDuplicate(unit);
    if (duplicate !== null) {
      return {
        committed: true,
        rowId: 0,
        unit: duplicate,
        warnings: ['DUPLICATE_SKIPPED'],
        duplicate: true,
      };
    }
    console.info('[ConfirmTrace] service=createWithCommitKey-begin');
    const persisted: KnowledgeUnitPersistenceResult = await this.repository.createWithRevisionAndCommitKey(
      unit,
      generationMetadata,
      commit,
    );
    console.info('[ConfirmTrace] service=createWithCommitKey-ok');
    const warnings: string[] = await this.finalizeWrite(
      persisted.unit, persisted.duplicate !== true, persisted.duplicate !== true);
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
      console.info('[ConfirmTrace] service=updateWithCommitKey-begin');
      const persisted: KnowledgeUnitPersistenceResult = await this.repository.updateWithRevisionAndCommitKey(
        unit,
        expectedVersion,
        generationMetadata,
        commit,
      );
      console.info('[ConfirmTrace] service=updateWithCommitKey-ok');
      const warnings: string[] = await this.finalizeWrite(persisted.unit, false);
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
      if (e instanceof KnowledgeUnitWriteError) {
        throw new KnowledgeUnitWriteError(e.code, e.message);
      }
      if (e instanceof Error) {
        throw new Error(e.message);
      }
      throw new Error(String(e));
    }
  }

  /** 写前查重：同一道题重复整理时复用已有笔记（不新增行、不刷索引）。 */
  private async findDuplicate(unit: KnowledgeUnit): Promise<KnowledgeUnit | null> {
    if (this.repository.findDuplicate === undefined) {
      return null;
    }
    try {
      return await this.repository.findDuplicate(unit);
    } catch (e) {
      return null;
    }
  }

  /** 写区串行段：索引同步（可选）+ post-commit effects（并发时会卡死，必须互斥）。 */
  private async finalizeWrite(unit: KnowledgeUnit, isCreate: boolean,
    syncIndex: boolean = true): Promise<string[]> {
    return await KnowledgeUnitWriteService.writeSection.runExclusive(async (): Promise<string[]> => {
      if (syncIndex) {
        await this.syncIndex(unit);
      }
      return await this.runPostCommit(unit, isCreate);
    });
  }

  /** 索引同步（尽力而为 + 超时兜底）：检索索引失败绝不影响笔记写入结果。 */
  private async syncIndex(unit: KnowledgeUnit): Promise<void> {
    console.info('[ConfirmTrace] index-sync-begin');
    try {
      await KnowledgeUnitWriteService.withTimeout(
        NoteFtsIndex.upsert(unit), INDEX_SYNC_TIMEOUT_MS, 'note-index');
      console.info('[ConfirmTrace] index-sync-ok');
    } catch (e) {
      console.warn('[KnowledgeUnitWriteService] index sync skipped: ' + (e as Error).message);
    }
  }

  /** Promise.race 超时兜底：只用于「可降级」的附加动作（索引/UI 副作用），不改变事务结果。 */
  private static async withTimeout(task: Promise<void>, timeoutMs: number, label: string): Promise<void> {
    let timer: number = 0;
    const timeout: Promise<void> = new Promise<void>((resolve: () => void): void => {
      timer = setTimeout((): void => {
        console.warn('[KnowledgeUnitWriteService] timeout after ' + timeoutMs.toString() + 'ms: ' + label);
        resolve();
      }, timeoutMs);
    });
    try {
      await Promise.race([task, timeout]);
    } finally {
      clearTimeout(timer);
    }
  }

  private async runPostCommit(unit: KnowledgeUnit, isCreate: boolean): Promise<string[]> {
    const warnings: string[] = [];
    for (const effect of this.effects) {
      if (effect.createOnly === true && !isCreate) {
        continue;
      }
      const effectStartedAt: number = Date.now();
      try {
        await KnowledgeUnitWriteService.withTimeout(
          effect.run(unit), POST_COMMIT_EFFECT_TIMEOUT_MS, 'post-commit effect ' + effect.name);
        console.info('[EffectTrace] name=' + effect.name + ' ok ms=' + (Date.now() - effectStartedAt).toString());
      } catch (e) {
        const message: string = e instanceof Error ? e.message : String(e);
        warnings.push(effect.name + ': ' + message);
      }
    }
    return warnings;
  }
}
