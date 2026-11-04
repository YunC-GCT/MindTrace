/**
 * ConversationRunEvents.ets — 对话运行的 run 事件词汇
 *
 * 路径: agents/src/main/ets/conversation/ConversationRunEvents.ets
 * 职责: 定义对话链路写进 run_store / run_event 的事件 kind 与 payload 口径，
 *       与笔记写入的 dispatch.* 事件共用同一个 sink 契约
 * 依赖: ../core/dispatch/RunEventSink（仅类型）
 *
 * 数据流:
 *   ConversationWorkflow.run / setStep → RunEventSink → entry RunStoreEventSink → run_event
 *
 * 约束: payload 不落正文，只放类型/步骤/终态这类元数据
 */
import type { DispatchRunEvent } from '../core/dispatch/RunEventSink';

export const CONVERSATION_EVENT_START: string = 'conversation.start';
export const CONVERSATION_EVENT_STEP: string = 'conversation.step';
export const CONVERSATION_EVENT_TERMINAL: string = 'conversation.terminal';

export function conversationStartPayload(requestKind: string, origin: string): string {
  return JSON.stringify({
    requestKind: requestKind,
    origin: origin,
  });
}

export function conversationStepPayload(step: string): string {
  return JSON.stringify({ step: step });
}

export function conversationTerminalPayload(outcome: string, reason: string): string {
  return JSON.stringify({
    outcome: outcome,
    reason: reason,
  });
}

export function conversationEvent(kind: string, payloadJson: string): DispatchRunEvent {
  return { kind: kind, payloadJson: payloadJson };
}
