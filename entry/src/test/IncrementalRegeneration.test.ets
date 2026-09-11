/**
 * IncrementalRegeneration.test.ets - Issue 104 seam tests.
 *
 * Covers the public regeneration contracts before UI wiring: planner/merge,
 * repository base lookup, Dispatcher draft/confirm, and write coordination.
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  DifficultyLevel,
  KnowledgeUnit,
  ReviewStatus,
  IncrementalSection,
  IncrementalManifest,
  IncrementalRequirement,
  IncrementalPlan,
  IncrementalPatch,
  parseIncrementalSections,
  buildIncrementalManifest,
  detectIncrementalLocks,
  planIncrementalChange,
  mergeIncrementalPatches,
  sourceFingerprint,
  NoteGenerationRequest,
  SourceFragment,
  IncrementalBase,
  NoteGenerationRepository,
  NoteGenerationRun,
  NoteGenerationCheckpoint,
  NoteGenerationRecovery,
  NoteGenerationCommitResult,
  NoteGenerationLifecycleLog,
  SourceBundle,
} from 'common';
import { Dispatcher, KnowledgeModel } from 'agents';
import { IncrementalPatchResponse } from 'common';
import { KnowledgeUnitWriteService } from '../main/ets/services/KnowledgeUnitWriteService';
import {
  KnowledgeUnitPersistenceResult,
  KnowledgeUnitPostCommitEffect,
  KnowledgeUnitWriteError,
  KnowledgeUnitWriteErrorCode,
  KnowledgeUnitWriteRepository,
} from '../main/ets/models/KnowledgeUnitWriteModels';

const makeUnit = (content: string, version: number = 2): KnowledgeUnit => {
  return {
    id: 'note-104', title: '连续函数', content: content, summary: '连续函数', tags: ['连续'],
    subject: '数学分析', category: '概念', chapter: '连续性', difficulty: DifficultyLevel.EASY,
    source: 'note_generation', createdAt: 10, updatedAt: 20, reviewStatus: ReviewStatus.REVIEW,
    nextReviewAt: 30, intervalDays: 5, easeFactor: 2.5, repetitions: 3,
    prerequisites: ['pre-1'], related: ['related-1'], embedding: [0.1, 0.2], userId: 'u1', version: version,
  };
};

class FakeWriteRepository implements KnowledgeUnitWriteRepository {
  lastExpectedVersion: number = 0;
  async createWithRevision(unit: KnowledgeUnit, _metadata: string): Promise<KnowledgeUnitPersistenceResult> {
    return { rowId: 1, unit: unit };
  }
  async updateWithRevision(unit: KnowledgeUnit, expectedVersion: number, _metadata: string): Promise<KnowledgeUnitPersistenceResult> {
    this.lastExpectedVersion = expectedVersion;
    return { rowId: 0, unit: unit };
  }
}

class NoopEffect implements KnowledgeUnitPostCommitEffect {
  name: string = 'noop';
  async run(_unit: KnowledgeUnit): Promise<void> {
  }
}

class ConflictWriteRepository extends FakeWriteRepository {
  async updateWithRevision(
    _unit: KnowledgeUnit,
    _expectedVersion: number,
    _metadata: string,
  ): Promise<KnowledgeUnitPersistenceResult> {
    throw new KnowledgeUnitWriteError(
      KnowledgeUnitWriteErrorCode.VERSION_CONFLICT,
      'stale KnowledgeUnit version',
    );
  }
}

class FakeIncrementalModel extends KnowledgeModel {
  async repairIncrementalSections(
    _request: NoteGenerationRequest,
    plan: IncrementalPlan,
    _sections: IncrementalSection[],
    _sources: SourceFragment[],
  ): Promise<IncrementalPatchResponse> {
    return { patches: [{ sectionId: plan.targetSectionIds[0], operation: 'replace', content: '新增例子', sourceIds: ['source-new'] }] };
  }
}

class FakeIncrementalRepository implements NoteGenerationRepository {
  base: IncrementalBase;
  checkpoints: NoteGenerationCheckpoint[] = [];

  constructor(base: IncrementalBase) { this.base = base; }
  async saveRun(_run: NoteGenerationRun, _bundle: SourceBundle): Promise<void> {}
  async saveCheckpoint(checkpoint: NoteGenerationCheckpoint): Promise<void> { this.checkpoints.push(checkpoint); }
  async restore(_runId: string): Promise<NoteGenerationRecovery | undefined> { return undefined; }
  async saveCommitResult(_result: NoteGenerationCommitResult): Promise<void> {}
  async getCommitResult(_key: string): Promise<NoteGenerationCommitResult | undefined> { return undefined; }
  async cancelRun(_runId: string): Promise<void> {}
  async appendLifecycleLog(_log: NoteGenerationLifecycleLog): Promise<void> {}
  async listRecoverableRuns(): Promise<NoteGenerationRun[]> { return []; }
  async getRegenerationBase(_noteId: string): Promise<IncrementalBase | undefined> { return this.base; }
}

export default function incrementalRegenerationTest(): void {
  describe('Issue 104 incremental regeneration', () => {
    it('parses stable sections and locks a manually edited latest revision', 0, () => {
      const current = parseIncrementalSections('## 定义\n定义正文\n## 例子\n例子正文');
      const generated: IncrementalManifest = buildIncrementalManifest('note-104', 2, current, ['source-old']);
      const edited: IncrementalSection[] = parseIncrementalSections('## 定义\n用户改过的定义\n## 例子\n例子正文');
      const locked: IncrementalSection[] = detectIncrementalLocks(edited, generated);
      expect(locked[0].state).assertEqual('locked');
      expect(locked[1].state).assertEqual('generated');
      expect(locked[0].content).assertEqual('用户改过的定义');
    });

    it('plans only relevant targets and merge preserves locked and untargeted bytes', 0, () => {
      const sections: IncrementalSection[] = parseIncrementalSections('## 定义\n定义正文\n## 例子\n例子正文');
      const manifest: IncrementalManifest = buildIncrementalManifest('note-104', 2, sections, ['source-old']);
      const requirement: IncrementalRequirement = {
        instruction: '增加一个例子', targetSectionIds: [], mustInclude: ['例子'], preserveUserEdits: true,
      };
      const plan: IncrementalPlan = planIncrementalChange(requirement, sections, manifest, [{
        id: 'source-new', kind: 'conversation', originId: 'chat', sequence: 0,
        fingerprint: sourceFingerprint('新例子'), text: '新例子',
      }]);
      expect(plan.targetSectionIds.length).assertEqual(1);
      const patch: IncrementalPatch = {
        sectionId: plan.targetSectionIds[0], operation: 'replace', content: '新增例子', sourceIds: ['source-new'],
      };
      const merged = mergeIncrementalPatches(sections, plan, [patch]);
      expect(merged.ok).assertTrue();
      expect(merged.sections[0].content).assertEqual('定义正文');
      expect(merged.sections[1].content).assertEqual('新增例子');
      expect(merged.diff.some((item): boolean => item.kind === 'changed')).assertTrue();
    });

    it('passes the expected version through the write seam', 0, async () => {
      const repository: FakeWriteRepository = new FakeWriteRepository();
      const service: KnowledgeUnitWriteService = new KnowledgeUnitWriteService(repository, [new NoopEffect()]);
      const result = await service.update(makeUnit('## 定义\n定义正文'), 2, 'issue-104');
      expect(result.committed).assertTrue();
      expect(repository.lastExpectedVersion).assertEqual(2);
    });

    it('returns VERSION_CONFLICT instead of overwriting a newer KnowledgeUnit', 0, async () => {
      const repository: ConflictWriteRepository = new ConflictWriteRepository();
      const service: KnowledgeUnitWriteService = new KnowledgeUnitWriteService(repository, [new NoopEffect()]);
      const result = await service.update(makeUnit('## 定义\n过期正文'), 2, 'issue-104');
      expect(result.committed).assertFalse();
      expect(result.errorCode).assertEqual(KnowledgeUnitWriteErrorCode.VERSION_CONFLICT);
    });

  it('requires an explicit note id at Dispatcher.dispatch', 0, async () => {
      const result = await new Dispatcher().dispatch({
        source: 'app', payload: { kind: 'text', text: '增加例子' }, generation: {
          runId: 'regen-104', instruction: '增加例子', mode: 'regenerate',
          sources: { fragments: [] }, baseVersion: 2,
        },
      }, { persist: false });
      expect(result.success).assertFalse();
      expect(result.errorCode).assertEqual('NOTE_ID_REQUIRED');
    });

    it('keeps an ambiguous conversational request at selection instead of guessing a title', 0, async () => {
      const result = await new Dispatcher().dispatch({
        source: 'app', payload: { kind: 'text', text: '增加例子' }, generation: {
          runId: 'ambiguous-104', instruction: '增加例子', mode: 'regenerate',
          sources: { fragments: [] }, baseVersion: 2,
        },
      }, { persist: false });
      expect(result.success).assertFalse();
      expect(result.errorCode).assertEqual('NOTE_ID_REQUIRED');
    });

    it('generates a targeted preview through Dispatcher without a DAO write', 0, async () => {
      const sections: IncrementalSection[] = parseIncrementalSections('## 定义\n定义正文\n## 例子\n旧例子');
      sections[0].sourceIds = ['source-old'];
      sections[1].sourceIds = ['source-old'];
      const base: IncrementalBase = {
        unit: makeUnit('## 定义\n定义正文\n## 例子\n旧例子'),
        manifest: buildIncrementalManifest('note-104', 2, sections, ['source-old']),
        sources: { fragments: [{ id: 'source-old', kind: 'conversation', originId: 'old', sequence: 0, fingerprint: 'old', text: '旧例子' }] },
        baseVersion: 2,
      };
      const repository: FakeIncrementalRepository = new FakeIncrementalRepository(base);
      const request: NoteGenerationRequest = {
        runId: 'incremental-preview-104', instruction: '增加一个例子', mode: 'regenerate',
        targetNoteId: 'note-104', baseVersion: 2,
        sources: { fragments: [{ id: 'source-new', kind: 'conversation', originId: 'new', sequence: 0, fingerprint: 'new', text: '新例子' }] },
      };
      const result = await new Dispatcher().dispatch({
        source: 'app', payload: { kind: 'text', text: request.instruction }, generation: request,
      }, { persist: false, generationRepository: repository, knowledgeModel: new FakeIncrementalModel() });
      expect(result.success).assertTrue();
      expect(result.data?.id).assertEqual('note-104');
      expect(result.data?.version).assertEqual(2);
      expect(result.data?.content.includes('新增例子')).assertTrue();
      expect(result.generation?.incrementalDiff?.some((item): boolean => item.kind === 'preserved')).assertTrue();
      expect(repository.checkpoints.length).assertEqual(1);
    });
  });
}
