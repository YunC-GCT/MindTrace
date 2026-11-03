/**
 * ConversationPortsProduction.ets — 对话端口的 entry 侧组合根
 *
 * 路径: entry/src/main/ets/services/ConversationPortsProduction.ets
 * 职责: 把 AiService / AgentMemoryService / 证据与复习实现包成 agents 端口，
 *       连同 filesDir 一起交给 ConversationWorkflowPortsFactory
 * 依赖: @kit.AbilityKit、agents 端口、entry 服务
 *
 * 数据流:
 *   EntryAbility / ConversationRuntime → buildProductionConversationPorts → ConversationWorkflow
 */
import { common } from '@kit.AbilityKit';
import {
  ChatMessageWriteRequest,
  ClassificationResult,
  KnowledgeUnit,
  NoteContextClarification,
  NoteDraftReadyEvent,
  NoteGenerationContextResult,
  NoteGenerationProgressSink,
  NoteGenerationRoute,
  NoteGenerationRun,
  NoteTopicCandidate,
  SourceBundle,
  SourceFragment,
} from 'common';
import type { AgentMemoryRecord, CancellationToken } from 'common';
import {
  NoteReviewService,
  ConversationWorkflowPorts,
  ConversationWorkflowPortsFactory,
} from 'agents';
import type {
  ConversationWorkflowPortsInput,
  IConversationCapturePort,
  IConversationDraftServicePort,
  IConversationMemoryServicePort,
  IConversationNoteRoutePort,
} from 'agents';
import { AiService } from './AiService';
import { AgentMemoryService } from './AgentMemoryService';
import { createNoteEvidenceService, NoteEvidenceService } from './NoteEvidenceService';
import { DefaultNoteReviewEvidenceProvider } from './NoteReviewEvidenceProviders';

class ConversationCaptureAdapter implements IConversationCapturePort {
  private readonly ai: AiService;

  constructor(context: common.UIAbilityContext) { this.ai = new AiService(context); }

  async analyzeImage(
    imageUri: string,
    userText: string,
    token?: CancellationToken,
  ): Promise<ClassificationResult> {
    return await this.ai.analyzeImage(imageUri, userText, token);
  }

  async generateNoteDraftWithSources(
    runId: string,
    instruction: string,
    sourceText: string,
    pendingSources: SourceFragment[],
    token?: CancellationToken,
    originSessionId?: string,
    parentConversationRunId?: string,
    route?: NoteGenerationRoute,
    progressSink?: NoteGenerationProgressSink,
  ): Promise<NoteDraftReadyEvent> {
    return await this.ai.generateNoteDraftWithSources(
      runId,
      instruction,
      sourceText,
      pendingSources,
      token,
      originSessionId,
      parentConversationRunId,
      route,
      progressSink,
    );
  }

  async generateNoteDraftWithBundle(
    runId: string,
    instruction: string,
    bundle: SourceBundle,
    pendingSourceIds: string[],
    contextBudgetTokens: number,
    token?: CancellationToken,
    originSessionId?: string,
    parentConversationRunId?: string,
    route?: NoteGenerationRoute,
    progressSink?: NoteGenerationProgressSink,
  ): Promise<NoteDraftReadyEvent> {
    return await this.ai.generateNoteDraftWithBundle(
      runId,
      instruction,
      bundle,
      pendingSourceIds,
      contextBudgetTokens,
      token,
      originSessionId,
      parentConversationRunId,
      route,
      progressSink,
    );
  }

  async saveNoteContextClarification(
    runId: string,
    instruction: string,
    bundle: SourceBundle,
    topics: NoteTopicCandidate[],
    pendingSourceIds: string[],
    contextBudgetTokens: number,
    originSessionId?: string,
    parentConversationRunId?: string,
    route?: NoteGenerationRoute,
  ): Promise<NoteContextClarification> {
    return await this.ai.saveNoteContextClarification(
      runId,
      instruction,
      bundle,
      topics,
      pendingSourceIds,
      contextBudgetTokens,
      originSessionId,
      parentConversationRunId,
      route,
    );
  }

  async resumeNoteContextClarification(
    runId: string,
    topicId: string,
    token?: CancellationToken,
    progressSink?: NoteGenerationProgressSink,
  ): Promise<NoteDraftReadyEvent> {
    return await this.ai.resumeNoteContextClarification(runId, topicId, token, progressSink);
  }

  async regenerateNoteDraft(
    runId: string,
    noteId: string,
    instruction: string,
    sourceText: string,
    token?: CancellationToken,
    originSessionId?: string,
    parentConversationRunId?: string,
    progressSink?: NoteGenerationProgressSink,
  ): Promise<NoteDraftReadyEvent> {
    return await this.ai.regenerateNoteDraft(
      runId,
      noteId,
      instruction,
      sourceText,
      token,
      originSessionId,
      parentConversationRunId,
      progressSink,
    );
  }
}

class ConversationDraftServiceAdapter implements IConversationDraftServicePort {
  private readonly ai: AiService;

  constructor(ai: AiService) { this.ai = ai; }

  restoreDraft(runId: string): Promise<NoteDraftReadyEvent> { return this.ai.restoreDraft(runId); }

  confirmDraft(event: NoteDraftReadyEvent, candidate: KnowledgeUnit): Promise<KnowledgeUnit> {
    return this.ai.confirmDraft(event, candidate);
  }

  cancelDraft(runId: string): Promise<void> { return this.ai.cancelDraft(runId); }

  retryDraft(runId: string): Promise<NoteDraftReadyEvent> { return this.ai.retryDraft(runId); }

  listRecoverableDrafts(): Promise<NoteGenerationRun[]> { return this.ai.listRecoverableDrafts(); }

  regenerateNoteDraft(
    runId: string,
    noteId: string,
    instruction: string,
    sourceText: string,
    token?: CancellationToken,
    originSessionId?: string,
    parentConversationRunId?: string,
    progressSink?: NoteGenerationProgressSink,
  ): Promise<NoteDraftReadyEvent> {
    return this.ai.regenerateNoteDraft(
      runId, noteId, instruction, sourceText, token,
      originSessionId, parentConversationRunId, progressSink,
    );
  }
}

class ConversationMemoryServiceAdapter implements IConversationMemoryServicePort {
  private readonly memory: AgentMemoryService;

  constructor(memory: AgentMemoryService) { this.memory = memory; }

  saveMessage(request: ChatMessageWriteRequest): Promise<void> {
    return this.memory.saveMessage(request);
  }

  saveOcrResult(
    sessionId: string,
    imageUri: string,
    userText: string,
    result: ClassificationResult,
  ): Promise<string> {
    return this.memory.saveOcrResult(sessionId, imageUri, userText, result);
  }

  getStructuredContextForNoteGeneration(
    sessionId: string,
    instruction: string,
    inlineMaterial: string,
    currentConversationText: string,
    currentRunId: string,
  ): Promise<NoteGenerationContextResult> {
    return this.memory.getStructuredContextForNoteGeneration(
      sessionId, instruction, inlineMaterial, currentConversationText, currentRunId,
    );
  }

  updateLearnerProfileIfNeeded(sessionId: string, token?: CancellationToken): Promise<void> {
    return this.memory.updateLearnerProfileIfNeeded(sessionId, token);
  }

  summarizeSessionIfNeeded(sessionId: string, token?: CancellationToken): Promise<void> {
    return this.memory.summarizeSessionIfNeeded(sessionId, token);
  }

  getPendingNoteMaterials(sessionId: string): Promise<AgentMemoryRecord[]> {
    return this.memory.getPendingNoteMaterials(sessionId);
  }

  getContextForReply(sessionId: string): Promise<string> {
    return this.memory.getContextForReply(sessionId);
  }

  getContextForNoteGeneration(sessionId: string): Promise<string> {
    return this.memory.getContextForNoteGeneration(sessionId);
  }

  getLearnerProfileContext(sessionId: string): Promise<string> {
    return this.memory.getLearnerProfileContext(sessionId);
  }
}

export function buildProductionConversationPorts(
  context: common.UIAbilityContext,
  noteRoute?: IConversationNoteRoutePort,
): ConversationWorkflowPorts {
  const ai: AiService = new AiService(context);
  const input: ConversationWorkflowPortsInput = {
    filesDir: context.filesDir,
    capture: new ConversationCaptureAdapter(context),
    draftService: new ConversationDraftServiceAdapter(ai),
    memoryService: new ConversationMemoryServiceAdapter(new AgentMemoryService(context)),
    evidence: new NoteEvidenceService(),
    review: new NoteReviewService(new DefaultNoteReviewEvidenceProvider(createNoteEvidenceService())),
    noteRoute: noteRoute,
  };
  return ConversationWorkflowPortsFactory.production(input);
}
