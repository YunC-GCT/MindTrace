/**
 * ConversationMemoryProjection.ets - conversation persistence and memory projection.
 *
 * Path: entry/src/main/ets/workflows/conversation/ConversationMemoryProjection.ets
 * Responsibility: project accepted run messages/OCR and load derived memory contexts.
 * Dependencies: AgentMemoryService; conversation run identity; common contracts.
 *
 * Data flow:
 *   Current run message/OCR -> context eligibility guard -> RDB memory projection.
 */
import { common } from '@kit.AbilityKit';
import { CancellationToken, ClassificationResult, SourceFragment } from 'common';
import { AgentMemoryService } from '../../services/AgentMemoryService';
import { AgentMemoryRecord } from '../../models/AgentMemoryModels';
import { ChatMessageOrigin } from './ConversationState';
import { ConversationRunRef } from '../../services/ConversationIdentity';

export interface IConversationMemoryProjectionHost {
  memoryContext(): common.UIAbilityContext;
  acceptsMemoryRun(ref: ConversationRunRef): boolean;
  memoryOrigin(ref: ConversationRunRef): ChatMessageOrigin;
  commitMemoryHistory(ref: ConversationRunRef): Promise<boolean>;
  userMessageId(ref: ConversationRunRef): number;
  reportMemoryDiagnostic(ref: ConversationRunRef, diagnostic: string): void;
  memoryCancellationToken(ref: ConversationRunRef): CancellationToken | undefined;
}

export class ConversationMemoryProjection {
  private readonly host: IConversationMemoryProjectionHost;
  private memory: AgentMemoryService | null = null;

  private constructor(host: IConversationMemoryProjectionHost) {
    this.host = host;
  }

  static create(host: IConversationMemoryProjectionHost): ConversationMemoryProjection {
    return new ConversationMemoryProjection(host);
  }

  async saveUser(ref: ConversationRunRef, content: string): Promise<void> {
    if (!this.host.acceptsMemoryRun(ref)) { return; }
    try {
      if (!(await this.host.commitMemoryHistory(ref))) { throw new Error('CHAT_HISTORY_COMMIT_REQUIRED'); }
      const messageId: number = this.host.userMessageId(ref);
      if (messageId <= 0) { throw new Error('USER_MESSAGE_KEY_UNAVAILABLE'); }
      await this.service().saveMessage({
        sessionId: ref.sessionId,
        role: 'user',
        content: content,
        messageKey: ref.runId + ':user',
        sequence: messageId,
        runId: ref.runId,
        origin: this.host.memoryOrigin(ref),
      });
    } catch (error) {
      this.host.reportMemoryDiagnostic(ref, 'stage=context-projection;code=USER_MESSAGE_PROJECTION_PENDING');
      console.warn('[ConversationMemoryProjection] save user memory failed: '
        + ConversationMemoryProjection.errorMessage(error));
    }
  }

  async saveAssistant(ref: ConversationRunRef, content: string, messageId: number): Promise<void> {
    if (!this.host.acceptsMemoryRun(ref)) { return; }
    try {
      if (!(await this.host.commitMemoryHistory(ref))) { throw new Error('CHAT_HISTORY_COMMIT_REQUIRED'); }
      await this.service().saveMessage({
        sessionId: ref.sessionId,
        role: 'assistant',
        content: content,
        messageKey: ref.runId + ':assistant:' + messageId.toString(),
        sequence: messageId,
        runId: ref.runId,
        origin: this.host.memoryOrigin(ref),
      });
    } catch (error) {
      this.host.reportMemoryDiagnostic(ref, 'stage=context-projection;code=ASSISTANT_MESSAGE_PROJECTION_PENDING');
      console.warn('[ConversationMemoryProjection] save assistant memory failed: '
        + ConversationMemoryProjection.errorMessage(error));
    }
  }

  async saveOcr(
    ref: ConversationRunRef,
    imageUri: string,
    userText: string,
    result: ClassificationResult,
  ): Promise<string | null> {
    if (!this.host.acceptsMemoryRun(ref)) { return null; }
    try {
      return await this.service().saveOcrResult(ref.sessionId, imageUri, userText, result);
    } catch (error) {
      console.warn('[ConversationMemoryProjection] save OCR memory failed: '
        + ConversationMemoryProjection.errorMessage(error));
      return null;
    }
  }

  async contextForReply(ref: ConversationRunRef): Promise<string> {
    return await this.loadContext(ref, 'reply');
  }

  async contextForNote(ref: ConversationRunRef): Promise<string> {
    return await this.loadContext(ref, 'note');
  }

  async learnerProfile(ref: ConversationRunRef): Promise<string> {
    return await this.loadContext(ref, 'profile');
  }

  async updateLearnerProfile(ref: ConversationRunRef): Promise<void> {
    if (!this.host.acceptsMemoryRun(ref)) { return; }
    try {
      await this.service().updateLearnerProfileIfNeeded(
        ref.sessionId,
        this.host.memoryCancellationToken(ref),
      );
    } catch (error) {
      console.warn('[ConversationMemoryProjection] update learner profile failed: '
        + ConversationMemoryProjection.errorMessage(error));
    }
  }

  async summarize(ref: ConversationRunRef): Promise<void> {
    if (!this.host.acceptsMemoryRun(ref)) { return; }
    try {
      await this.service().summarizeSessionIfNeeded(ref.sessionId, this.host.memoryCancellationToken(ref));
    } catch (error) {
      console.warn('[ConversationMemoryProjection] summarize memory failed: '
        + ConversationMemoryProjection.errorMessage(error));
    }
  }

  async pendingSources(ref: ConversationRunRef): Promise<SourceFragment[]> {
    if (!this.host.acceptsMemoryRun(ref)) { return []; }
    try {
      const records: AgentMemoryRecord[] = await this.service().getPendingNoteMaterials(ref.sessionId);
      const sources: SourceFragment[] = [];
      let sequence: number = 1;
      for (const record of records) {
        sources.push({
          id: record.id,
          kind: 'ocr',
          originId: record.source,
          sequence: sequence,
          fingerprint: record.id,
          text: record.content,
        });
        sequence += 1;
      }
      return sources;
    } catch (error) {
      console.warn('[ConversationMemoryProjection] load pending sources failed: '
        + ConversationMemoryProjection.errorMessage(error));
      return [];
    }
  }

  private async loadContext(ref: ConversationRunRef, kind: 'reply' | 'note' | 'profile'): Promise<string> {
    if (!this.host.acceptsMemoryRun(ref)) { return ''; }
    try {
      if (kind === 'reply') { return await this.service().getContextForReply(ref.sessionId); }
      if (kind === 'note') { return await this.service().getContextForNoteGeneration(ref.sessionId); }
      return await this.service().getLearnerProfileContext(ref.sessionId);
    } catch (error) {
      console.warn('[ConversationMemoryProjection] load ' + kind + ' context failed: '
        + ConversationMemoryProjection.errorMessage(error));
      return '';
    }
  }

  private service(): AgentMemoryService {
    if (this.memory === null) {
      this.memory = new AgentMemoryService(this.host.memoryContext());
    }
    return this.memory;
  }

  private static errorMessage(error: Object): string {
    if (error instanceof Error) { return error.message; }
    if (typeof error === 'string' && error.length > 0) { return error; }
    return 'UNKNOWN_MEMORY_PROJECTION_ERROR';
  }
}
