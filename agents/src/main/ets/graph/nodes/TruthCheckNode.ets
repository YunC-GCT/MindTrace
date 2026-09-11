// MindTrace - TruthCheckNode
// 2026-09-05 · D2 Ticket #5
import { AgentState, CaptureGraphError, CaptureNode, CaptureNodeResult, copyAgentState } from '../AgentState';
import { TruthCheckResult } from 'common';
import { TruthCheckService } from '../../agents/TruthCheckService';

export class TruthCheckNodeFactory {
  static create(service: TruthCheckService): CaptureNode {
    return async (input: AgentState): Promise<CaptureNodeResult> => {
       const truthInput: string = (input.generationRequest !== undefined || input.preparedCandidate !== undefined) && input.knowledgeUnit !== undefined
         ? input.captureText + '\n' + input.knowledgeUnit.content
         : input.captureText;
       const result = service.check(truthInput);
      const messages: string[] = [];
      for (const detail of result.details) {
        if (!detail.passed) {
          messages.push(detail.checkName + ': ' + detail.issues.join(','));
        }
      }
      const truthCheck: TruthCheckResult = {
        passed: result.truthFlag,
        flags: [],
        message: messages.join('; '),
      };
      const next: AgentState = copyAgentState(input);
      next.truthCheck = truthCheck;
      if (!result.truthFlag) {
        const error: CaptureGraphError = {
          kind: 'TRUTH_CHECK_ERROR',
          message: truthCheck.message ?? 'TruthCheck failed',
          step: 'truth_check',
          retriable: false,
        };
        next.error = error;
      }
      return { state: next };
    };
  }
}
