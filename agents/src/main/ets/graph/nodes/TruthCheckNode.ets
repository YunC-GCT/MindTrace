// MindTrace - TruthCheckNode
// 2026-09-05 · D2 Ticket #5
import { AgentState, CaptureNode, CaptureNodeResult } from '../AgentState';
import { TruthCheckResult } from 'common';
import { TruthCheckService } from '../../agents/TruthCheckService';

export class TruthCheckNodeFactory {
  static create(service: TruthCheckService): CaptureNode {
    return async (input: AgentState): Promise<CaptureNodeResult> => {
      const result = service.check(input.captureText);
      const truthCheck: TruthCheckResult = {
        passed: result.truthFlag === false,
        flags: [],
        message: result.details.map((d) => d.checkName).join(','),
      };
      const next: AgentState = {
        captureText: input.captureText,
        currentStep: input.currentStep,
        persist: input.persist,
        truthCheck: truthCheck,
      };
      return { state: next };
    };
  }
}
