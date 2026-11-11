/**
 * ConversationNodeHost.ets — 节点处理器依赖的宿主能力
 *
 * 路径: agents/src/main/ets/conversation/ConversationNodeHost.ets
 * 职责: 把 ConversationWorkflow 对节点处理器暴露的能力收成一个显式接口，
 *       处理器只依赖这个接口，不再直接读工作流的私有字段
 * 依赖: common、../chat/*
 *
 * 数据流:
 *   ConversationWorkflow（宿主实现） → IConversationNodeHost → 各 NodeHandler
 */
import type {
  CancellationToken,
  ClassificationResult,
  ConversationRunRef,
  NoteEvidenceContext,
  NoteEvidencePort,
  NoteGenerationContextResult,
  NoteReviewPort,
} from 'common';
import type { ReplyContext } from '../chat/IntentClassifier';
import type {
  IConversationCapturePort, IConversationIntentPort, IConversationReplyPort, IConversationToolPort,
} from './ConversationWorkflowPorts';
import type { ChatMessageOrigin, ChatMessageOutcome, ConversationProgressStep } from './ConversationState';
import type { ConversationWorkflowCallbacks } from './ConversationTypes';
import type { ConversationReviewHandler } from './ConversationReviewHandler';

export interface IConversationNodeHost {
  /** UI 回调集合（消息增删改、终态、诊断）。 */
  nodeCallbacks(): ConversationWorkflowCallbacks;
  replyPort(): IConversationReplyPort;
  reviewPort(): NoteReviewPort;
  capturePort(): IConversationCapturePort;
  intentPort(): IConversationIntentPort;

  reviewHandler(): ConversationReviewHandler;
  toolReplyPort(): IConversationToolPort | undefined;
  evidencePort(): NoteEvidencePort;

  /** 统一的错误文案提取（脱敏由调用方决定）。 */
  errorMessage(error: Object): string;
  rawErrorMessage(error: Object): string;
  errorCodeOf(error: Object): number;
  userFacingError(error: Object): string;
  failureOutcome(error: Object): ChatMessageOutcome;

  setStep(ref: ConversationRunRef, step: ConversationProgressStep): void;
  originFor(ref: ConversationRunRef): ChatMessageOrigin;
  cancellationToken(ref: ConversationRunRef): CancellationToken | undefined;

  createReplyContext(
    memoryContext: string,
    learnerProfileContext: string,
    userContent: string,
    evidence: NoteEvidenceContext | undefined,
  ): ReplyContext;

  ensureNotCancelled(ref: ConversationRunRef): void;
  safeSaveOcrResult(
    ref: ConversationRunRef,
    imageUri: string,
    userText: string,
    result: ClassificationResult,
  ): Promise<string | null>;
  addAiMessage(
    ref: ConversationRunRef,
    content: string,
    origin?: ChatMessageOrigin,
    outcome?: ChatMessageOutcome,
  ): Promise<void>;
  finishRunFailure(ref: ConversationRunRef, error: Object, outcome?: ChatMessageOutcome): void;
  safeSaveUserMessage(ref: ConversationRunRef, content: string): Promise<void>;
  safeSaveAssistantMessage(ref: ConversationRunRef, content: string, messageId: number): Promise<void>;
  safeGetStructuredContextForNoteGeneration(
    ref: ConversationRunRef,
    instruction: string,
    inlineMaterial: string,
    currentConversationText: string,
  ): Promise<NoteGenerationContextResult | undefined>;
  safeUpdateLearnerProfileIfNeeded(ref: ConversationRunRef): Promise<void>;
  safeSummarizeIfNeeded(ref: ConversationRunRef): Promise<void>;
}
