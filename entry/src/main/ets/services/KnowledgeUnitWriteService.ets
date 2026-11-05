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
import type { NoteSimilarityCandidate, NoteSimilarityJudgePort } from 'common';
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
import {
  SIMILARITY_GRAY_MIN,
  SIMILARITY_HARD_DUPLICATE,
  similarityScore,
} from 'agents/src/main/ets/note/Index';

// 首装冷启动偶发卡死兜底：副作用最多等 5s，超时降级为告警，不阻塞主写链路。
const POST_COMMIT_EFFECT_TIMEOUT_MS: number = 5000;

export class KnowledgeUnitWriteService {
  /** 全局写区：索引同步 + post-commit effects 串行（S0 并发实验：并发 post-commit 会卡死）。 */
  private static readonly writeSection: AsyncMutex = new AsyncMutex();
  private repository: KnowledgeUnitWriteRepository;
  private effects: KnowledgeUnitPostCommitEffect[];
  private readonly judge: NoteSimilarityJudgePort | undefined;

  constructor(repository: KnowledgeUnitWriteRepository, effects: KnowledgeUnitPostCommitEffect[],
    judge?: NoteSimilarityJudgePort) {
    this.repository = repository;
    this.effects = effects;
    this.judge = judge;
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
      persisted.unit, persisted.duplicate !== true);
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

  /**
   * 写前查重：先走确定性规则；拿不准的灰区（0.6–0.9）交给模型仲裁，
   * 避免「换个说法」的同一道题被重复写入。
   */
  private async findDuplicate(unit: KnowledgeUnit): Promise<KnowledgeUnit | null> {
    let hard: KnowledgeUnit | null = null;
    if (this.repository.findDuplicate !== undefined) {
      try {
        hard = await this.repository.findDuplicate(unit);
      } catch (e) {
        hard = null;
      }
    }
    if (hard !== null) {
      return hard;
    }
    if (this.judge === undefined || this.repository.findSimilarCandidates === undefined) {
      return null;
    }
    let candidates: NoteSimilarityCandidate[] = [];
    try {
      candidates = await this.repository.findSimilarCandidates(unit);
    } catch (e) {
      return null;
    }
    let best: NoteSimilarityCandidate | null = null;
    let bestScore: number = 0;
    for (let i = 0; i < candidates.length; i += 1) {
      const score: number = similarityScore(unit.title, unit.content,
        candidates[i].title, candidates[i].content);
      if (score > bestScore) {
        bestScore = score;
        best = candidates[i];
      }
    }
    if (best === null || bestScore < SIMILARITY_GRAY_MIN) {
      return null;
    }
    if (bestScore >= SIMILARITY_HARD_DUPLICATE) {
      return await this.loadCandidate(best.id);
    }
    let sameNote: boolean = false;
    try {
      sameNote = await this.judge.isSameNote(unit.title, unit.content, best.title, best.content);
    } catch (e) {
      sameNote = false;
    }
    return sameNote ? await this.loadCandidate(best.id) : null;
  }

  private async loadCandidate(id: string): Promise<KnowledgeUnit | null> {
    if (this.repository.queryById === undefined) {
      return null;
    }
    try {
      return await this.repository.queryById(id);
    } catch (e) {
      return null;
    }
  }

  /** 写区串行段：post-commit effects（并发时会卡死，必须互斥）。索引已在写库事务内同步。 */
  private async finalizeWrite(unit: KnowledgeUnit, isCreate: boolean): Promise<string[]> {
    return await KnowledgeUnitWriteService.writeSection.runExclusive(async (): Promise<string[]> => {
      return await this.runPostCommit(unit, isCreate);
    });
  }

  /** Promise.race 超时兜底：只用于「可降级」的 UI 副作用，不改变事务结果。 */
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
