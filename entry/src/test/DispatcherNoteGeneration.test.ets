/**
 * DispatcherNoteGeneration.test.ets — Issue 98 stable Capture seam tests.
 *
 * This test deliberately injects a KnowledgeModel test double. The production
 * path still enters only through Dispatcher.dispatch and never reaches a DAO
 * when persist=false.
 */
import { describe, it, expect } from '@ohos/hypium';
import { Dispatcher, DispatchOptions, NoteCommitResult, NoteDaoInterface } from 'agents';
import { KnowledgeModel } from 'agents';
import {
  DifficultyLevel,
  DispatchRequest,
  DispatchResult,
  KnowledgeUnit,
  LlmCallRequest,
  LlmCallResult,
  LlmCaller,
  NoteDraftDocument,
  NoteDraftSection,
  NoteGenerationEvidenceItem,
  NoteGenerationOutline,
  NoteGenerationOutlineSection,
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
  NoteGenerationProgressEvent,
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
  lastRun: NoteGenerationRun | undefined = undefined;

  async saveRun(_run: NoteGenerationRun, _bundle: SourceBundle): Promise<void> {
    this.runSaves += 1;
    this.lastRun = _run;
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

class VerifierContractFailureLlm implements LlmCaller {
  async call(request: LlmCallRequest): Promise<LlmCallResult> {
    const system: string = request.messages.length > 0 ? request.messages[0].content : '';
    if (system.includes('math note standard route')) {
      return { text: VerifierContractFailureLlm.standardArtifacts(), streamed: false };
    }
    if (system.includes('Act as an independent verifier')) {
      return {
        text: '{"status":"supported","issues":[],"checkedEvidenceIds":[],"decisions":[]}',
        streamed: false,
      };
    }
    if (system.includes('Return JSON only with an evidence array')) {
      return { text: '{"evidence":[]}', streamed: false };
    }
    throw new Error('unexpected LLM request in verifier failure fixture');
  }

  private static standardArtifacts(): string {
    return '{'
      + '"outline":{"schemaVersion":"mindtrace.note-outline.v1","sections":['
      + VerifierContractFailureLlm.outlineSection('section-one', '定义一', 0)
      + ',' + VerifierContractFailureLlm.outlineSection('section-two', '定义二', 1)
      + ',' + VerifierContractFailureLlm.outlineSection('section-three', '定义三', 2)
      + ',' + VerifierContractFailureLlm.outlineSection('section-four', '定义四', 3)
      + ',' + VerifierContractFailureLlm.outlineSection('section-five', '定义五', 4)
      + ']},'
      + '"evidence":['
      + VerifierContractFailureLlm.evidenceItem('pipeline-evidence-1', 'section-one', '第一条定义。')
      + ',' + VerifierContractFailureLlm.evidenceItem('pipeline-evidence-2', 'section-two', '第二条定义。')
      + ',' + VerifierContractFailureLlm.evidenceItem('pipeline-evidence-3', 'section-three', '第三条定义。')
      + ',' + VerifierContractFailureLlm.evidenceItem('pipeline-evidence-4', 'section-four', '第四条定义。')
      + ',' + VerifierContractFailureLlm.evidenceItem('pipeline-evidence-5', 'section-five', '第五条定义。')
      + '],'
      + '"draft":{"schemaVersion":"mindtrace.note-draft.v1","title":"五条定义",'
      + '"summary":"五条定义的整理","subject":"数学分析","category":"概念",'
      + '"chapter":"基础概念","difficulty":1,"tags":["定义"],"sections":['
      + VerifierContractFailureLlm.draftSection('section-one', '定义一', '第一条定义。')
      + ',' + VerifierContractFailureLlm.draftSection('section-two', '定义二', '第二条定义。')
      + ',' + VerifierContractFailureLlm.draftSection('section-three', '定义三', '第三条定义。')
      + ',' + VerifierContractFailureLlm.draftSection('section-four', '定义四', '第四条定义。')
      + ',' + VerifierContractFailureLlm.draftSection('section-five', '定义五', '第五条定义。')
      + ']}}';
  }

  private static outlineSection(id: string, label: string, order: number): string {
    return '{"id":"' + id + '","label":"' + label + '","order":' + order.toString()
      + ',"mustInclude":[],"sourceIds":["source-a"]}';
  }

  private static evidenceItem(id: string, sectionId: string, claim: string): string {
    return '{"id":"' + id + '","type":"definition","claim":"' + claim
      + '","sourceRefs":[{"sourceId":"source-a","excerpt":"' + claim
      + '","start":0,"end":0}],"targetSectionId":"' + sectionId + '","verification":"supported"}';
  }

  private static draftSection(id: string, label: string, content: string): string {
    return '{"id":"' + id + '","label":"' + label + '","content":"' + content
      + '","sourceIds":["source-a"],"state":"generated","baseHash":"' + id + '-hash"}';
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
    const definitionSectionId: string = stableSectionId(0, '定义');
    const exampleSectionId: string = stableSectionId(1, '例子');
    const outline: NoteGenerationOutline = {
      schemaVersion: 'mindtrace.note-outline.v1',
      sections: [{
        id: definitionSectionId,
        label: '定义',
        order: 0,
        mustInclude: ['定义'],
        sourceIds: ['source-a'],
      }, {
        id: exampleSectionId,
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
      targetSectionId: definitionSectionId,
      verification: 'supported',
    }, {
      id: 'evidence-example',
      type: 'example',
      claim: '函数 f(x)=x 在 [0,1] 上连续。',
      sourceRefs: [{ sourceId: 'source-b', excerpt: '例：f(x)=x 在 [0,1] 上连续。', start: 0, end: 25 }],
      targetSectionId: exampleSectionId,
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
        id: definitionSectionId,
        label: '定义',
        content: '函数在闭区间上连续。',
        sourceIds: ['source-a'],
        state: 'generated',
        baseHash: 'hash-definition',
      }, {
        id: exampleSectionId,
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
      sections: [{ id: 'section-proof', label: '证明', content: '推导：保留全部步骤。\nx = 1', sourceIds: [firstSource], state: 'generated', baseHash: 'proof' }, {
        id: 'section-example', label: '例子', content: '例子：保留尾部材料。\nx = 2', sourceIds: [lastSource], state: 'generated', baseHash: 'example',
      }],
    };
    const ledger: NoteGenerationLedger = { formulas: [], terminology: [], conclusions: [] };
    return { outline: outline, evidence: [], draft: draft, verification: { status: 'supported', issues: [], checkedEvidenceIds: [], decisions: [] }, ledger: ledger };
  }
}

class RequestedSectionsDeepKnowledgeModel extends KnowledgeModel {
  receivedSections: string[] = [];

  async structureDeepDraft(request: NoteGenerationRequest): Promise<NoteGenerationDeepResult> {
    this.receivedSections = request.requirement?.requestedSections ?? [];
    const sourceId: string = request.sources.fragments[0].id;
    const outlineSections: NoteGenerationOutlineSection[] = [];
    const draftSections: NoteDraftSection[] = [];
    for (let index: number = 0; index < this.receivedSections.length; index += 1) {
      const label: string = this.receivedSections[index];
      const sectionId: string = stableSectionId(index, label);
      outlineSections.push({
        id: sectionId,
        label: label,
        order: index,
        mustInclude: [label],
        sourceIds: [sourceId],
        depth: 0,
        parentId: index === 0 ? undefined : stableSectionId(index - 1, this.receivedSections[index - 1]),
        segmentIds: [],
      });
      draftSections.push({
        id: sectionId,
        label: label,
        content: label + '：本节覆盖用户指定章节。',
        sourceIds: [sourceId],
        state: 'generated',
        baseHash: 'hash-' + index.toString(),
      });
    }
    const outline: NoteGenerationOutline = {
      schemaVersion: 'mindtrace.note-outline.v1',
      sections: outlineSections,
    };
    const draft: NoteDraftDocument = {
      schemaVersion: 'mindtrace.note-draft.v1',
      title: '连续函数与中值定理',
      summary: '四个指定章节',
      subject: '数学分析',
      category: '定理',
      chapter: '微分学',
      difficulty: 3,
      tags: ['中值定理'],
      instruction: request.instruction,
      sections: draftSections,
    };
    const ledger: NoteGenerationLedger = { formulas: [], terminology: [], conclusions: [] };
    return { outline: outline, evidence: [], draft: draft, verification: { status: 'supported', issues: [], checkedEvidenceIds: [], decisions: [] }, ledger: ledger };
  }
}

class DeepDiagnosticsKnowledgeModel extends DeepKnowledgeModel {
  async structureDeepDraft(request: NoteGenerationRequest): Promise<NoteGenerationDeepResult> {
    const result: NoteGenerationDeepResult = await super.structureDeepDraft(request);
    result.draft.sections[0].content = '推导：保留全部步骤。\n$$\nx = 1\n$$';
    result.draft.sections[1].content = '例子：保留尾部材料。\n$$\nx = 2\n$$';
    const issues: NoteGenerationIssue[] = [{
      stage: 'merge',
      code: 'DEEP_SECTION_DUPLICATE_CONTENT',
      severity: 'hard',
      message: 'deep sections duplicate the same content',
      repairable: true,
      sectionId: 'section-example',
      sourceId: 'source-b',
    }, {
      stage: 'merge',
      code: 'DEEP_SYMBOL_DRIFT',
      severity: 'hard',
      message: 'deep sections use inconsistent formula symbols',
      repairable: true,
      sectionId: 'section-example',
    }, {
      stage: 'merge',
      code: 'DEEP_REFERENCE_INVALID',
      severity: 'hard',
      message: 'deep section contains an unresolved cross-section reference',
      repairable: true,
      sectionId: 'section-example',
    }, {
      stage: 'outline',
      code: 'DEEP_SOURCE_INVALID',
      severity: 'hard',
      message: 'deep outline references an unknown source',
      repairable: false,
      sectionId: 'section-proof',
      sourceId: 'source-missing',
    }, {
      stage: 'merge',
      code: 'DEEP_MUST_INCLUDE_MISSING',
      severity: 'hard',
      message: 'deep draft does not cover must-include: 公式',
      repairable: true,
    }];
    result.verification = {
      status: 'ambiguous',
      issues: issues,
      checkedEvidenceIds: result.verification.checkedEvidenceIds,
      decisions: result.verification.decisions,
    };
    return result;
  }

  async repairDeepDraft(
    _request: NoteGenerationRequest,
    current: NoteGenerationDeepResult,
    _issues: NoteGenerationIssue[],
  ): Promise<NoteGenerationDeepResult> {
    return current;
  }
}

class SoftSymbolDriftKnowledgeModel extends DeepKnowledgeModel {
  async structureDeepDraft(request: NoteGenerationRequest): Promise<NoteGenerationDeepResult> {
    const result: NoteGenerationDeepResult = await super.structureDeepDraft(request);
    result.draft.sections[0].content = '推导：保留全部步骤。\n$$\nx = 1\n$$';
    result.draft.sections[1].content = '例子：保留尾部材料。\n$$\nx = 0\n$$';
    return result;
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
      code: 'EVIDENCE_CONTRADICTED',
      severity: 'hard',
      message: 'candidate did not improve',
      repairable: true,
      sourceId: 'r' + this.repairRound.toString(),
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

class CountingNoteDao implements NoteDaoInterface {
  private readonly counter: CountingDao;
  private readonly rowId: number;
  private readonly commitKeyOverride: string;

  constructor(counter: CountingDao, rowId: number, commitKeyOverride: string = '') {
    this.counter = counter;
    this.rowId = rowId;
    this.commitKeyOverride = commitKeyOverride;
  }

  async insert(_unit: KnowledgeUnit): Promise<number> {
    this.counter.writes += 1;
    return this.rowId;
  }

  async insertWithCommitKey(unit: KnowledgeUnit, commit: NoteGenerationCommitResult): Promise<NoteCommitResult> {
    this.counter.writes += 1;
    const result: NoteCommitResult = {
      commitKey: this.commitKeyOverride.length > 0 ? this.commitKeyOverride : commit.commitKey,
      rowId: this.rowId,
      noteId: unit.id,
      version: unit.version,
      duplicate: false,
    };
    return result;
  }
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
      expect(result.generation?.questions !== undefined && result.generation.questions.length > 0).assertTrue();
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
          originSessionId: 's1',
          parentConversationRunId: 'r101',
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
      const progressEvents: NoteGenerationProgressEvent[] = [];
      const testDao: NoteDaoInterface = new CountingNoteDao(dao, 1);
      const options: DispatchOptions = {
        persist: false,
        dao: testDao,
        generationRepository: repository,
        knowledgeModel: model,
        progressSink: (event: NoteGenerationProgressEvent): void => { progressEvents.push(event); },
      };
      const result: DispatchResult = await new Dispatcher().dispatch(request, options);

      expect(result.success).assertTrue();
      expect(result.data?.title).assertEqual(unitForTest.title);
      expect(result.generation?.route).assertEqual('light');
      expect(result.generation?.status).assertEqual('ready-preview');
      expect(dao.writes).assertEqual(0);
      expect(repository.checkpointSaves).assertEqual(1);
      expect(repository.lastRun?.originSessionId).assertEqual('s1');
      expect(repository.lastRun?.parentConversationRunId).assertEqual('r101');
      expect(progressEvents[0].phase).assertEqual('prepare');
      expect(progressEvents[0].state).assertEqual('running');
      expect(progressEvents[progressEvents.length - 1].phase).assertEqual('compose');
      expect(progressEvents[progressEvents.length - 1].state).assertEqual('success');

      const generated: KnowledgeUnit = result.data ?? unitForTest;
      const prepared: PreparedCandidate = {
        runId: 'light-98',
        checkpointId: 'light-98:0',
        candidateHash: sourceFingerprint(JSON.stringify(generated)),
        candidate: generated,
        commitKey: 'light-98:light-98:0:confirmed',
      };
      const commitDao: NoteDaoInterface = new CountingNoteDao(dao, 2, prepared.commitKey ?? '');
      const confirmRequest: DispatchRequest = {
        source: 'app',
        payload: { kind: 'text', text: generated.content },
        preparedCandidate: prepared,
      };
      const confirmOptions: DispatchOptions = {
        persist: true,
        generationRepository: repository,
        dao: commitDao,
      };
      const confirmResult: DispatchResult = await new Dispatcher().dispatch(confirmRequest, confirmOptions);
      const duplicateRequest: DispatchRequest = {
        source: 'app',
        payload: { kind: 'text', text: generated.content },
        preparedCandidate: prepared,
      };
      const duplicateOptions: DispatchOptions = {
        persist: true,
        generationRepository: repository,
        dao: commitDao,
      };
      const duplicateResult: DispatchResult = await new Dispatcher().dispatch(duplicateRequest, duplicateOptions);
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
      const candidate: KnowledgeUnit = result.data ?? unitForTest;
      const checkpoint: NoteGenerationCheckpoint = repository.checkpoints[0];
      expect(checkpoint.candidateHash).assertEqual(sourceFingerprint(JSON.stringify(candidate)));
      const restoredCandidate: KnowledgeUnit = JSON.parse(checkpoint.documentJson) as KnowledgeUnit;
      expect(restoredCandidate.title).assertEqual(candidate.title);
    });

    it('stops before content repair when the independent verifier is unavailable', 0, async () => {
      const repository: FakeRepository = new FakeRepository();
      const progressEvents: NoteGenerationProgressEvent[] = [];
      const sourceText: string = '第一条定义。\n第二条定义。\n第三条定义。\n第四条定义。\n第五条定义。';
      const request: DispatchRequest = {
        source: 'app',
        payload: { kind: 'text', text: sourceText },
        generation: {
          runId: 'verifier-unavailable-101',
          instruction: '整理笔记',
          mode: 'create',
          route: 'standard',
          sources: { fragments: [{
            id: 'source-a',
            kind: 'conversation',
            originId: 'message-a',
            sequence: 0,
            fingerprint: 'source-a-fingerprint',
            text: sourceText,
          }] },
        },
      };
      const result: DispatchResult = await new Dispatcher().dispatch(request, {
        persist: false,
        generationRepository: repository,
        knowledgeModel: new KnowledgeModel(new VerifierContractFailureLlm()),
        progressSink: (event: NoteGenerationProgressEvent): void => { progressEvents.push(event); },
      });

      expect(result.success).assertFalse();
      expect(result.generation?.stopReason).assertEqual('verifier_unavailable');
      expect(repository.checkpointSaves).assertEqual(1);
      expect(progressEvents.some((event: NoteGenerationProgressEvent): boolean =>
        event.activity === 'repair_draft')).assertFalse();
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

    it('passes requested section titles from instruction into deep generation', 0, async () => {
      const instruction: string = '请整理“连续函数、可导性与中值定理”的复习笔记。\n'
        + '要求生成结构化笔记，包含 4 个 section：\n'
        + '1. 连续函数的定义与判断方法\n'
        + '2. 可导与连续的关系\n'
        + '3. 拉格朗日中值定理\n'
        + '4. 常见错误与自测题\n'
        + '每个 section 包含：核心定义、直观解释、关键公式、一个例子、一个常见误区。';
      const model: RequestedSectionsDeepKnowledgeModel = new RequestedSectionsDeepKnowledgeModel();
      const repository: FakeRepository = new FakeRepository();
      const request: DispatchRequest = {
        source: 'app',
        payload: { kind: 'text', text: instruction },
        generation: {
          runId: 'deep-requested-sections-107',
          instruction: instruction,
          mode: 'create',
          route: 'deep',
          sources: { fragments: [{
            id: 'source-lagrange',
            kind: 'conversation',
            originId: 'message-lagrange',
            sequence: 0,
            fingerprint: 'lagrange',
            text: instruction,
          }] },
        },
      };

      const result: DispatchResult = await new Dispatcher().dispatch(request, {
        persist: false,
        generationRepository: repository,
        knowledgeModel: model,
      });

      expect(result.success).assertTrue();
      expect(model.receivedSections.length).assertEqual(4);
      expect(model.receivedSections[0]).assertEqual('连续函数的定义与判断方法');
      expect(model.receivedSections[1]).assertEqual('可导与连续的关系');
      expect(model.receivedSections[2]).assertEqual('拉格朗日中值定理');
      expect(model.receivedSections[3]).assertEqual('常见错误与自测题');
      expect(result.generation?.outline?.sections[2].label).assertEqual('拉格朗日中值定理');
    });

    it('does not treat prose assignments as cross-section formula drift', 0, async () => {
      const repository: FakeRepository = new FakeRepository();
      const model: DeepKnowledgeModel = new DeepKnowledgeModel();
      const request: DispatchRequest = {
        source: 'app',
        payload: { kind: 'text', text: '请给出完整详细证明和推导' },
        generation: {
          runId: 'deep-local-equation-105',
          instruction: '请给出完整详细证明和推导，保留例子',
          mode: 'create',
          route: 'deep',
          sources: { fragments: [{
            id: 'source-a', kind: 'conversation', originId: 'message-a', sequence: 0,
            fingerprint: 'a', text: '推导材料。',
          }, {
            id: 'source-b', kind: 'conversation', originId: 'message-b', sequence: 1,
            fingerprint: 'b', text: '例子材料。',
          }] },
        },
      };

      const result: DispatchResult = await new Dispatcher().dispatch(request, {
        persist: false, generationRepository: repository, knowledgeModel: model,
      });

      expect(result.success).assertTrue();
      expect(result.generation?.issues.some((issue): boolean => issue.code === 'DEEP_SYMBOL_DRIFT')).assertFalse();
    });

    it('keeps explicit deep formula drift visible without blocking preview', 0, async () => {
      const repository: FakeRepository = new FakeRepository();
      const model: SoftSymbolDriftKnowledgeModel = new SoftSymbolDriftKnowledgeModel();
      const request: DispatchRequest = {
        source: 'app',
        payload: { kind: 'text', text: '请给出完整详细证明和推导' },
        generation: {
          runId: 'deep-soft-drift-106',
          instruction: '请给出完整详细证明和推导，保留例子',
          mode: 'create',
          route: 'deep',
          sources: { fragments: [{
            id: 'source-a', kind: 'conversation', originId: 'message-a', sequence: 0,
            fingerprint: 'a', text: '推导材料。公式 x = 1。',
          }, {
            id: 'source-b', kind: 'conversation', originId: 'message-b', sequence: 1,
            fingerprint: 'b', text: '例子材料。公式 x = 0。',
          }] },
        },
      };

      const result: DispatchResult = await new Dispatcher().dispatch(request, {
        persist: false, generationRepository: repository, knowledgeModel: model,
      });

      let driftIssue: NoteGenerationIssue | undefined = undefined;
      for (const issue of result.generation?.issues ?? []) {
        if (issue.code === 'DEEP_SYMBOL_DRIFT') {
          driftIssue = issue;
          break;
        }
      }
      expect(result.success).assertTrue();
      expect(result.generation?.status).assertEqual('ready-preview');
      expect(result.generation?.stopReason).assertEqual('deep_complete');
      expect(driftIssue !== undefined).assertTrue();
      expect(driftIssue?.severity).assertEqual('soft');
    });

    it('exposes complete deep diagnostics without truncating issue details', 0, async () => {
      const repository: FakeRepository = new FakeRepository();
      const model: DeepDiagnosticsKnowledgeModel = new DeepDiagnosticsKnowledgeModel();
      const request: DispatchRequest = {
        source: 'app',
        payload: { kind: 'text', text: '请给出完整详细证明和推导' },
        generation: {
          runId: 'deep-diagnostics-106',
          instruction: '请给出完整详细证明和推导',
          mode: 'create',
          route: 'deep',
          sources: { fragments: [{
            id: 'source-a', kind: 'conversation', originId: 'message-a', sequence: 0,
            fingerprint: 'a', text: '定义与推导。',
          }, {
            id: 'source-b', kind: 'ocr', originId: 'ocr-b', sequence: 1,
            fingerprint: 'b', text: '例子与公式。',
          }] },
        },
      };

      const result: DispatchResult = await new Dispatcher().dispatch(request, {
        persist: false, generationRepository: repository, knowledgeModel: model,
      });

      const diagnostics: string = result.generation?.diagnostics ?? '';
      expect(result.success).assertFalse();
      expect(result.generation?.stopReason).assertEqual('repeated_issue_fingerprint');
      expect(diagnostics.includes('DEEP_SECTION_DUPLICATE_CONTENT')).assertTrue();
      expect(diagnostics.includes('DEEP_SYMBOL_DRIFT')).assertTrue();
      expect(diagnostics.includes('DEEP_REFERENCE_INVALID')).assertTrue();
      expect(diagnostics.includes('DEEP_SOURCE_INVALID')).assertTrue();
      expect(diagnostics.includes('DEEP_MUST_INCLUDE_MISSING')).assertTrue();
      expect(diagnostics.includes('"sectionId":"section-example"')).assertTrue();
      expect(diagnostics.includes('"sourceId":"source-missing"')).assertTrue();
      expect(diagnostics.includes('"issueCount":6')).assertTrue();
      expect(diagnostics.includes('"tokenBudget":14000')).assertTrue();
      expect(diagnostics.includes('"estimatedTokenCost":')).assertTrue();
      expect(diagnostics.includes('"issues":[{')).assertTrue();
      expect(diagnostics.includes('previousFormula=x = 1')).assertTrue();
      expect(diagnostics.includes('currentFormula=x = 2')).assertTrue();
      expect(diagnostics.includes('previousSection=section-proof')).assertTrue();
      expect(diagnostics.includes('currentSection=section-example')).assertTrue();
    });

    it('downgrades an oversized deep request to standard without silently dropping sources', 0, async () => {
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
      expect(result.generation?.route).assertEqual('standard');
      expect(result.generation?.issues.some((issue): boolean => issue.code === 'SOURCE_BUDGET_EXCEEDED')).assertFalse();
      const savedSourceIds: string[] = repository.lastRun?.sourceIds ?? [];
      expect(savedSourceIds.includes('huge-source')).assertTrue();
    });
  });
}
