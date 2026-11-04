// agents HSP - public API 入口
// W1 块 3 逐步展开真实 export(HMAFManager + 5 子 Agent)

// 当前版本
//   v0.0.1 (2026-07-13 骨架)
//   v0.0.2 (2026-07-14 LLM 共享基础设施 LlmConfig/LlmClient)
//   v0.0.3 (2026-07-14 BranchRequest.payload 升级 DispatchPayload discriminated union)
export const AGENTS_VERSION = 'v0.0.3';

// 主 Agent 调度中枢(Z)

export { CommandExecutor } from './core/CommandExecutor';
export { CommandRouter } from './core/CommandRouter';
export type { NoteWorkflowId, RouterPreflightResult } from './core/CommandRouter';
export type { DispatchOptions } from './core/CommandExecutor';
export { NullRunEventSink } from './core/dispatch/RunEventSink';
export type { DispatchRunEvent, RunEventSink } from './core/dispatch/RunEventSink';
export { TypeClassifier } from './subagents/TypeClassifier';
export type { TypeClassifierTextResult } from './subagents/TypeClassifier';
export { KnowledgeModel } from './subagents/KnowledgeModel';
export { PromptBuilder } from './subagents/PromptBuilder';
export { TruthCheckService } from './subagents/TruthCheckService';
export { normalizeSubjectName, sanitizeNoteTitle, CANONICAL_SUBJECTS } from './subagents/KnowledgeTaxonomy';
export type { SubjectNormalization, TitleSanitization } from './subagents/KnowledgeTaxonomy';
export { planCaptureSet } from './graph/captureSetPlanner';
export type { PlannedProblem, SetImageText, SetPlan } from './graph/captureSetPlanner';
export { OcrTool } from './mcp/tools/OcrTool';
export type { OcrRecognitionResult } from './mcp/tools/OcrTool';
export type { KnowledgeUnitExt, StructuredField, AiRawResponse } from './models/KnowledgeUnitExt';
export type { NoteDaoInterface, NoteCommitResult } from './models/NoteDaoInterface';
export type { CaptureProvenance, DispatchPayload } from 'common';
