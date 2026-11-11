/**
 * ConversationRunRegistry.ets — 对话运行的进程内状态表
 *
 * 路径: agents/src/main/ets/conversation/ConversationRunRegistry.ets
 * 职责: 按 runId 维护取消令牌、消息来源与「错误只上报一次」标记；
 *       结束/取消时统一清理，避免 run 之间串状态
 * 依赖: common（ConversationRunRef / CancellationToken / ChatMessageOrigin）
 *
 * 数据流:
 *   ConversationWorkflow.run → begin → 节点读取 token/origin → end
 */
import type { CancellationToken, ConversationRunRef } from 'common';
import type { ChatMessageOrigin } from './ConversationState';

export class ConversationRunRegistry {
  private readonly tokens: Map<string, CancellationToken> = new Map<string, CancellationToken>();
  private readonly origins: Map<string, ChatMessageOrigin> = new Map<string, ChatMessageOrigin>();
  private readonly reportedErrors: Set<string> = new Set<string>();

  begin(ref: ConversationRunRef, origin: ChatMessageOrigin, token: CancellationToken): void {
    this.tokens.set(ref.runId, token);
    this.origins.set(ref.runId, origin);
    this.reportedErrors.delete(ref.runId);
  }

  end(ref: ConversationRunRef): void {
    this.tokens.delete(ref.runId);
    this.origins.delete(ref.runId);
    this.reportedErrors.delete(ref.runId);
  }

  /** 取消钩子触发时只丢令牌与来源，错误标记留给 end 清理。 */
  dropCancellation(ref: ConversationRunRef): void {
    this.tokens.delete(ref.runId);
    this.origins.delete(ref.runId);
  }

  token(ref: ConversationRunRef): CancellationToken | undefined {
    return this.tokens.get(ref.runId);
  }

  origin(ref: ConversationRunRef): ChatMessageOrigin {
    return this.origins.get(ref.runId) ?? 'chat';
  }

  /** 第一次调用返回 true；同一 run 重复上报返回 false。 */
  markErrorReported(ref: ConversationRunRef): boolean {
    if (this.reportedErrors.has(ref.runId)) {
      return false;
    }
    this.reportedErrors.add(ref.runId);
    return true;
  }
}
