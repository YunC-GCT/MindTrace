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

// 子 Agent(D 责任 - 写真实现,L 责任 - 写真实现)
//   当前为 stub,接 DispatchPayload discriminated union
//   D 接手: 替换 TypeClassifier.classify body
//   spec 015: KnowledgeModel 重构为轻量编排 agent, 常量/提示词/真值检查拆分为协作服务
export { TypeClassifier } from './agents/TypeClassifier';
export type { TypeClassifierTextResult } from './agents/TypeClassifier';
export { KnowledgeModel } from './agents/KnowledgeModel';
export { PromptBuilder } from './agents/PromptBuilder';
export { TruthCheckService } from './agents/TruthCheckService';
export { normalizeSubjectName, sanitizeNoteTitle, CANONICAL_SUBJECTS } from './agents/KnowledgeTaxonomy';
export type { SubjectNormalization, TitleSanitization } from './agents/KnowledgeTaxonomy';
export { planCaptureSet } from './graph/captureSetPlanner';
export type { PlannedProblem, SetImageText, SetPlan } from './graph/captureSetPlanner';
export { OcrTool } from './mcp/tools/OcrTool';
export type { OcrRecognitionResult } from './mcp/tools/OcrTool';

// 模型与扩展类型
export type { KnowledgeUnitExt, StructuredField, AiRawResponse } from './models/KnowledgeUnitExt';

// 持久化接口 (D2 Ticket #5: entry 通过该接口注入 NoteDao 实现)
export type { NoteDaoInterface, NoteCommitResult } from './models/NoteDaoInterface';

// 重新导出 DispatchPayload / CaptureProvenance 类型(定义在 common/models/CaptureChain.ets)
//   UI 端 (entry/) 可以 `import type { DispatchPayload, CaptureProvenance } from 'agents'`
//   也可以从 'common' 拿,两种都行
export type { CaptureProvenance, DispatchPayload } from 'common';

// 对话回复链路（2026-11-03 由 entry/services 上移，UI 与 :agent 进程共用）
export { IntentClassifier } from './chat/IntentClassifier';
export type { ReplyContext, ReplyKind, TextIntent } from './chat/IntentClassifier';
export { ModelRouter } from './chat/ModelRouter';
export type { RoutedReply } from './chat/ModelRouter';
export { CHAT_REPLY_POLICY, ReplyService, configureDebugFaultSource } from './chat/ReplyService';
export type { LlmCallPolicy, ReplyEventSink, StreamReplyResult } from './chat/ReplyService';

// App 内意图分类（2026-11-03 由 entry/services 上移）
export { AppIntentRouter } from './chat/AppIntentRouter';
export {
  INTENT_KINDS, INTENT_LABELS, buildAppIntentPrompt, classifyAppIntentLocal,
  isKnownAppIntent, parseAppIntentJson, validateAppIntentJson,
} from './chat/AppIntentRules';
export type { AppIntentDecision, AppIntentKind } from './chat/AppIntentRules';

// 对话图契约（2026-11-03 由 entry/workflows/conversation 上移）
export type {
  ChatMessageOrigin, ChatMessageOutcome, ConversationProgressStep, ConversationRequest,
  ConversationState, ConversationStep, ImageConversationRequest,
  RegenerateConversationRequest, TextConversationRequest,
} from './conversation/ConversationState';
export { CHAT_TOOL_REPLY_ENABLED, ConversationToolReplyFlags } from './conversation/ConversationToolReplyFlags';

// 对话图（2026-11-03 由 entry/workflows/conversation 上移，UI 上下文经端口注入）
export { ConversationWorkflow } from './conversation/ConversationWorkflow';
export {
  ConversationWorkflowPorts, ConversationWorkflowPortsFactory,
} from './conversation/ConversationWorkflowPorts';
export type {
  ConversationWorkflowPortsInput,
  IConversationCapturePort, IConversationIntentPort, IConversationNoteRoutePort,
  IConversationReplyPort, IConversationToolPort,
} from './conversation/ConversationWorkflowPorts';
export type {
  IConversationDraftServicePort, IConversationMemoryServicePort,
} from './conversation/ConversationServicePorts';
export { ConversationDraftWorkflow } from './conversation/ConversationDraftWorkflow';
export { ConversationMemoryProjection } from './conversation/ConversationMemoryProjection';
export type {
  ConversationErrorMessageEvent, ConversationMessageEvent, ConversationReplaceContentEvent,
  ConversationRunEventStatus, ConversationStatusMessageEvent, ConversationStreamMessageEvent,
  ConversationWorkflowCallbacks,
} from './conversation/ConversationTypes';

// 复习链（2026-11-03 由 entry/services 上移，证据经 provider 注入）
export { NoteReviewEvidenceProvider, NoteReviewService } from './review/NoteReviewService';

// 证据链（2026-11-03 由 entry/services 上移，数据经检索/图谱端口注入）
export { NoteEvidenceService, NoteEvidenceStreamFilter } from './evidence/NoteEvidenceService';

// 笔记生成上下文预处理（2026-11-03 由 entry/services 上移）
export { NoteGenerationContextBuilder } from './note/NoteGenerationContextBuilder';

// 笔记生成与校验的领域规则（2026-11-04 由 entry/services 上移）
export { NoteContextValidityReviewer } from './note/NoteContextValidityReviewer';
export { WritePathValidator } from './note/WritePathValidator';
export {
  groupExactDuplicates, groupNearDuplicates, normalizeKey, normalizeLegacySubject,
} from './note/LegacyNoteNormalizer';
export type {
  LegacyDedupeEntry, LegacyDuplicateGroup, LegacySubjectInput,
} from './note/LegacyNoteNormalizer';
export { ModelSelector } from './chat/ModelSelector';
export type { ModelAvailability } from './chat/ModelSelector';

// 笔记判重与回复排版规则（2026-11-04 由 common/utils 回迁）
export {
  bigramSimilarity, findDuplicate, isDuplicateOf, normalizeForDedupe,
} from './note/NoteDedupe';
export type { DedupeCandidate } from './note/NoteDedupe';
export { buildMathStyleRules } from './chat/ReplyStyleRules';
export type { ReplyStyle } from './chat/ReplyStyleRules';
export { streamErrorText } from './chat/StreamErrorText';
