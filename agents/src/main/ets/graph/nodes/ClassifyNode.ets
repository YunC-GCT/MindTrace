// MindTrace - ClassifyNode
// 2026-09-05 · D2 Ticket #4
import { AgentState, CaptureNode, CaptureNodeResult, copyAgentState } from '../AgentState';
import { ClassificationResult } from 'common';
import { TypeClassifier } from '../../agents/TypeClassifier';

export class ClassifyNodeFactory {
  static create(classifier: TypeClassifier): CaptureNode {
    return async (input: AgentState): Promise<CaptureNodeResult> => {
      const classification: ClassificationResult = await classifier.classifyText(input.captureText);
      const next: AgentState = copyAgentState(input);
      next.classification = classification;
      return { state: next };
    };
  }
}
