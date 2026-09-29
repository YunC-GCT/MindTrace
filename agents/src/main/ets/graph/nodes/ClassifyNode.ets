// MindTrace - ClassifyNode
// 2026-09-05 · D2 Ticket #4
import { AgentState, CaptureGraphError, CaptureNode, CaptureNodeResult, copyAgentState } from '../AgentState';
import { ClassificationResult } from 'common';
import { TypeClassifier } from '../../agents/TypeClassifier';

export class ClassifyNodeFactory {
  static create(classifier: TypeClassifier): CaptureNode {
    return async (input: AgentState): Promise<CaptureNodeResult> => {
      input.cancellationToken?.throwIfCancelled();
      const classification: ClassificationResult = await classifier.classifyText(input.captureText);
      input.cancellationToken?.throwIfCancelled();
      const next: AgentState = copyAgentState(input);
      next.classification = classification;
      if (input.payload?.kind === 'image' && classification.ocrTextQuality !== 'refined') {
        const error: CaptureGraphError = {
          kind: 'CAPTURE_TEXT_REFINEMENT_FAILED',
          message: '图片文字清洗失败，请重试或重新拍照',
          step: 'classify',
          retriable: true,
        };
        next.error = error;
        return { state: next };
      }
      if (classification.ocrText !== undefined && classification.ocrText.trim().length > 0) {
        next.captureText = classification.ocrText;
      }
      return { state: next };
    };
  }
}
