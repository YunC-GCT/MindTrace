/**
 * DispatcherNoteGeneration.test.ets — Issue 98 stable Capture seam tests.
 *
 * This test deliberately injects a KnowledgeModel test double. The production
 * path still enters only through Dispatcher.dispatch and never reaches a DAO
 * when persist=false.
 */
import { describe, it, expect } from '@ohos/hypium';
import { Dispatcher, DispatchOptions, NoteCommitResult } from 'agents';
import { KnowledgeModel } from 'agents';
import {
  DifficultyLevel,
  DispatchRequest,
  DispatchResult,
  KnowledgeUnit,
  NoteDraftDocument,
  NoteDraftSection,
  NoteGenerationEvidenceItem,
  NoteGenerationOutline,
  NoteGenerationStandardResult,
  NoteGenerationVerification,
  NoteGenerationEvidenceDecision,
  NoteGenerationIssue,
  NoteGenerationRequest,
  NoteGenerationRepository,
  NoteGenerationRun,
  NoteGenerationCheckpoint,
  ReviewStatus,
  SourceBundle,
  NoteGenerationRecovery,
  NoteGenerationCommitResult,
  NoteGenerationLifecycleLog,
  PreparedCandidate,
  NoteGenerationDeepResult,
  NoteGenerationLedger,
  deepBudget,
  segmentSourceBundle,
  selectGenerationRoute,
  sourceFingerprint,
  stableSectionId,
} from 'common';

class FakeRepository implements NoteGenerationRepository {
  runSaves: number = 0;
  checkpointSaves: number = 0;
  checkpoints: NoteGenerationCheckpoint[] = [];
  commits: NoteGenerationCommitResult[] = [];

  async saveRun(_run: NoteGenerationRun, _bundle: SourceBundle): Promise<void> {
    this.runSaves += 1;
  }

  async saveCheckpoint(_checkpoint: NoteGenerationCheckpoint): Promise<void> {
    this.checkpointSaves += 1;
    this.checkpoints.push(_checkpoint);
  }

  async restore(runId: string): Promise<NoteGenerationRecovery | undefined> {
    if (runId !== 'light-98') {
      return undefined;
    }
    const run: NoteGenerationRun = {
      id: runId,
      route: 'light',
      status: 'ready-preview',
      instruction: '保留定义',
      sourceCount: 1,
      tokenBudget: 1200,
    };
    return { run: run, sources: { fragments: [] }, checkpoints: this.checkpoints, softIssueCodes: [] };
  }

  async saveCommitResult(result: NoteGenerationCommitResult): Promise<void> {
    this.commits.push(result);
  }

  async getCommitResult(commitKey: string): Promise<NoteGenerationCommitResult | undefined> {
    return this.commits.find((item: NoteGenerationCommitResult): boolean => item.commitKey === commitKey);
  }

  async cancelRun(_runId: string): Promise<void> {
  }

  async appendLifecycleLog(_log: NoteGenerationLifecycleLog): Promise<void> {
  }

  async listRecoverableRuns(): Promise<NoteGenerationRun[]> {
    return [];
  }
}

class FakeKnowledgeModel extends KnowledgeModel {
  calls: number = 0;

  async structureLightDraft(_request: NoteGenerationRequest): Promise<NoteDraftDocument> {
    this.calls += 1;
    const section: NoteDraftSection = {
      id: 'definition',
      label: '定义',
      content: '函数在闭区间上连续。',
      sourceIds: ['source-1'],
      state: 'generated',
      baseHash: 'base-1',
    };
    return {
      schemaVersion: 'mindtrace.note-draft.v1',
      title: '连续函数',
      summary: '闭区间连续性',
      subject: '数学分析',
      category: '概念',
      chapter: '连续性',
      difficulty: 1,
      tags: ['连续'],
      sections: [section],
    };
  }
}

class StandardKnowledgeModel extends KnowledgeModel {
  calls: number = 0;

  async structureStandardDraft(_request: NoteGenerationRequest): Promise<NoteGenerationStandardResult> {
    this.calls += 1;
    const outline: NoteGenerationOutline = {
      schemaVersion: 'mindtrace.note-outline.v1',
      sections: [{
        id: 'section-definition',
        label: '定义',
        order: 0,
        mustInclude: ['定义'],
        sourceIds: ['source-a'],
      }, {
        id: 'section-example',
        label: '例子',
        order: 1,
        mustInclude: ['例子'],
        sourceIds: ['source-b'],
      }],
    };
    const evidence: NoteGenerationEvidenceItem[] = [{
      id: 'evidence-definition',
      type: 'definition',
      claim: '函数在闭区间上连续。',
      sourceRefs: [{ sourceId: 'source-a', excerpt: '函数在闭区间上连续。', start: 0, end: 10 }],
      targetSectionId: 'section-definition',
      verification: 'supported',
    }, {
      id: 'evidence-example',
      type: 'example',
      claim: '函数 f(x)=x 在 [0,1] 上连续。',
      sourceRefs: [{ sourceId: 'source-b', excerpt: '例：f(x)=x 在 [0,1] 上连续。', start: 0, end: 25 }],
      targetSectionId: 'section-example',
      verification: 'supported',
    }];
    const draft: NoteDraftDocument = {
      schemaVersion: 'mindtrace.note-draft.v1',
      title: '连续函数',
      summary: '定义与例子',
      subject: '数学分析',
      category: '概念',
      chapter: '连续性',
      difficulty: 1,
      tags: ['连续'],
      instruction: '完整保留定义和例子',
      sections: [{
        id: 'section-definition',
        label: '定义',
        content: '函数在闭区间上连续。',
        sourceIds: ['source-a'],
        state: 'generated',
        baseHash: 'hash-definition',
      }, {
        id: 'section-example',
        label: '例子',
        content: '例：f(x)=x 在 [0,1] 上连续。',
        sourceIds: ['source-b'],
        state: 'generated',
        baseHash: 'hash-example',
      }],
    };
    const verification: NoteGenerationVerification = {
      status: 'supported',
      issues: [],
      checkedEvidenceIds: ['evidence-definition', 'evidence-example'],
      decisions: [{ evidenceId: 'evidence-definition', status: 'supported' }, { evidenceId: 'evidence-example', status: 'supported' }],
    };
    return { outline: outline, evidence: evidence, draft: draft, verification: verification };
  }
}

class DeepKnowledgeModel extends KnowledgeModel {
  calls: number = 0;

  async structureDeepDraft(request: NoteGenerationRequest): Promise<NoteGenerationDeepResult> {
    this.calls += 1;
    const firstSource: string = request.sources.fragments[0].id;
    const lastSource: string = request.sources.fragments[request.sources.fragments.length - 1].id;
    const outline: NoteGenerationOutline = {
      schemaVersion: 'mindtrace.note-outline.v1',
      sections: [{
        id: 'section-proof', label: '证明', order: 0, mustInclude: ['推导'], sourceIds: [firstSource],
        depth: 0, parentId: undefined, segmentIds: [],
      }, {
        id: 'section-example', label: '例子', order: 1, mustInclude: ['例子'], sourceIds: [lastSource],
        depth: 1, parentId: 'section-proof', segmentIds: [],
      }],
    };
    const draft: NoteDraftDocument = {
      schemaVersion: 'mindtrace.note-draft.v1', title: '长证明', summary: '完整推导', subject: '数学分析',
      category: '证明题', chapter: '极限', difficulty: 3, tags: ['证明'], instruction: request.instruction,
      sections: [{ id: 'section-proof', label: '证明', content: '推导：保留全部步骤。', sourceIds: [firstSource], state: 'generated', baseHash: 'proof' }, {
        id: 'section-example', label: '例子', content: '例子：保留尾部材料。', sourceIds: [lastSource], state: 'generated', baseHash: 'example',
      }],
    };
    const ledger: NoteGenerationLedger = { formulas: [], terminology: [], conclusions: [] };
    return { outline: outline, evidence: [], draft: draft, verification: { status: 'supported', issues: [], checkedEvidenceIds: [], decisions: [] }, ledger: ledger };
  }
}

class ContradictoryKnowledgeModel extends StandardKnowledgeModel {
  async structureStandardDraft(_request: NoteGenerationRequest): Promise<NoteGenerationStandardResult> {
    this.calls += 1;
    const outline: NoteGenerationOutline = {
      schemaVersion: 'mindtrace.note-outline.v1',
      sections: [{ id: 'section-definition', label: '定义', order: 0, mustInclude: ['定义'], sourceIds: ['source-a'] }, {
        id: 'section-example', label: '例子', order: 1, mustInclude: ['例子'], sourceIds: ['source-b'],
      }],
    };
    const resultEvidence: NoteGenerationEvidenceItem[] = [{
      id: 'evidence-definition', type: 'definition', claim: '函数在闭区间上连续。',
      sourceRefs: [{ sourceId: 'source-a', excerpt: '定义与例子存在冲突。', start: 0, end: 10 }],
      targetSectionId: 'section-definition', verification: 'contradicted',
    }, {
      id: 'evidence-example', type: 'example', claim: '例：f(x)=x。',
      sourceRefs: [{ sourceId: 'source-b', excerpt: '例：f(x)=x。', start: 0, end: 10 }],
      targetSectionId: 'section-example', verification: 'contradicted',
    }];
    const draft: NoteDraftDocument = {
      schemaVersion: 'mindtrace.note-draft.v1', title: '冲突材料', summary: '冲突', subject: '数学分析',
      category: '概念', chapter: '连续性', difficulty: 1, tags: ['连续'], instruction: '完整保留定义和例子',
      sections: [{ id: 'section-definition', label: '定义', content: '定义与例子存在冲突。', sourceIds: ['source-a'], state: 'generated', baseHash: 'a' }, {
        id: 'section-example', label: '例子', content: '例：f(x)=x。', sourceIds: ['source-b'], state: 'generated', baseHash: 'b',
      }],
    };
    const evidence: NoteGenerationEvidenceItem[] = [];
    for (const item of resultEvidence) {
      evidence.push({
        id: item.id,
        type: item.type,
        claim: item.claim,
        sourceRefs: item.sourceRefs,
        targetSectionId: item.targetSectionId,
        verification: 'contradicted',
      });
    }
    const issue: NoteGenerationIssue = {
      stage: 'evidence', code: 'EVIDENCE_CONTRADICTED', severity: 'hard',
      message: 'verifier found contradicted evidence', repairable: true,
    };
    const verification: NoteGenerationVerification = {
      status: 'contradicted', issues: [issue], checkedEvidenceIds: ['evidence-definition', 'evidence-example'],
      decisions: [{ evidenceId: 'evidence-definition', status: 'contradicted' }, { evidenceId: 'evidence-example', status: 'contradicted' }],
    };
    return { outline: outline, evidence: evidence, draft: draft, verification: verification, reextractionCount: 1 };
  }

  async repairStandardDraft(
    _request: NoteGenerationRequest,
    current: NoteGenerationStandardResult,
    _issues: NoteGenerationIssue[],
  ): Promise<NoteGenerationStandardResult> {
    return current;
  }
}

class RepairingKnowledgeModel extends StandardKnowledgeModel {
  private firstAttempt: boolean = true;

  async structureStandardDraft(_request: NoteGenerationRequest): Promise<NoteGenerationStandardResult> {
    if (this.firstAttempt) {
      this.firstAttempt = false;
      return await new ContradictoryKnowledgeModel().structureStandardDraft(_request);
    }
    return await super.structureStandardDraft(_request);
  }

  async repairStandardDraft(
    request: NoteGenerationRequest,
    current: NoteGenerationStandardResult,
    _issues: NoteGenerationIssue[],
  ): Promise<NoteGenerationStandardResult> {
    const evidence: NoteGenerationEvidenceItem[] = [];
    for (const item of current.evidence) {
      evidence.push({
        id: item.id,
        type: item.type,
        claim: item.claim,
        sourceRefs: item.sourceRefs,
        targetSectionId: item.targetSectionId,
        verification: 'supported',
      });
    }
    const verification: NoteGenerationVerification = {
      status: 'supported',
      issues: [],
      checkedEvidenceIds: evidence.map((item: NoteGenerationEvidenceItem): string => item.id),
      decisions: evidence.map((item: NoteGenerationEvidenceItem): NoteGenerationEvidenceDecision => ({
        evidenceId: item.id,
        status: 'supported',
      })),
    };
    return {
      outline: current.outline,
      evidence: evidence,
      draft: current.draft,
      verification: verification,
      reextractionCount: 1,
    };
  }
}

class DiminishingKnowledgeModel extends ContradictoryKnowledgeModel {
  private repairRound: number = 0;

  async repairStandardDraft(
    _request: NoteGenerationRequest,
    current: NoteGenerationStandardResult,
    _issues: NoteGenerationIssue[],
  ): Promise<NoteGenerationStandardResult> {
    this.repairRound += 1;
    const issue: NoteGenerationIssue = {
      stage: 'evidence',
      code: 'NO_IMPROVEMENT_' + this.repairRound.toString(),
      severity: 'hard',
      message: 'candidate did not improve ' + 'x'.repeat(this.repairRound * 20),
      repairable: true,
    };
    const verification: NoteGenerationVerification = {
      status: 'contradicted',
      issues: [issue],
      checkedEvidenceIds: current.verification.checkedEvidenceIds,
      decisions: current.verification.decisions,
    };
    return {
      outline: current.outline,
      evidence: current.evidence,
      draft: current.draft,
      verification: verification,
      reextractionCount: this.repairRound,
    };
  }
}

class CountingDao {
  writes: number = 0;
}

  const unitForTest: KnowledgeUnit = {
  id: 'candidate-98',
  title: '连续函数',
  content: '## 定义\n函数在闭区间上连续。',
  summary: '闭区间连续性',
  tags: ['连续'],
  subject: '数学分析',
  category: '概念',
  chapter: '连续性',
  difficulty: DifficultyLevel.EASY,
  source: 'note_generation',
  createdAt: 1,
  updatedAt: 1,
  reviewStatus: ReviewStatus.NEW,
  nextReviewAt: 2,
  intervalDays: 1,
  easeFactor: 2.5,
  repetitions: 0,
  prerequisites: [],
  related: [],
  embedding: [],
  userId: '',
  version: 1,
  };

export default function dispatcherNoteGenerationTest(): void {
  describe('Dispatcher.note_generation', () => {
    it('returns needs-input without calling Structure for missing facts', 0, async () => {
      const repository: FakeRepository = new FakeRepository();
      const request: DispatchRequest = {
        source: 'app',
        payload: { kind: 'text', text: '' },
        generation: {
          runId: 'missing-98',
          instruction: '请补充缺少的已知条件',
          mode: 'create',
          sources: { fragments: [] },
        },
      };
      const options: DispatchOptions = { persist: false, generationRepository: repository };
      const result: DispatchResult = await new Dispatcher().dispatch(request, options);

      expect(result.success).assertFalse();
      expect(result.generation?.status).assertEqual('needs-input');
      expect(result.generation?.questions.length > 0).assertTrue();
      expect(repository.runSaves).assertEqual(2);
      expect(repository.checkpointSaves).assertEqual(0);
    });

    it('returns a TruthChecked candidate and performs no DAO writes', 0, async () => {
      const repository: FakeRepository = new FakeRepository();
      const dao: CountingDao = new CountingDao();
      const request: DispatchRequest = {
        source: 'app',
        payload: { kind: 'text', text: '函数在闭区间上连续。' },
        generation: {
          runId: 'light-98',
          instruction: '保留定义',
          mode: 'create',
          sources: {
            fragments: [{
              id: 'source-1',
              kind: 'ocr',
              originId: 'ocr-1',
              sequence: 0,
              fingerprint: 'fp-1',
              text: '函数在闭区间上连续。',
            }],
          },
        },
      };
      const model: FakeKnowledgeModel = new FakeKnowledgeModel();
      const options: DispatchOptions = {
        persist: false,
        dao: {
          insert: async (_unit: KnowledgeUnit): Promise<number> => {
            dao.writes += 1;
            return 1;
          },
        },
        generationRepository: repository,
        knowledgeModel: model,
      };
      const result: DispatchResult = await new Dispatcher().dispatch(request, options);

      expect(result.success).assertTrue();
      expect(result.data?.title).assertEqual(unitForTest.title);
      expect(result.generation?.route).assertEqual('light');
      expect(result.generation?.status).assertEqual('ready-preview');
      expect(dao.writes).assertEqual(0);
      expect(repository.checkpointSaves).assertEqual(1);

      const generated: KnowledgeUnit = result.data ?? unitForTest;
      const prepared: PreparedCandidate = {
        runId: 'light-98',
        checkpointId: 'light-98:0',
        candidateHash: sourceFingerprint(JSON.stringify(generated)),
        candidate: generated,
        commitKey: 'light-98:light-98:0:confirmed',
      };
      const insertWithCommitKey = async (unit: KnowledgeUnit): Promise<NoteCommitResult> => {
        dao.writes += unit.title === generated.title ? 1 : 0;
        return {
          commitKey: prepared.commitKey ?? '',
          rowId: 2,
          noteId: unit.id,
          version: unit.version,
          duplicate: false,
        };
      };
      const confirmResult: DispatchResult = await new Dispatcher().dispatch({
        source: 'app',
        payload: { kind: 'text', text: generated.content },
        preparedCandidate: prepared,
      }, {
        persist: true,
        generationRepository: repository,
        dao: {
          insert: async (_unit: KnowledgeUnit): Promise<number> => 2,
          insertWithCommitKey: insertWithCommitKey,
        },
      });
      const duplicateResult: DispatchResult = await new Dispatcher().dispatch({
        source: 'app',
        payload: { kind: 'text', text: generated.content },
        preparedCandidate: prepared,
      }, {
        persist: true,
        generationRepository: repository,
        dao: {
          insert: async (_unit: KnowledgeUnit): Promise<number> => 3,
          insertWithCommitKey: insertWithCommitKey,
        },
      });
      expect(confirmResult.success).assertTrue();
      expect(duplicateResult.success).assertTrue();
      expect(confirmResult.data?.content).assertEqual(generated.content);
      expect(duplicateResult.data?.content).assertEqual(generated.content);
      expect(dao.writes).assertEqual(1);
      expect(model.calls).assertEqual(1);
    });

    it('uses the deterministic standard route with outline and frozen supported evidence', 0, async () => {
      const repository: FakeRepository = new FakeRepository();
      const model: StandardKnowledgeModel = new StandardKnowledgeModel();
      const request: DispatchRequest = {
        source: 'app',
        payload: { kind: 'text', text: '函数在闭区间上连续。例：f(x)=x 在 [0,1] 上连续。' },
        generation: {
          runId: 'standard-101',
          instruction: '完整保留定义和例子',
          mode: 'create',
          sources: { fragments: [{
            id: 'source-a', kind: 'conversation', originId: 'message-a', sequence: 0,
            fingerprint: 'a', text: '函数在闭区间上连续。',
          }, {
            id: 'source-b', kind: 'ocr', originId: 'ocr-b', sequence: 1,
            fingerprint: 'b', text: '例：f(x)=x 在 [0,1] 上连续。',
          }] },
        },
      };
      const result: DispatchResult = await new Dispatcher().dispatch(request, {
        persist: false, generationRepository: repository, knowledgeModel: model,
      });

      expect(result.success).assertTrue();
      expect(result.generation?.route).assertEqual('standard');
      expect(result.generation?.outline?.sections[0].id).assertEqual(stableSectionId(0, '定义'));
      expect(result.generation?.evidence?.length).assertEqual(2);
      expect(result.generation?.verification?.status).assertEqual('supported');
      expect(repository.checkpointSaves).assertEqual(1);
      expect(model.calls).assertEqual(1);
    });

    it('returns needs-input for facts that only the user can supply', 0, async () => {
      const repository: FakeRepository = new FakeRepository();
      const request: DispatchRequest = {
        source: 'app',
        payload: { kind: 'text', text: '请整理这个题目。' },
        generation: {
          runId: 'needs-input-101',
          instruction: '完整推导，但题目缺少已知条件',
          mode: 'create',
          sources: { fragments: [{
            id: 'source-a', kind: 'conversation', originId: 'message-a', sequence: 0,
            fingerprint: 'a', text: '请整理这个题目。',
          }] },
        },
      };
      const result: DispatchResult = await new Dispatcher().dispatch(request, {
        persist: false, generationRepository: repository,
      });

      expect(result.success).assertFalse();
      expect(result.generation?.status).assertEqual('needs-input');
      expect(result.generation?.issues[0].code).assertEqual('MISSING_USER_FACT');
    });

    it('blocks preview on contradicted evidence and exposes the process issue', 0, async () => {
      const repository: FakeRepository = new FakeRepository();
      const model: ContradictoryKnowledgeModel = new ContradictoryKnowledgeModel();
      const request: DispatchRequest = {
        source: 'app', payload: { kind: 'text', text: '定义与例子存在冲突。' }, generation: {
          runId: 'contradiction-101', instruction: '完整保留定义和例子', mode: 'create',
          sources: { fragments: [{ id: 'source-a', kind: 'conversation', originId: 'm-a', sequence: 0, fingerprint: 'a', text: '定义与例子存在冲突。' }, {
            id: 'source-b', kind: 'ocr', originId: 'o-b', sequence: 1, fingerprint: 'b', text: '例：f(x)=x。',
          }] },
        },
      };
      const result: DispatchResult = await new Dispatcher().dispatch(request, {
        persist: false, generationRepository: repository, knowledgeModel: model,
      });

      expect(result.success).assertFalse();
      expect(result.generation?.status).assertEqual('needs-input');
      expect(result.generation?.verification?.status).assertEqual('contradicted');
      expect(result.generation?.issues.some((issue: NoteGenerationIssue): boolean => issue.code === 'EVIDENCE_CONTRADICTED')).assertTrue();
      expect(result.generation?.outline?.sections.length).assertEqual(2);
      expect(model.calls).assertEqual(1);
    });

    it('repairs only the failed standard candidate and keeps checkpoint lineage metadata', 0, async () => {
      const repository: FakeRepository = new FakeRepository();
      const model: RepairingKnowledgeModel = new RepairingKnowledgeModel();
      const request: DispatchRequest = {
        source: 'app', payload: { kind: 'text', text: '定义与例子存在冲突。' }, generation: {
          runId: 'repair-102', instruction: '完整保留定义和例子', mode: 'create',
          sources: { fragments: [{ id: 'source-a', kind: 'conversation', originId: 'm-a', sequence: 0, fingerprint: 'a', text: '函数在闭区间上连续。' }, {
            id: 'source-b', kind: 'ocr', originId: 'o-b', sequence: 1, fingerprint: 'b', text: '例：f(x)=x 在 [0,1] 上连续。',
          }] },
        },
      };

      const result: DispatchResult = await new Dispatcher().dispatch(request, {
        persist: false, generationRepository: repository, knowledgeModel: model,
      });

      expect(result.success).assertTrue();
      expect(result.generation?.status).assertEqual('ready-preview');
      expect(result.generation?.stopReason).assertEqual('repair_complete');
      expect(repository.checkpoints.length).assertEqual(2);
      expect(repository.checkpoints[1].parentId).assertEqual(repository.checkpoints[0].id);
      expect(repository.checkpoints[1].iteration).assertEqual(1);
      expect(repository.checkpoints[0].coverage).not().assertNull();
      expect(repository.checkpoints[1].tokenCost).not().assertNull();
      expect(repository.checkpoints[1].decision).assertEqual('best');
    });

    it('diminishing_returns rolls back to the best checkpoint after two rounds without improvement', 0, async () => {
      const repository: FakeRepository = new FakeRepository();
      const model: DiminishingKnowledgeModel = new DiminishingKnowledgeModel();
      const request: DispatchRequest = {
        source: 'app', payload: { kind: 'text', text: '定义与例子存在冲突。' }, generation: {
          runId: 'diminishing-102', instruction: '完整保留定义和例子', mode: 'create',
          sources: { fragments: [{ id: 'source-a', kind: 'conversation', originId: 'm-a', sequence: 0, fingerprint: 'a', text: '函数在闭区间上连续。' }, {
            id: 'source-b', kind: 'ocr', originId: 'o-b', sequence: 1, fingerprint: 'b', text: '例：f(x)=x 在 [0,1] 上连续。',
          }] },
        },
      };

      const result: DispatchResult = await new Dispatcher().dispatch(request, {
        persist: false, generationRepository: repository, knowledgeModel: model,
      });

      expect(result.success).assertFalse();
      expect(result.generation?.stopReason).assertEqual('diminishing_returns');
      expect(result.generation?.progress?.rollback).assertTrue();
      expect(result.generation?.bestCheckpointId).assertEqual('diminishing-102:0');
      expect(repository.checkpoints.length).assertEqual(3);
      expect(repository.checkpoints[0].decision).assertEqual('initial');
      expect(repository.checkpoints[2].decision).assertEqual('rejected');
    });

    it('selects deep deterministically and preserves semantic segments and the tail mapping', 0, async () => {
      const sources: SourceBundle = { fragments: [{
        id: 'ocr-page-1', kind: 'ocr', originId: 'page-1', sequence: 0, fingerprint: 'p1',
        text: '# 定义\n函数 f(x) 连续。\n\n证明：\n第一步：设 x=0。\n第二步：因此结论成立。',
      }, {
        id: 'ocr-page-2', kind: 'ocr', originId: 'page-2', sequence: 1, fingerprint: 'p2',
        text: '例子：\nf(x)=x^2。\n\n结论：尾部材料必须保留。',
      }] };
      expect(selectGenerationRoute(sources, '请给出完整详细证明和推导')).assertEqual('deep');
      const segments = segmentSourceBundle(sources);
      expect(segments.length > 2).assertTrue();
      expect(segments.some((segment): boolean => segment.text.includes('尾部材料'))).assertTrue();
      expect(deepBudget().maxRepairRounds > 0).assertTrue();

      const repository: FakeRepository = new FakeRepository();
      const model: DeepKnowledgeModel = new DeepKnowledgeModel();
      const request: DispatchRequest = {
        source: 'app', payload: { kind: 'text', text: '请给出完整详细证明和推导' }, generation: {
          runId: 'deep-103', instruction: '请给出完整详细证明和推导，保留例子', mode: 'create', sources: sources,
        },
      };
      const result: DispatchResult = await new Dispatcher().dispatch(request, {
        persist: false, generationRepository: repository, knowledgeModel: model,
      });
      expect(result.success).assertTrue();
      expect(result.generation?.route).assertEqual('deep');
      expect(result.generation?.outline?.sections.length).assertEqual(2);
      expect(result.generation?.outline?.sections[1].sourceIds[0]).assertEqual('ocr-page-2');
      expect(repository.checkpoints.length > 0).assertTrue();
      expect(model.calls).assertEqual(1);
    });

    it('returns needs-input instead of silently dropping sources over the deep source budget', 0, async () => {
      const hugeText: string = '证明步骤和公式。'.repeat(5000);
      const repository: FakeRepository = new FakeRepository();
      const request: DispatchRequest = {
        source: 'app', payload: { kind: 'text', text: hugeText }, generation: {
          runId: 'deep-budget-103', instruction: '详细证明', mode: 'create', sources: {
            fragments: [{ id: 'huge-source', kind: 'conversation', originId: 'message', sequence: 0, fingerprint: 'huge', text: hugeText }],
          },
        },
      };
      const result: DispatchResult = await new Dispatcher().dispatch(request, {
        persist: false, generationRepository: repository,
      });
      expect(result.success).assertFalse();
      expect(result.generation?.route).assertEqual('deep');
      expect(result.generation?.status).assertEqual('needs-input');
      expect(result.generation?.issues.some((issue): boolean => issue.code === 'SOURCE_BUDGET_EXCEEDED')).assertTrue();
      expect(result.generation?.issues.some((issue): boolean => issue.message.includes('huge-source'))).assertTrue();
    });
  });
}
