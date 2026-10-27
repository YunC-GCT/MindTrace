// MindTrace - OcrNode
// 2026-09-05 · D2 Ticket #4
// 2026-09-06 · payload→state 管线修复: capture 节点改读 state.payload,
//   不再接受被清空的 captureText; payload 缺失是编程错误, 显式报错不兜底 (spec 011 §9)
import { AgentState, CaptureGraphError, CaptureNode, CaptureNodeResult, copyAgentState } from '../AgentState';
import { TypeClassifier, TypeClassifierTextResult } from '../../agents/TypeClassifier';
import type { RunContext } from 'common';

export class OcrNodeFactory {
  static create(classifier: TypeClassifier): CaptureNode {
    return async (input: AgentState, context?: RunContext | null): Promise<CaptureNodeResult> => {
      if (input.payload === undefined) {
        const error: CaptureGraphError = {
          kind: 'CAPTURE_NO_PAYLOAD',
          message: 'capture node requires state.payload (seeded by Dispatcher START)',
          step: 'capture',
          retriable: false,
        };
        const failed: AgentState = copyAgentState(input);
        failed.error = error;
        return { state: failed };
      }
      context?.throwIfStopped();
      const recognized: TypeClassifierTextResult = await classifier.recognizeText(input.payload);
      context?.throwIfStopped();
      const next: AgentState = copyAgentState(input);
      next.captureText = recognized.text;
      return { state: next };
    };
  }
}
