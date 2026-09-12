// common HSP - public API 入口
// W1 块 3: 暴露 Agent 业务所需的最小子集(Dispatcher 侧)

// ========== 设计 Token (颜色 / 尺寸 / 字号) ==========
export {
  MINT, MINT_DARK, MINT_LIGHT, MINT_GLOW, MINT_BORDER,
  PURPLE, PURPLE_DARK, PURPLE_LIGHT, PINK, PINK_LIGHT, AMBER,
  BG_DARK, BG_CARD,
  SUBJECT_COLORS, TYPE_COLORS,
  TEXT, TEXT_2, TEXT_3, TEXT_4,
  BORDER,
  S_1, S_2, S_3, S_4, S_5, S_6,
  R_SM, R_MD, R_LG, R_XL, R_2XL, R_FULL,
  F_XS, F_SM, F_BASE, F_MD, F_LG, F_XL, F_2XL, F_3XL,
  SCREEN_W, SCREEN_H,
  HEADER_H, FAB_SIZE, HERO_RING_SIZE, NOTE_ICON_SIZE, DOT_SIZE, AVATAR_SIZE, AI_SETTINGS_BTN_H, CAM_SHUTTER_OUTER, CAM_SHUTTER_INNER, CAM_BTN_SIZE, CAM_ALBUM_SIZE, CAM_CONFIRM_H,
  TAB_BAR_HEIGHT, TAB_ICON_SIZE, TAB_BTN_RADIUS, AI_BTN_SIZE, AI_ICON_SIZE,
  DANGER, DANGER_BRIGHT, WARNING, SUCCESS,
  GLASS_8, GLASS_10, GLASS_14, CAM_OVERLAY_BG, CAM_PREVIEW_BG, CAM_MASK,
  OVERLAY_MASK, OVERLAY_MASK_SOLID,
  W_NORMAL, W_MEDIUM, W_SEMIBOLD, W_BOLD,
  LH_TIGHT, LH_BASE, LH_COMFORT, LH_LOOSE, LH_HEADING,
  SHADOW_FAB, SHADOW_GLOW_MINT, SHADOW_AI_BTN,
  DUR_INSTANT, DUR_FAST, DUR_BASE, DUR_SLOW, DUR_SLOWER, DUR_SLOWEST, DUR_BREATH,
} from './constants/ColorTokens';

// ========== Mock 笔记数据 (UI 开发期) ==========
export {
  NoteItem, NOTES, stripMD, recentDate,
} from './data/MockNotes';

// ========== 笔记分类与取色 ==========
export {
  NOTE_TYPE_ALL_KEY,
  NOTE_TYPE_KEYS,
  noteTypeFilterKeys,
  typeChar, typeColor, typeGlassColor,
  subjectColor, subjectColorByIndex, subjectGlassColor, subjectBorderColor,
  glassToneColor, glassSurfaceColor, glassHighlightColor, glassShadowColor, borderToneColor,
  normalizeNoteType, isKnownNoteType,
} from './data/NoteTaxonomy';

// ========== Agent 共享类型 (Dispatcher 侧) ==========
export {
  KnowledgeUnit,
  ReviewRecord,
  KGNode,
  KGEdge,
} from './models/CommonTypes';
export {
  DifficultyLevel,
  ConfidenceLevel,
  ReviewStatus,
  IntentType,
  AgentTask,
  AgentResponse,
  ApiError,
} from './models/CommonTypes';

// ========== D1 拍照链类型 (Agent 业务) ==========
export {
  ClassificationInput,
  ClassificationResult,
  TruthFlag,
  TruthCheckResult,
  DispatchRequest,
  DispatchResult,
  ApiResponse,
  API_CODE,
  CLASSIFY_CONFIDENCE_THRESHOLD,
} from './models/CaptureChain';
export type { ApiCode, DispatchPayload, ImagePayload, TextPayload, FilePayload, NoteCategory } from './models/CaptureChain';
export type {
  NoteGenerationMode,
  SourceKind,
  NoteGenerationRoute,
  NoteGenerationStatus,
  DraftSectionState,
  SourceFragment,
  SourceBundle,
  NoteGenerationRequirement,
  NoteGenerationRequest,
  NoteDraftSection,
  NoteDraftDocument,
  NoteGenerationIssue,
  ProcessIssue,
  NoteGenerationOutlineSection,
  NoteGenerationOutline,
  EvidenceItemType,
  EvidenceVerificationStatus,
  EvidenceSourceRef,
  NoteGenerationEvidenceItem,
  NoteGenerationVerification,
  NoteGenerationEvidenceDecision,
  NoteGenerationStandardResult,
  NoteGenerationLedgerEntry,
  NoteGenerationLedger,
  NoteGenerationSegment,
  NoteGenerationDeepResult,
  NoteGenerationBudget,
  NoteGenerationCoverage,
  NoteGenerationCheckpointDecision,
  NoteGenerationProgress,
  NoteGenerationRun,
  NoteGenerationCheckpoint,
  NoteDraftReadyEvent,
  PreparedCandidate,
  NoteGenerationRecovery,
  NoteGenerationResult,
  NoteGenerationRepository,
  NoteGenerationCommitResult,
  NoteGenerationLifecycleEvent,
  NoteGenerationLifecycleLog,
  IncrementalSectionState,
  IncrementalDiffKind,
  IncrementalSection,
  IncrementalManifestSection,
  IncrementalManifest,
  IncrementalRequirement,
  IncrementalPlan,
  IncrementalPatch,
  IncrementalDiffItem,
  IncrementalMergeResult,
  IncrementalBase,
  IncrementalPatchResponse,
 } from './models/NoteGenerationModels';
export {
  NOTE_DRAFT_SCHEMA_VERSION,
  NOTE_DRAFT_JSON_SCHEMA,
  NOTE_OUTLINE_SCHEMA_VERSION,
  NOTE_EVIDENCE_SCHEMA_VERSION,
  NOTE_VERIFICATION_SCHEMA_VERSION,
  NOTE_OUTLINE_JSON_SCHEMA,
  NOTE_EVIDENCE_JSON_SCHEMA,
  NOTE_VERIFICATION_JSON_SCHEMA,
  NOTE_STANDARD_JSON_SCHEMA,
  defaultRequirement,
  selectLightRoute,
  selectGenerationRoute,
  lightBudget,
  standardBudget,
  deepBudget,
  segmentSourceBundle,
  buildDeepOutline,
  validateDeepOutline,
  sourceFingerprint,
  buildSourceId,
  stableSectionId,
  validateSourceBundle,
  normalizeOutline,
  validateDraftDocument,
  validateDraftShape,
  parseIncrementalSections,
  buildIncrementalManifest,
  detectIncrementalLocks,
  planIncrementalChange,
  mergeIncrementalPatches,
   renderIncrementalSections,
   buildJsonSchema,
   parseDirectStandardArtifacts,
  } from './models/NoteGenerationModels';
export { NoteGenerationEvidenceVerifier } from './models/NoteGenerationModels';

// ========== 统一日志 ==========
export {
  LogLevel,
  Logger,
  defaultLog,
  getLogger,
} from './utils/logger';

// ========== LLM 共享基础设施 (Z 2026-07-14, PR1 2026-09-06, PR2-T1 2026-09-07) ==========
//   LlmConfig:  单例, preferences 持久化 endpoint/model/temp/maxTokens/timeoutMs/EnableThinking/vendorId/customVendor,
//               API key 委托 ApiKeyVault (TEE + AES256-GCM 加密),
//               getEndpoint/getModel 按 vendorId 解析(PR2-T1: 5 厂商预设 + 自定义)
//   LlmClient:  OpenAI 兼容 HTTP 客户端, 所有 agent 统一调用
//   LlmError:   统一错误类型, 按 kind 分类(NO_API_KEY / NETWORK_ERROR / API_ERROR / ...)
//   LlmTypes:   ChatMessage / LlmCallRequest / LlmCallResult / LlmErrorKind
//   ApiKeyVault: 凭据 vault (@kit.AssetStoreKit, 兼容读取旧 preferences key)
//   providers:  5 厂商预设(DeepSeek / Tongyi / GLM / Kimi / Doubao) + findProvider 工厂
export { LlmConfig, DEFAULT_ENABLE_THINKING } from './llm/LlmConfig';
export { ApiKeyVault } from './security/ApiKeyVault';
export { LlmClient } from './llm/LlmClient';
export { LlmGuard } from './llm/LlmGuard';
export { JSON_ONLY_RULES, LATEX_GENERATION_RULES, buildGuardRetryMessage } from './llm/LlmOutputRules';
export { LlmError, STREAM_EVENT_TYPES } from './llm/LlmTypes';
export { PROVIDERS, DEFAULT_VENDOR_ID, findProvider } from './llm/providers';
export type { ProviderConfig, CustomVendorConfig } from './llm/providers';
export type {
  ChatMessage,
  LlmCallOptions,
  LlmCallRequest,
  LlmCallResult,
  LlmErrorKind,
  LlmFunctionCallNameArgs,
  LlmFunctionDefinition,
  LlmToolCall,
  LlmToolDefinition,
  LlmResponseFormat,
  LlmJsonSchema,
  StreamEvent,
  StreamEventType,
  StreamThinkingEvent,
  StreamTextEvent,
  StreamToolCallEvent,
  StreamToolResultEvent,
} from './llm/LlmTypes';
export type { LlmGuardJsonOptions, LlmGuardJsonResult, LlmGuardValidationResult, LlmJsonValidator } from './llm/LlmGuard';
export type { LlmCaller } from './llm/LlmGuard';
export { ToolRegistry } from './tools/ToolRegistry';
export { ToolCatalog } from './tools/ToolCatalog';
export { ToolLoop } from './tools/ToolLoop';
export { StateGraph, StateGraphError } from './workflow/StateGraph';
export type { AgentTool, ToolResult } from './tools/ToolRegistry';
export type { StateGraphNode, StateGraphRoute, StateGraphHalt, StateGraphErrorKind } from './workflow/StateGraph';
export type { ToolLoopOptions } from './workflow/tool-calling/ToolCallingState';
export { NoteQueryTool, NoteGetTool, ReviewDueQueryTool, createReadOnlyNoteTools } from './tools/NoteQueryTools';

// ========== OCR 端点配置 (2026-07-17 P0 修复) ==========
//   OcrConfig:  单例, preferences 持久化 endpoint + enabled, 真机部署改 IP
export { OcrConfig } from './ocr/OcrConfig';

// ========== 数据库 (持久化存储) ==========
export { DatabaseHelper } from './DatabaseHelper';

// ========== 学习计划模型 ==========
export { StudyPlanItem } from './models/StudyPlan';

// ========== 文件 URI / MIME 共享工具 ==========
export { mimeFromExtension, extFromUri, fileNameFromUri } from './utils/FileUriUtils';
export { uuid, shortId } from './utils/uuid';
export { LatexRiskNormalizer } from './utils/LatexRiskNormalizer';
export type {
  LatexRiskLevel,
  LatexRenderMode,
  LatexSegmentKind,
  RenderSegment,
  LatexRiskResult,
} from './utils/LatexRiskNormalizer';

// ========== MM-MD-v1 内容渲染协议 ==========
export { ContentProtocol } from './render/ContentProtocol';
export { ContentExcerptBuilder } from './render/ContentExcerptBuilder';
export type {
  ContentProtocolRisk,
  ContentValidationResult,
} from './render/ContentProtocol';

// ========== D4 Kit facade 接缝契约 (spec 013) ==========
//   只声明契约, 不 import @kit.*; 实现由 entry 层注入
export type {
  ReviewReminderRequest,
  ReminderFacade,
} from './kit/ReminderFacade';
export type {
  BackgroundTaskTag,
  BackgroundTaskFacade,
} from './kit/BackgroundTaskFacade';
export type {
  CardSnapshot,
  FormCardFacade,
} from './kit/FormCardFacade';
export { CardSnapshotBinding } from './kit/FormCardFacade';
export { CardSnapshotStore } from './kit/CardSnapshotStore';
