/**
 * ConversationServicePorts.ets — 对话子流程依赖的服务端口
 *
 * 路径: agents/src/main/ets/conversation/ConversationServicePorts.ets
 * 职责: 让草稿推进与记忆投影不持有 UIAbilityContext，也不直接 new AiService /
 *       AgentMemoryService；实现由 entry 组合根注入
 * 依赖: common
 *
 * 数据流:
 *   ConversationWorkflowPorts → 本文件端口 → ConversationDraftWorkflow / ConversationMemoryProjection
 */
import {
  AgentMemoryRecord,
  CancellationToken,
  ChatMessageWriteRequest,
  ClassificationResult,
  KnowledgeUnit,
  NoteDraftReadyEvent,
  NoteGenerationContextResult,
  NoteGenerationProgressSink,
  NoteGenerationRun,
} from 'common';

export interface IConversationDraftServicePort {
  restoreDraft(runId: string): Promise<NoteDraftReadyEvent>;
  confirmDraft(event: NoteDraftReadyEvent, candidate: KnowledgeUnit): Promise<KnowledgeUnit>;
  cancelDraft(runId: string): Promise<void>;
  retryDraft(runId: string): Promise<NoteDraftReadyEvent>;
  listRecoverableDrafts(): Promise<NoteGenerationRun[]>;
  regenerateNoteDraft(
    runId: string,
    noteId: string,
    instruction: string,
    sourceText: string,
    cancellationToken?: CancellationToken,
    originSessionId?: string,
    parentConversationRunId?: string,
    progressSink?: NoteGenerationProgressSink,
  ): Promise<NoteDraftReadyEvent>;
}

export interface IConversationMemoryServicePort {
  saveMessage(request: ChatMessageWriteRequest): Promise<void>;
  saveOcrResult(
    sessionId: string,
    imageUri: string,
    userText: string,
    result: ClassificationResult,
  ): Promise<string>;
  getStructuredContextForNoteGeneration(
    sessionId: string,
    instruction: string,
    inlineMaterial: string,
    currentConversationText: string,
    currentRunId: string,
  ): Promise<NoteGenerationContextResult>;
  updateLearnerProfileIfNeeded(sessionId: string, cancellationToken?: CancellationToken): Promise<void>;
  summarizeSessionIfNeeded(sessionId: string, cancellationToken?: CancellationToken): Promise<void>;
  getPendingNoteMaterials(sessionId: string): Promise<AgentMemoryRecord[]>;
  getContextForReply(sessionId: string): Promise<string>;
  getContextForNoteGeneration(sessionId: string): Promise<string>;
  getLearnerProfileContext(sessionId: string): Promise<string>;
}
