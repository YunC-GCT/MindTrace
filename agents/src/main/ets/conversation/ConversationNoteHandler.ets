/**
 * ConversationNoteHandler.ets — 对话内笔记生成节点
 *
 * 路径: agents/src/main/ets/conversation/ConversationNoteHandler.ets
 * 职责: 从会话材料生成笔记草稿：显式重生成 → 增量拒绝 → 结构化上下文 →
 *       主题澄清 / 走 capture 端口生成 bundle 草稿
 * 依赖: common、../chat/*、./ConversationNodeHost
 *
 * 数据流:
 *   ConversationWorkflow.note_reply → 本处理器 → capturePort / memoryProjection → onDraftReady
 */
import type {
  CancellationToken,
  ConversationRunRef,
  NoteContextClarification,
  NoteDraftReadyEvent,
  NoteGenerationContextResult,
  NoteGenerationProgressEvent,
  NoteGenerationProgressSink,
  NoteGenerationRoute,
} from 'common';
import { LlmErrorBodyFormatter } from 'common';
import type { NoteSuggestion } from 'common';
import type { IConversationNodeHost } from './ConversationNodeHost';

interface RegenerationInstruction {
  noteId: string;
  instruction: string;
}

export class ConversationNoteHandler {
  private readonly host: IConversationNodeHost;

  constructor(host: IConversationNodeHost) {
    this.host = host;
  }

  async handle(
    ref: ConversationRunRef,
    userInstruction: string,
    route?: NoteGenerationRoute,
  ): Promise<NoteDraftReadyEvent | undefined> {
    const explicitRegeneration: RegenerationInstruction | undefined = ConversationNoteHandler.parseRegenerationRequest(userInstruction);
    if (explicitRegeneration !== undefined) {
      await this.host.safeSaveUserMessage(ref, userInstruction);
      try {
        const event: NoteDraftReadyEvent = await this.host.capturePort().regenerateNoteDraft(
          'regenerate-' + Date.now().toString(),
          explicitRegeneration.noteId,
          explicitRegeneration.instruction,
          explicitRegeneration.instruction,
          this.host.cancellationToken(ref),
          ref.sessionId,
          ref.runId,
          this.progressSink(ref),
        );
        this.host.nodeCallbacks().onDraftReady(ref, event);
        this.host.nodeCallbacks().completeProgress(ref);
        return event;
      } catch (e) {
        const errorMessage: string = this.host.errorMessage(e);
        this.host.finishRunFailure(ref, e);
        throw new Error(errorMessage);
      }
    }
    if (ConversationNoteHandler.isIncrementalInstruction(userInstruction)) {
      await this.host.addAiMessage(ref, '请先选择要修改的明确笔记，再提出增量修改要求。', this.host.originFor(ref), 'failed');
      return undefined;
    }
    await this.host.safeSaveUserMessage(ref, userInstruction);
    try {
      const configured: boolean = await this.host.replyPort().isConfigured();
      if (!configured) {
        throw new Error('NO_API_KEY');
      }

      const inlineMaterial: string = this.host.intentPort().inlineNoteMaterial(userInstruction).trim();
      const fallbackConversation: string = this.host.nodeCallbacks().getConversationText(ref, true).trim();
      const noteContext: NoteGenerationContextResult | undefined = await this.host.safeGetStructuredContextForNoteGeneration(
        ref,
        userInstruction,
        inlineMaterial,
        fallbackConversation,
      );
      if (noteContext === undefined || noteContext.bundle.fragments.length === 0) {
        await this.host.addAiMessage(ref, '当前会话还没有可整理的内容', this.host.originFor(ref), 'failed');
        return undefined;
      }

      const noteGenerationRunId: string = 'conversation-' + Date.now().toString();
      if (!this.host.nodeCallbacks().isCurrentRun(ref)) { return undefined; }
      if (noteContext.requiresClarification) {
        const clarification: NoteContextClarification = await this.host.capturePort().saveNoteContextClarification(
          noteGenerationRunId,
          userInstruction,
          noteContext.bundle,
          noteContext.topics,
          noteContext.pendingSourceIds,
          noteContext.contextBudgetTokens,
          ref.sessionId,
          ref.runId,
          route,
        );
        const clarificationMessage: string = this.host.replyPort().normalize(
          ConversationNoteHandler.topicClarificationMessage(noteContext),
        );
        const messageId: number = this.host.nodeCallbacks().addAiMsg(ref, clarificationMessage, this.host.originFor(ref), 'completed');
        if (messageId > 0) {
          const onClarificationReady = this.host.nodeCallbacks().onNoteContextClarificationReady;
          if (onClarificationReady !== undefined) {
            onClarificationReady(ref, messageId, clarification);
          }
          await this.host.safeSaveAssistantMessage(ref, clarificationMessage, messageId);
        }
        return undefined;
      }
      const event: NoteDraftReadyEvent = await this.generateDraftFromContext(
        ref,
        noteGenerationRunId,
        userInstruction,
        noteContext,
        this.host.cancellationToken(ref),
        route,
      );
      this.host.nodeCallbacks().onDraftReady(ref, event);
      // 建议请求：草稿生成完成时告诉上层「这里可以新建一条原子笔记」，
      // 本轮只记录不渲染；用户确认后才走既有的 draft 确认链路。
      const suggestion: NoteSuggestion = {
        action: 'create',
        noteKind: 'atomic',
        count: 1,
        reason: 'draft-ready',
      };
      const callbacks = this.host.nodeCallbacks();
      if (callbacks.onNoteSuggestion !== undefined) {
        callbacks.onNoteSuggestion(ref, suggestion);
      }
      this.host.nodeCallbacks().completeProgress(ref);
      return event;
    } catch (e) {
      const errMsg: string = LlmErrorBodyFormatter.redactSensitiveText(this.host.errorMessage(e));
      this.host.finishRunFailure(ref, e);
      throw new Error(errMsg);
    }
  }

  private async generateDraftFromContext(
    ref: ConversationRunRef,
    runId: string,
    instruction: string,
    context: NoteGenerationContextResult,
    cancellationToken?: CancellationToken,
    route?: NoteGenerationRoute,
  ): Promise<NoteDraftReadyEvent> {
    return await this.host.capturePort().generateNoteDraftWithBundle(
      runId,
      instruction,
      context.bundle,
      context.pendingSourceIds,
      context.contextBudgetTokens,
      cancellationToken,
      ref.sessionId,
      ref.runId,
      route,
      this.progressSink(ref),
    );
  }

  private progressSink(ref: ConversationRunRef): NoteGenerationProgressSink {
    return (event: NoteGenerationProgressEvent): void => {
      this.host.nodeCallbacks().onNoteGenerationProgress(ref, event);
    };
  }

  private static topicClarificationMessage(context: NoteGenerationContextResult): string {
    const lines: string[] = [];
    if (context.topics.length === 0) {
      return '我还无法可靠判断这些材料的唯一数学主题。请输入一个具体主题后再生成笔记。';
    }
    lines.push('我发现材料里有多个数学主题。请先回复你要整理哪一个主题，我再生成单主题笔记：');
    for (let index: number = 0; index < context.topics.length; index += 1) {
      const topic = context.topics[index];
      lines.push((index + 1).toString() + '. ' + topic.displayName);
    }
    return lines.join('\n');
  }

  private static parseRegenerationRequest(userInstruction: string): RegenerationInstruction | undefined {
    const markers: string[] = ['noteId=', 'noteId:', '笔记ID=', '笔记ID：'];
    for (const marker of markers) {
      const markerIndex: number = userInstruction.indexOf(marker);
      if (markerIndex < 0) {
        continue;
      }
      const valueStart: number = markerIndex + marker.length;
      const separatorIndex: number = userInstruction.indexOf(' ', valueStart);
      const noteId: string = (separatorIndex < 0
        ? userInstruction.substring(valueStart)
        : userInstruction.substring(valueStart, separatorIndex)).trim();
      if (noteId.length > 0) {
        const instruction: string = userInstruction.substring(valueStart + noteId.length).trim();
        return {
          noteId: noteId,
          instruction: instruction.length > 0 ? instruction : '请按新要求增量更新笔记',
        };
      }
    }
    return undefined;
  }

  private static isIncrementalInstruction(userInstruction: string): boolean {
    const markers: string[] = ['增加例子', '补充例子', '展开推导', '只修改', '增量', '重生成章节'];
    for (const marker of markers) {
      if (userInstruction.includes(marker)) {
        return true;
      }
    }
    return false;
  }
}
