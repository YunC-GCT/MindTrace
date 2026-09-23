/**
 * KnowledgeModelNoteGeneration.test.ets — note-generation normalization regressions
 *
 * 路径: agents/src/test/KnowledgeModelNoteGeneration.test.ets
 * 职责: 锁定 pipeline evidence 经过独立验证后仍保留 origin 标记
 * 依赖: @ohos/hypium; KnowledgeModel; common LLM and note-generation contracts
 *
 * 数据流:
 *   scripted standard JSON → KnowledgeModel normalization → verifier → origin assertion
 *
 * ArkTS 1.1 strict 适配:
 *   - LlmCaller 使用显式测试类注入,不使用结构类型对象字面量
 */
import { describe, it, expect } from '@ohos/hypium';
import { KnowledgeModel } from '../main/ets/agents/KnowledgeModel';
import type {
  LlmCallRequest,
  LlmCallResult,
  LlmCaller,
  NoteGenerationRequest,
} from 'common';

class StandardGenerationCaller implements LlmCaller {
  private callCount: number = 0;
  private verifierResponseMode: 'complete' | 'incomplete_then_complete' | 'wrong_field_then_complete' = 'complete';

  setVerifierResponseMode(mode: 'complete' | 'incomplete_then_complete' | 'wrong_field_then_complete'): void {
    this.verifierResponseMode = mode;
  }

  async call(_request: LlmCallRequest): Promise<LlmCallResult> {
    this.callCount += 1;
    if (this.callCount === 1) {
      const standardJson: string = '{'
        + '"outline":{"schemaVersion":"mm-note-outline-v1","sections":['
        + '{"id":"sec-1","label":"定义","order":0,"mustInclude":[],"sourceIds":["src-1"]}'
        + ']},'
        + '"evidence":[],'
        + '"draft":{"schemaVersion":"mm-note-draft-v1","title":"连续性",'
        + '"summary":"函数连续性的定义",'
        + '"subject":"数学分析","category":"概念","chapter":"连续性",'
        + '"difficulty":1,"tags":[],"sections":['
        + '{"id":"sec-1","label":"定义","content":"函数在一点连续。",'
        + '"sourceIds":["src-1"],"state":"generated","baseHash":""}]}}';
      return { text: standardJson, streamed: false };
    }
    if (this.verifierResponseMode === 'incomplete_then_complete' && this.callCount === 2) {
      const incompleteVerificationJson: string = '{'
        + '"status":"supported",'
        + '"decisions":[],"issues":[],"checkedEvidenceIds":[]}';
      return { text: incompleteVerificationJson, streamed: false };
    }
    if (this.verifierResponseMode === 'wrong_field_then_complete' && this.callCount === 2) {
      const wrongFieldVerificationJson: string = '{'
        + '"status":"supported",'
        + '"decisions":[{"id":"pipeline-evidence-1","status":"supported"}],'
        + '"issues":[],"checkedEvidenceIds":[]}';
      return { text: wrongFieldVerificationJson, streamed: false };
    }
    const verificationJson: string = '{'
      + '"status":"supported",'
      + '"decisions":[{"evidenceId":"pipeline-evidence-1","status":"supported"}],'
      + '"issues":[],"checkedEvidenceIds":["pipeline-evidence-1"]}';
    return { text: verificationJson, streamed: false };
  }
}

class LegacyDifficultyCaller implements LlmCaller {
  async call(_request: LlmCallRequest): Promise<LlmCallResult> {
    const response: string = '{'
      + '"schemaVersion":"mm-note-draft-v1","title":"连续函数",'
      + '"summary":"函数在一点连续","subject":"数学分析","category":"概念",'
      + '"chapter":"连续性","difficulty":5,"tags":["连续"],"sections":['
      + '{"id":"section-item-legacy","label":"定义","content":"函数在一点连续。",'
      + '"sourceIds":["src-1"],"state":"generated","baseHash":""}]}';
    return { text: response, streamed: false };
  }
}

function request(): NoteGenerationRequest {
  return {
    runId: 'origin-regression',
    instruction: '保留定义',
    mode: 'create',
    sources: {
      fragments: [{
        id: 'src-1',
        kind: 'conversation',
        originId: 'origin-1',
        sequence: 0,
        fingerprint: 'fp-1',
        text: '函数在一点连续。',
      }],
    },
  };
}

export default function knowledgeModelNoteGenerationTest(): void {
  describe('KnowledgeModel.pipeline_evidence_origin', () => {
    it('preserves_pipeline_origin_after_verification', 0, async () => {
      const model: KnowledgeModel = new KnowledgeModel(new StandardGenerationCaller());
      const result = await model.structureStandardDraft(request());
      expect(result.evidence.length).assertEqual(1);
      expect(result.evidence[0].origin).assertEqual('pipeline');
      expect(result.evidence[0].id).assertEqual('pipeline-evidence-1');
    });
  });

  describe('KnowledgeModel.independent_verifier_contract', () => {
    it('retries_when_verifier_does_not_cover_every_evidence_item', 0, async () => {
      const caller: StandardGenerationCaller = new StandardGenerationCaller();
      caller.setVerifierResponseMode('incomplete_then_complete');
      const model: KnowledgeModel = new KnowledgeModel(caller);
      const result = await model.structureStandardDraft(request());
      expect(result.verification.issues.length).assertEqual(0);
      expect(result.verification.decisions.length).assertEqual(1);
      expect(result.verification.decisions[0].evidenceId).assertEqual('pipeline-evidence-1');
    });

    it('retries_when_verifier_uses_the_wrong_evidence_id_field', 0, async () => {
      const caller: StandardGenerationCaller = new StandardGenerationCaller();
      caller.setVerifierResponseMode('wrong_field_then_complete');
      const model: KnowledgeModel = new KnowledgeModel(caller);
      const result = await model.structureStandardDraft(request());
      expect(result.verification.issues.length).assertEqual(0);
      expect(result.verification.decisions[0].evidenceId).assertEqual('pipeline-evidence-1');
    });
  });

  describe('KnowledgeModel.legacy_difficulty_contract', () => {
    it('normalizes_difficulty_five_to_a_valid_level', 0, async () => {
      const model: KnowledgeModel = new KnowledgeModel(new LegacyDifficultyCaller());
      const result = await model.structureLightDraft(request());
      expect(result.difficulty).assertEqual(2);
    });
  });
}
