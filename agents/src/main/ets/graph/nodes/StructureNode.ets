// MindTrace - StructureNode
// 2026-09-05 · D2 Ticket #5
import { AgentState, CaptureNode, CaptureGraphError, CaptureNodeResult, copyAgentState } from '../AgentState';
import { KnowledgeModel } from '../../agents/KnowledgeModel';
import { GenerationJsonError } from '../../agents/GenerationJsonCaller';
import { KnowledgeUnit, LlmError, NoteDraftDocument, NoteGenerationStandardResult } from 'common';

export class StructureNodeFactory {
  static create(service: KnowledgeModel): CaptureNode {
    return async (input: AgentState): Promise<CaptureNodeResult> => {
      try {
        input.cancellationToken?.throwIfCancelled();
        let draft: NoteDraftDocument | undefined = undefined;
        let standardResult: NoteGenerationStandardResult | undefined = undefined;
        let unit: KnowledgeUnit;
        if (input.generationRequest !== undefined) {
          if (input.generationRequest.route === 'standard') {
            standardResult = await service.structureStandardDraft(input.generationRequest);
            if (standardResult.verification.status === 'contradicted'
              || standardResult.verification.status === 'ambiguous'
              || StructureNodeFactory.hasHardIssues(standardResult)) {
              const gateError: CaptureGraphError = {
                kind: 'STANDARD_GATE_FAILED',
                message: StructureNodeFactory.standardGateMessage(standardResult),
                step: 'structure',
                retriable: false,
              };
              const blocked: AgentState = copyAgentState(input);
              blocked.standardResult = standardResult;
              blocked.draft = standardResult.draft;
              blocked.error = gateError;
              return { state: blocked };
            }
            draft = standardResult.draft;
          } else {
            // The draft is generated once; the candidate remains a direct mapping
            // owned by KnowledgeModel and is then checked by TruthCheckNode.
            draft = await service.structureLightDraft(input.generationRequest);
          }
          unit = service.draftToKnowledgeUnit(draft, input.source);
        } else if (input.classification === undefined) {
          unit = await service.structure(input.captureText);
        } else {
          unit = await service.structureWithClassification(input.captureText, input.classification, input.source);
        }
        const next: AgentState = copyAgentState(input);
        next.cancellationToken?.throwIfCancelled();
        next.knowledgeUnit = unit;
        if (draft !== undefined) {
          next.draft = draft;
        }
        if (standardResult !== undefined) {
          next.standardResult = standardResult;
        }
        return { state: next };
      } catch (e) {
        // §13.5 (2026-09-19): retriable 按错误类型映射 —
        // GenerationJsonError.retriable (传输类可重试) / LlmError 网络类 kind /
        // 其余 (校验/截断/解析/未知) 一律 false; kind 恒 'STRUCTURE_ERROR'
        let retriable: boolean = false;
        if (e instanceof GenerationJsonError) {
          retriable = e.retriable;
        } else if (e instanceof LlmError) {
          retriable = e.kind === 'NETWORK_ERROR' || e.kind === 'TIMEOUT' || e.kind === 'STREAM_FAILED';
        }
        const error: CaptureGraphError = {
          kind: 'STRUCTURE_ERROR',
          message: e instanceof Error ? e.message : String(e),
          step: 'structure',
          retriable: retriable,
        };
        const next: AgentState = copyAgentState(input);
        next.error = error;
        return { state: next };
      }
    };
  }

  private static standardGateMessage(result: NoteGenerationStandardResult): string {
    const codes: string[] = [];
    for (const issue of result.verification.issues) {
      codes.push(issue.code);
    }
    return 'standard process gate failed: ' + codes.join(',');
  }

  private static hasHardIssues(result: NoteGenerationStandardResult): boolean {
    for (const issue of result.verification.issues) {
      if (issue.severity === 'hard') {
        return true;
      }
    }
    return false;
  }
}
