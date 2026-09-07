// MindTrace - CaptureGraph 图状态与节点契约
// 2026-09-05 · D2 Ticket #12

import { ClassificationResult, DispatchPayload, KnowledgeUnit, TruthCheckResult } from 'common';

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
  // 原始调度入参 — capture 节点 (OcrNode) 依赖它触达 image/file/text 三类 payload;
  // capture 之后的节点不再消费, 允许被丢弃 (spec 011 payload→state 管线修复, 2026-09-06)
  payload?: DispatchPayload;
  classification?: ClassificationResult;
  knowledgeUnit?: KnowledgeUnit;
  truthCheck?: TruthCheckResult;
  error?: CaptureGraphError;
  currentStep: CaptureStep;
  persist: boolean;
}

export interface CaptureNodeResult {
  state: AgentState;
}

export type CaptureNode = (state: AgentState) => Promise<CaptureNodeResult>;
