/**
 * KnowledgeUnitWriteService.test.ets — KnowledgeUnit 写入协调行为测试
 *
 * 路径: entry/src/test/KnowledgeUnitWriteService.test.ets
 * 职责: 覆盖提交、冲突、持久化失败和写后警告
 * 依赖: Hypium, KnowledgeUnitWriteService
 */
import { describe, it, expect } from '@ohos/hypium';
import { DifficultyLevel, KnowledgeUnit, ReviewStatus } from 'common';
import {
  KnowledgeUnitPersistenceResult,
  KnowledgeUnitPostCommitEffect,
  KnowledgeUnitWriteError,
  KnowledgeUnitWriteErrorCode,
  KnowledgeUnitWriteRepository,
  KnowledgeUnitWriteResult,
} from '../main/ets/models/KnowledgeUnitWriteModels';
import { KnowledgeUnitWriteService } from '../main/ets/services/KnowledgeUnitWriteService';

class FakeWriteRepository implements KnowledgeUnitWriteRepository {
  fail: boolean = false;
  conflict: boolean = false;
  createCalls: number = 0;
  updateCalls: number = 0;
  expectedVersion: number = 0;

  async createWithRevision(unit: KnowledgeUnit, generationMetadata: string): Promise<KnowledgeUnitPersistenceResult> {
    this.createCalls += 1;
    if (this.fail) {
      throw new Error('revision insert failed');
    }
    const result: KnowledgeUnitPersistenceResult = { rowId: 8, unit: unit };
    return result;
  }

  async updateWithRevision(
    unit: KnowledgeUnit,
    expectedVersion: number,
    generationMetadata: string,
  ): Promise<KnowledgeUnitPersistenceResult> {
    this.updateCalls += 1;
    this.expectedVersion = expectedVersion;
    if (this.conflict) {
      throw new KnowledgeUnitWriteError(KnowledgeUnitWriteErrorCode.VERSION_CONFLICT, 'stale version');
    }
    const result: KnowledgeUnitPersistenceResult = { rowId: 0, unit: unit };
    return result;
  }
}

class FakePostCommitEffect implements KnowledgeUnitPostCommitEffect {
  name: string = 'card_refresh';
  fail: boolean = false;
  calls: number = 0;

  async run(unit: KnowledgeUnit): Promise<void> {
    this.calls += 1;
    if (this.fail) {
      throw new Error('card unavailable');
    }
  }
}

const makeUnit = (version: number): KnowledgeUnit => {
  const unit: KnowledgeUnit = {
    id: 'note-97',
    title: 'Mean value theorem',
    content: 'Snapshot content',
    summary: 'Snapshot summary',
    tags: ['theorem'],
    subject: 'Calculus',
    category: '定理',
    chapter: 'Derivatives',
    difficulty: DifficultyLevel.MEDIUM,
    source: 'manual',
    createdAt: 100,
    updatedAt: 200,
    reviewStatus: ReviewStatus.REVIEW,
    nextReviewAt: 300,
    intervalDays: 5,
    easeFactor: 2.4,
    repetitions: 3,
    prerequisites: ['note-1'],
    related: ['note-2'],
    embedding: [0.1, 0.2],
    userId: 'user-1',
    version: version,
  };
  return unit;
};

export default function knowledgeUnitWriteServiceTest() {
  describe('KnowledgeUnitWriteService', () => {
    it('returns committed create and runs post-commit effects', 0, async () => {
      const repository: FakeWriteRepository = new FakeWriteRepository();
      const effect: FakePostCommitEffect = new FakePostCommitEffect();
      const effects: KnowledgeUnitPostCommitEffect[] = [effect];
      const service: KnowledgeUnitWriteService = new KnowledgeUnitWriteService(repository, effects);

      const result: KnowledgeUnitWriteResult = await service.create(makeUnit(1), '');

      expect(result.committed).assertTrue();
      expect(result.rowId).assertEqual(8);
      expect(result.warnings.length).assertEqual(0);
      expect(repository.createCalls).assertEqual(1);
      expect(effect.calls).assertEqual(1);
    });

    it('returns VERSION_CONFLICT without running post-commit effects', 0, async () => {
      const repository: FakeWriteRepository = new FakeWriteRepository();
      repository.conflict = true;
      const effect: FakePostCommitEffect = new FakePostCommitEffect();
      const effects: KnowledgeUnitPostCommitEffect[] = [effect];
      const service: KnowledgeUnitWriteService = new KnowledgeUnitWriteService(repository, effects);

      const result: KnowledgeUnitWriteResult = await service.update(makeUnit(3), 2, '');

      expect(result.committed).assertFalse();
      expect(result.errorCode).assertEqual(KnowledgeUnitWriteErrorCode.VERSION_CONFLICT);
      expect(repository.expectedVersion).assertEqual(2);
      expect(effect.calls).assertEqual(0);
    });

    it('keeps persistence failure fatal and skips post-commit effects', 0, async () => {
      const repository: FakeWriteRepository = new FakeWriteRepository();
      repository.fail = true;
      const effect: FakePostCommitEffect = new FakePostCommitEffect();
      const effects: KnowledgeUnitPostCommitEffect[] = [effect];
      const service: KnowledgeUnitWriteService = new KnowledgeUnitWriteService(repository, effects);
      let failed: boolean = false;

      try {
        await service.create(makeUnit(1), '');
      } catch (e) {
        failed = true;
      }

      expect(failed).assertTrue();
      expect(effect.calls).assertEqual(0);
    });

    it('returns warning when a post-commit effect fails', 0, async () => {
      const repository: FakeWriteRepository = new FakeWriteRepository();
      const effect: FakePostCommitEffect = new FakePostCommitEffect();
      effect.fail = true;
      const effects: KnowledgeUnitPostCommitEffect[] = [effect];
      const service: KnowledgeUnitWriteService = new KnowledgeUnitWriteService(repository, effects);

      const result: KnowledgeUnitWriteResult = await service.create(makeUnit(1), '');

      expect(result.committed).assertTrue();
      expect(result.warnings.length).assertEqual(1);
      expect(result.warnings[0]).assertContain('card_refresh');
    });
  });
}
