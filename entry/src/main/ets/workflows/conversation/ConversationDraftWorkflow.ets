/**
 * ConversationDraftWorkflow.ets - session-owned draft operations.
 *
 * Path: entry/src/main/ets/workflows/conversation/ConversationDraftWorkflow.ets
 * Responsibility: enforce draft ownership and coordinate restore/confirm/cancel/retry.
 * Dependencies: AiService; ConversationWorkflowCallbacks; ConversationRunRef.
 *
 * Data flow:
 *   Session-owned draft command -> ownership validation -> AiService -> preview/commit result.
 */
import { common } from '@kit.AbilityKit';
import { KnowledgeUnit, NoteDraftReadyEvent, NoteGenerationRun } from 'common';
import { AiService } from '../../services/AiService';
import { ChatMessageOrigin, ChatMessageOutcome } from './ConversationState';
import { ConversationRunRef } from '../../services/ConversationIdentity';

export interface IConversationDraftWorkflowHost {
  draftContext(): common.UIAbilityContext;
  acceptsDraftRun(ref: ConversationRunRef): boolean;
  publishDraft(ref: ConversationRunRef, event: NoteDraftReadyEvent): void;
  addDraftMessage(
    ref: ConversationRunRef,
    content: string,
    origin: ChatMessageOrigin,
    outcome: ChatMessageOutcome,
  ): Promise<void>;
  draftOrigin(ref: ConversationRunRef): ChatMessageOrigin;
}

export interface IConversationDraftGateway {
  restore(runId: string): Promise<NoteDraftReadyEvent>;
  confirm(event: NoteDraftReadyEvent, candidate: KnowledgeUnit): Promise<KnowledgeUnit>;
  cancel(runId: string): Promise<void>;
  retry(runId: string): Promise<NoteDraftReadyEvent>;
  listRecoverable(): Promise<NoteGenerationRun[]>;
  regenerate(
    runId: string,
    noteId: string,
    instruction: string,
    sessionId: string,
    parentRunId: string,
  ): Promise<NoteDraftReadyEvent>;
}

class AiConversationDraftGateway implements IConversationDraftGateway {
  private readonly host: IConversationDraftWorkflowHost;
  private service: AiService | null = null;

  constructor(host: IConversationDraftWorkflowHost) { this.host = host; }

  async restore(runId: string): Promise<NoteDraftReadyEvent> {
    return await this.ai().restoreDraft(runId);
  }

  async confirm(event: NoteDraftReadyEvent, candidate: KnowledgeUnit): Promise<KnowledgeUnit> {
    return await this.ai().confirmDraft(event, candidate);
  }

  async cancel(runId: string): Promise<void> { await this.ai().cancelDraft(runId); }

  async retry(runId: string): Promise<NoteDraftReadyEvent> { return await this.ai().retryDraft(runId); }

  async listRecoverable(): Promise<NoteGenerationRun[]> { return await this.ai().listRecoverableDrafts(); }

  async regenerate(
    runId: string,
    noteId: string,
    instruction: string,
    sessionId: string,
    parentRunId: string,
  ): Promise<NoteDraftReadyEvent> {
    return await this.ai().regenerateNoteDraft(
      runId,
      noteId,
      instruction,
      instruction,
      undefined,
      sessionId,
      parentRunId,
    );
  }

  private ai(): AiService {
    if (this.service === null) { this.service = new AiService(this.host.draftContext()); }
    return this.service;
  }
}

export class ConversationDraftWorkflow {
  private readonly host: IConversationDraftWorkflowHost;
  private readonly gateway: IConversationDraftGateway;
  private pendingConfirmRunId: string | null = null;

  private constructor(host: IConversationDraftWorkflowHost, gateway?: IConversationDraftGateway) {
    this.host = host;
    this.gateway = gateway ?? new AiConversationDraftGateway(host);
  }

  static create(
    host: IConversationDraftWorkflowHost,
    gateway?: IConversationDraftGateway,
  ): ConversationDraftWorkflow {
    return new ConversationDraftWorkflow(host, gateway);
  }

  async confirm(
    ref: ConversationRunRef,
    event: NoteDraftReadyEvent,
    candidate: KnowledgeUnit,
  ): Promise<KnowledgeUnit> {
    this.requireOwnership(ref, event);
    if (this.pendingConfirmRunId !== null && this.pendingConfirmRunId === event.runId) {
      await this.addMessage(ref, '正在保存中，请勿重复点击。', 'failed');
      throw new Error('DUPLICATE_CONFIRM: 正在保存中');
    }
    const persistedEvent: NoteDraftReadyEvent = await this.gateway.restore(event.runId);
    this.requireOwnership(ref, persistedEvent);
    this.pendingConfirmRunId = event.runId;
    try {
      const committed: KnowledgeUnit = await this.gateway.confirm(event, candidate);
      await this.addMessage(ref, '已保存笔记：' + committed.title, 'completed');
      return committed;
    } catch (error) {
      const errorMessage: string = ConversationDraftWorkflow.errorMessage(error);
      const conflict: boolean = errorMessage.indexOf('VERSION_CONFLICT') >= 0;
      if (conflict && event.incrementalManifest !== undefined && event.expectedVersion !== undefined) {
        try {
          const instruction: string = event.incrementalInstruction ?? '请重新规划增量修改';
          const refreshed: NoteDraftReadyEvent = await this.gateway.regenerate(
            'replan-' + Date.now().toString(),
            event.incrementalManifest.noteId,
            instruction,
            ref.sessionId,
            ref.runId,
          );
          this.host.publishDraft(ref, refreshed);
          await this.addMessage(ref, '笔记版本已变化，已重新加载并生成新的预览，请再次确认。', 'completed');
        } catch (_replanError) {
          await this.addMessage(ref, '版本冲突且自动重规划失败，请重新整理笔记。', 'failed');
        }
      } else if (conflict) {
        await this.addMessage(ref, '笔记版本冲突，请重新整理笔记。', 'failed');
      } else {
        await this.addMessage(ref, '保存笔记失败: ' + errorMessage.substring(0, 120), 'failed');
      }
      throw new Error(errorMessage);
    } finally {
      this.pendingConfirmRunId = null;
    }
  }

  async restore(ref: ConversationRunRef, runId: string): Promise<NoteDraftReadyEvent> {
    const event: NoteDraftReadyEvent = await this.gateway.restore(runId);
    this.requireOwnership(ref, event);
    this.host.publishDraft(ref, event);
    return event;
  }

  async cancel(ref: ConversationRunRef, runId: string): Promise<void> {
    const event: NoteDraftReadyEvent = await this.gateway.restore(runId);
    this.requireOwnership(ref, event);
    await this.gateway.cancel(runId);
    await this.addMessage(ref, '已取消笔记草稿，待整理材料仍可使用。', 'completed');
  }

  async retry(ref: ConversationRunRef, runId: string): Promise<NoteDraftReadyEvent> {
    const event: NoteDraftReadyEvent = await this.gateway.retry(runId);
    this.requireOwnership(ref, event);
    this.host.publishDraft(ref, event);
    return event;
  }

  async listRecoverable(): Promise<NoteGenerationRun[]> {
    return await this.gateway.listRecoverable();
  }

  private async addMessage(ref: ConversationRunRef, content: string, outcome: ChatMessageOutcome): Promise<void> {
    if (this.host.acceptsDraftRun(ref)) {
      await this.host.addDraftMessage(ref, content, this.host.draftOrigin(ref), outcome);
    }
  }

  private requireOwnership(ref: ConversationRunRef, event: NoteDraftReadyEvent): void {
    if (event.originSessionId === undefined) {
      throw new Error('DETACHED_DRAFT_REQUIRES_RECOVERY_ENTRY');
    }
    if (event.originSessionId !== ref.sessionId) {
      throw new Error('DRAFT_SESSION_MISMATCH');
    }
  }

  private static errorMessage(error: Object): string {
    if (error instanceof Error) {
      return error.message;
    }
    if (typeof error === 'string' && error.length > 0) {
      return error;
    }
    return 'UNKNOWN_DRAFT_OPERATION_ERROR';
  }
}
