/**
 * ConversationTypes.ets — Conversation workflow 回调契约类型
 *
 * 路径: entry/src/main/ets/workflows/conversation/ConversationTypes.ets
 * 职责: 定义 ConversationWorkflowCallbacks 单一接缝 (UI ↔ workflow 全部交互)
 * 依赖: @kit.AbilityKit (common.UIAbilityContext); ./ConversationState (ConversationProgressStep); common (NoteDraftReadyEvent, StreamEvent)
 *
 * 数据流:
 *   AgentFloatWindow ↔ ConversationWorkflow (callbacks) ↔ ConversationWorkflow.run (StateGraph)
 *
 * 设计要点:
 *   - P0: appendAiMsg 接 StreamEvent (structured, 4-value union; tool_* 保留位); addAiMsgEmpty + finishAiMsg 形成"创建空消息 → 累积流 → 完成"三阶段
 *   - onDraftReady 把草稿事件抛回 UI,UI 端走 NoteDraftPanel;draft 状态字段回写到 ConversationState 在 State.ets 定义
 *
 * ArkTS 1.1 strict 适配:
 *   - 全部 callback 用具名函数类型,无 call signature 对象 (避免 arkts-no-call-signatures)
 *   - StreamEvent 以 type import 引入,避免循环依赖
 */

import { common } from '@kit.AbilityKit';
import { ChatMessageOrigin, ChatMessageOutcome, ConversationProgressStep } from './ConversationState';
import { NoteDraftReadyEvent } from 'common';
import type { StreamEvent } from 'common';
import { ConversationRunRef } from '../../services/ConversationIdentity';
import { CancellationToken } from 'common';

export interface ConversationWorkflowCallbacks {
  addAiMsg(ref: ConversationRunRef, content: string, origin?: ChatMessageOrigin, outcome?: ChatMessageOutcome): number;
  addAiMsgEmpty(ref: ConversationRunRef, origin: ChatMessageOrigin): number;
  appendAiMsg(ref: ConversationRunRef, id: number, event: StreamEvent): void;
  replaceAiMsg(ref: ConversationRunRef, id: number, content: string): void;
  finishAiMsg(ref: ConversationRunRef, id: number, outcome?: ChatMessageOutcome): void;
  getUserMessageId(ref: ConversationRunRef): number;
  commitHistory(ref: ConversationRunRef): Promise<boolean>;
  reportDiagnostic(ref: ConversationRunRef, diagnostic: string): void;
  onStart(ref: ConversationRunRef): void;
  onProgress(ref: ConversationRunRef, step: ConversationProgressStep): void;
  onFinish(ref: ConversationRunRef): void;
  isCurrentRun(ref: ConversationRunRef): boolean;
  getCancellationToken(ref: ConversationRunRef): CancellationToken | undefined;
  registerCancellationHook(ref: ConversationRunRef, hook: () => void): () => void;
  getContext(): common.UIAbilityContext;
  getConversationText(ref: ConversationRunRef, excludeLatestUser: boolean): string;
  onDraftReady(ref: ConversationRunRef, event: NoteDraftReadyEvent): void;
  onOcrBlank?(ref: ConversationRunRef, imageUri: string): void;
}
