// MindTrace - CaptureGraph 图状态与节点契约
// 2026-09-05 · D2 Ticket #12

import {
  ClassificationResult,
  DispatchPayload,
  KnowledgeUnit,
  NoteDraftDocument,
  NoteGenerationRequest,
  PreparedCandidate,
  TruthCheckResult,
  NoteGenerationStandardResult,
} from 'common';
import { NoteCommitResult } from '../models/NoteDaoInterface';
import type { CancellationToken } from 'common';

export type CaptureStep =
  | 'START'
  | 'capture'
  | 'classify'
  | 'structure'
  | 'truth_check'
  | 'persist'
  | 'END';

export interface CaptureGraphError {
  kind: string;
  message: string;
  step: CaptureStep;
  retriable: boolean;
  cause?: Object;
}

export interface AgentState {
  captureText: string;
  source: string;
  // 原始调度入参 — capture 节点 (OcrNode) 依赖它触达 image/file/text 三类 payload;
  // capture 之后的节点不再消费，但作为原始输入 channel 保留到 workflow 结束
  payload?: DispatchPayload;
  classification?: ClassificationResult;
  knowledgeUnit?: KnowledgeUnit;
  truthCheck?: TruthCheckResult;
  error?: CaptureGraphError;
  currentStep: CaptureStep;
  persist: boolean;
  analysisOnly: boolean;
  generationRequest?: NoteGenerationRequest;
  draft?: NoteDraftDocument;
  standardResult?: NoteGenerationStandardResult;
  preparedCandidate?: PreparedCandidate;
  commitResult?: NoteCommitResult;
  cancellationToken?: CancellationToken;
}

export interface CaptureNodeResult {
  state: AgentState;
}

export type CaptureNode = (state: AgentState) => Promise<CaptureNodeResult>;

export function copyAgentState(input: AgentState): AgentState {
  const copied: AgentState = {
    captureText: input.captureText,
    source: input.source,
    currentStep: input.currentStep,
    persist: input.persist,
    analysisOnly: input.analysisOnly,
  };
  if (input.payload !== undefined) {
    copied.payload = input.payload;
  }
  if (input.classification !== undefined) {
    copied.classification = input.classification;
  }
  if (input.knowledgeUnit !== undefined) {
    copied.knowledgeUnit = input.knowledgeUnit;
  }
  if (input.truthCheck !== undefined) {
    copied.truthCheck = input.truthCheck;
  }
  if (input.error !== undefined) {
    copied.error = input.error;
  }
  if (input.generationRequest !== undefined) {
    copied.generationRequest = input.generationRequest;
  }
  if (input.draft !== undefined) {
    copied.draft = input.draft;
  }
  if (input.standardResult !== undefined) {
    copied.standardResult = input.standardResult;
  }
  if (input.preparedCandidate !== undefined) {
    copied.preparedCandidate = input.preparedCandidate;
  }
  if (input.commitResult !== undefined) {
    copied.commitResult = input.commitResult;
  }
  if (input.cancellationToken !== undefined) {
    copied.cancellationToken = input.cancellationToken;
  }
  return copied;
}
