/**
 * ConversationReviewHandler.ets — 复习回答节点（complete / stream）
 *
 * 路径: agents/src/main/ets/conversation/ConversationReviewHandler.ets
 * 职责: 把复习计划的终答 / 模型回答落成一条消息：终态计划直接回、模型计划走
 *       回复端口并做引文过滤，最后统一 finish + 记忆投影
 * 依赖: common、../chat/*、./ConversationNodeHost
 *
 * 数据流:
 *   ConversationWorkflow 节点 → 本处理器 → replyPort / reviewPort → updateAiMsg → finishAiMsg
 */
import type {
  ConversationRunRef,
  NoteEvidenceStreamFilterPort,
  NoteReviewAnswer,
  NoteReviewFinalization,
  NoteReviewPlan,
  StreamEvent,
} from 'common';
import type { StreamReplyResult } from '../chat/ReplyService';
import type { ReplyContext } from '../chat/IntentClassifier';
import type { IConversationNodeHost } from './ConversationNodeHost';
import type { ConversationMessageEvent } from './ConversationTypes';

export class ConversationReviewHandler {
  private readonly host: IConversationNodeHost;

  constructor(host: IConversationNodeHost) {
    this.host = host;
  }

  async handleComplete(
    ref: ConversationRunRef,
    memoryContext: string,
    learnerProfileContext: string,
    plan: NoteReviewPlan,
  ): Promise<void> {
    const msgId: number = this.host.nodeCallbacks().addAiMsgEmpty(ref, this.host.originFor(ref));
    if (msgId <= 0) { return; }
    if (plan.kind === 'terminal') {
      await this.finish(ref, msgId, plan.displayText, plan.answer);
      this.host.setStep(ref, 'completed');
      return;
    }
    try {
      const configured: boolean = await this.host.replyPort().isConfigured();
      if (!configured) {
        const noKey: NoteReviewFinalization = this.host.reviewPort().fallbackFailure(plan, 'llm-not-configured');
        await this.finish(ref, msgId, noKey.displayText, noKey.answer);
        this.host.setStep(ref, 'completed');
        return;
      }
      this.host.setStep(ref, 'reply_model_call');
      const replyContext: ReplyContext = this.host.createReplyContext(
        memoryContext,
        learnerProfileContext,
        plan.modelUserContent,
        plan.evidence,
      );
      const reply: string = await this.host.replyPort().complete(replyContext, this.host.cancellationToken(ref));
      const finalization: NoteReviewFinalization = this.host.reviewPort().finalizeModelAnswer(plan, reply);
      await this.finish(ref, msgId, finalization.displayText, finalization.answer);
      this.host.setStep(ref, 'completed');
      if (finalization.answer.status === 'grounded') {
        await this.host.safeUpdateLearnerProfileIfNeeded(ref);
        await this.host.safeSummarizeIfNeeded(ref);
      }
    } catch (e) {
      const failed: NoteReviewFinalization = this.host.reviewPort().fallbackFailure(plan, 'model-failed');
      await this.finish(ref, msgId, failed.displayText, failed.answer);
      this.host.setStep(ref, 'completed');
    }
  }

  async handleStream(
    ref: ConversationRunRef,
    memoryContext: string,
    learnerProfileContext: string,
    plan: NoteReviewPlan,
  ): Promise<void> {
    const msgId: number = this.host.nodeCallbacks().addAiMsgEmpty(ref, this.host.originFor(ref));
    if (msgId <= 0) { return; }
    if (plan.kind === 'terminal') {
      await this.finish(ref, msgId, plan.displayText, plan.answer);
      this.host.setStep(ref, 'completed');
      return;
    }
    try {
      const configured: boolean = await this.host.replyPort().isConfigured();
      if (!configured) {
        const noKey: NoteReviewFinalization = this.host.reviewPort().fallbackFailure(plan, 'llm-not-configured');
        await this.finish(ref, msgId, noKey.displayText, noKey.answer);
        this.host.setStep(ref, 'completed');
        return;
      }
      this.host.setStep(ref, 'reply_model_call');
      const replyContext: ReplyContext = this.host.createReplyContext(
        memoryContext,
        learnerProfileContext,
        plan.modelUserContent,
        plan.evidence,
      );
      const citationFilter: NoteEvidenceStreamFilterPort = this.host.reviewPort().createStreamFilter(plan);
      const streamResult: StreamReplyResult = await this.host.replyPort().stream(
        replyContext,
        (event: StreamEvent): void => {
          if (event.type !== 'text') {
            const messageEvent: ConversationMessageEvent = { kind: 'stream', event: event };
            this.host.nodeCallbacks().updateAiMsg(ref, msgId, messageEvent);
            return;
          }
          const safeText: string = citationFilter.push(event.delta);
          if (safeText.length > 0) {
            const safeEvent: StreamEvent = { type: 'text', delta: safeText };
            const messageEvent: ConversationMessageEvent = { kind: 'stream', event: safeEvent };
            this.host.nodeCallbacks().updateAiMsg(ref, msgId, messageEvent);
          }
        },
        this.host.cancellationToken(ref),
      );
      const citationTail: string = citationFilter.flush();
      if (citationTail.length > 0) {
        const tailEvent: StreamEvent = { type: 'text', delta: citationTail };
        const messageEvent: ConversationMessageEvent = { kind: 'stream', event: tailEvent };
        this.host.nodeCallbacks().updateAiMsg(ref, msgId, messageEvent);
      }
      if (streamResult.usedFallback) {
        const fallback: NoteReviewFinalization = this.host.reviewPort().fallbackFailure(plan, 'stream-fallback');
        await this.finish(ref, msgId, fallback.displayText, fallback.answer);
        this.host.setStep(ref, 'completed');
        return;
      }
      if (streamResult.interrupted) {
        const interrupted: NoteReviewFinalization = this.host.reviewPort().fallbackFailure(plan, 'stream-interrupted');
        await this.finish(ref, msgId, interrupted.displayText, interrupted.answer);
        this.host.setStep(ref, 'completed');
        return;
      }
      const finalization: NoteReviewFinalization = this.host.reviewPort().finalizeModelAnswer(plan, streamResult.content);
      await this.finish(ref, msgId, finalization.displayText, finalization.answer);
      this.host.setStep(ref, 'completed');
      if (finalization.answer.status === 'grounded') {
        await this.host.safeUpdateLearnerProfileIfNeeded(ref);
        await this.host.safeSummarizeIfNeeded(ref);
      }
    } catch (e) {
      const failed: NoteReviewFinalization = this.host.reviewPort().fallbackFailure(plan, 'model-failed');
      await this.finish(ref, msgId, failed.displayText, failed.answer);
      this.host.setStep(ref, 'completed');
    }
  }

  private async finish(
    ref: ConversationRunRef,
    messageId: number,
    content: string,
    review: NoteReviewAnswer,
  ): Promise<void> {
    const displayContent: string = this.host.replyPort().normalize(content);
    const replaceEvent: ConversationMessageEvent = { kind: 'replace-content', content: displayContent };
    this.host.nodeCallbacks().updateAiMsg(ref, messageId, replaceEvent);
    const onReviewReady = this.host.nodeCallbacks().onNoteReviewReady;
    if (onReviewReady !== undefined) {
      onReviewReady(ref, messageId, review);
    }
    this.host.nodeCallbacks().finishAiMsg(ref, messageId, 'completed');
    await this.host.safeSaveAssistantMessage(ref, displayContent, messageId);
  }
}
