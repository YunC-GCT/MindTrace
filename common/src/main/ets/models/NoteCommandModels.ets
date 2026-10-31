/**
 * NoteCommandModels.ets — 笔记流水线的命令 / 终态契约（ADR-0019 实现）
 *
 * 路径: common/src/main/ets/models/NoteCommandModels.ets
 * 职责: 定义 `NoteCommand`（五种命令形状）与 `NoteOutcome`（五种终态）。
 *       调用方只读 `outcome.kind` 做穷举 switch；`DispatchResult` 退化为旧调用方的迁移适配器。
 * 依赖: CaptureChain（DispatchPayload / DispatchSource 口径）、NoteGenerationModels（生成请求/问题）。
 *
 * ArkTS 1.1 约束（与 ADR-0019 的 TS 伪码差异）:
 *   ADR 用对象联合 `A | B | C`；ArkTS 1.1 不允许对象字面量联合类型（arkts-no-untyped-obj-literals
 *   与联合类型成员访问限制），因此这里用「单一 interface + `kind` 判别字段 + 分字段注释」表达同一份契约。
 *   调用方必须 switch `kind` 后再读对应字段；mapper（NoteOutcomeMapper）是唯一允许构造 outcome 的地方。
 */
import type { ClassificationResult, DispatchPayload } from './CaptureChain';
import type { KnowledgeUnit } from './CommonTypes';
import type {
  NoteGenerationIssue,
  NoteGenerationRequest,
  NoteGenerationResult,
  PreparedCandidate,
} from './NoteGenerationModels';

// 与 DispatchRequest.source 同域（ADR-0019 (a) 的 DispatchSource）。
export type DispatchSource = 'app' | 'skill' | 'card';

export type NoteCommandKind = 'capture' | 'generation' | 'regenerate' | 'preparedCandidate' | 'analysisOnly';

export type NoteOutcomeKind = 'needsInput' | 'readyPreview' | 'committed' | 'failed' | 'cancelled';

// 降级不是失败：保留成功终态并附上「从哪降到哪、为什么」。
export interface DegradedMarker {
  from: string;
  to: string;
  reason: string;
}

/**
 * NoteCommand — 一次调用只带一个 kind，其余字段按 kind 取用：
 *   capture          : source + payload（默认持久化；commitKey 缺省由持久层合成）
 *   generation       : generation（含 route / sources / instruction）
 *   regenerate       : generation（mode === 'regenerate'，带 targetNoteId / baseVersion）
 *   preparedCandidate: preparedCandidate（自带 candidateHash / commitKey / expectedVersion）
 *   analysisOnly     : source + payload（不落库，只出分类）
 * operationId 用于日志 / 回执关联；commitKey 是幂等键（capture 缺省由 PersistNode 合成）。
 */
export interface NoteCommand {
  kind: NoteCommandKind;
  operationId: string;
  source?: DispatchSource;
  payload?: DispatchPayload;
  commitKey?: string;
  generation?: NoteGenerationRequest;
  preparedCandidate?: PreparedCandidate;
  includeRawText?: boolean;
}

/**
 * NoteOutcome — 一次命令恰好一个终态：
 *   committed   : noteId + version + commitKey 必须来自写端口/事务结果（ADR-0019 (d)）
 *   readyPreview: 生成/增量重生成产出的草稿 + checkpointId + runId
 *   needsInput  : 用户可修复的问题（不是失败），带 issues[]
 *   failed      : 稳定错误码 + retryable；消息只作展示
 *   cancelled   : committed 表示取消前是否已经落库（true 时必须带 noteId/version/commitKey）
 */
export interface NoteOutcome {
  kind: NoteOutcomeKind;
  operationId: string;
  route: 'D1';
  durationMs: number;
  // committed
  noteId?: string;
  version?: number;
  commitKey?: string;
  unit?: KnowledgeUnit;
  // readyPreview
  runId?: string;
  checkpointId?: string;
  draft?: KnowledgeUnit;
  // needsInput / failed
  reason?: string;
  issues?: NoteGenerationIssue[];
  // failed
  code?: string;
  message?: string;
  retryable?: boolean;
  // cancelled
  committed?: boolean;
  // 兼容字段（旧 DispatchResult 的透传，供迁移期调用方使用）
  classification?: ClassificationResult;
  recognizedText?: string;
  generation?: NoteGenerationResult;
  degraded?: DegradedMarker;
}

// 入口取消：CancellationToken 抛出的错误消息（ADR-0019 (e) 位置 1）。
export const NOTE_CANCELLED_MESSAGE: string = 'CONVERSATION_CANCELLED';

// 允许重试的错误码：传输层瞬时失败与输入可重拍（ADR-0019 (c)）。
const RETRYABLE_CODES: string[] = [
  'NETWORK_ERROR',
  'TIMEOUT',
  'STREAM_FAILED',
  'OCR_FAILED',
  'CAPTURE_TEXT_REFINEMENT_FAILED',
];

export function isRetryableNoteErrorCode(code: string): boolean {
  return RETRYABLE_CODES.indexOf(code) >= 0;
}
