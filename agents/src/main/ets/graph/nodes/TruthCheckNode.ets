// MindTrace - TruthCheckNode
// 2026-09-05 · D2 Ticket #5
import { AgentState, CaptureGraphError, CaptureNode, CaptureNodeResult, copyAgentState } from '../AgentState';
import { RunContext, TruthCheckResult } from 'common';
import { TruthCheckService } from '../../agents/TruthCheckService';

export class TruthCheckNodeFactory {
  static create(service: TruthCheckService): CaptureNode {
    return async (input: AgentState, context?: RunContext | null): Promise<CaptureNodeResult> => {
       context?.throwIfStopped();
       const truthInput: string = input.knowledgeUnit !== undefined
         ? input.knowledgeUnit.content
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
      context?.throwIfStopped();
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
