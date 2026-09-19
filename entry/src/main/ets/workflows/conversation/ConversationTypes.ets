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
import { ConversationProgressStep } from './ConversationState';
import { NoteDraftReadyEvent } from 'common';
import type { StreamEvent } from 'common';

export interface ConversationWorkflowCallbacks {
  addAiMsg(content: string): void;
  addAiMsgEmpty(): number;
  appendAiMsg(id: number, event: StreamEvent): void;
  finishAiMsg(id: number): void;
  onStart(): void;
  onProgress(step: ConversationProgressStep): void;
  onFinish(): void;
  getContext(): common.UIAbilityContext;
  getConversationText(excludeLatestUser: boolean): string;
  getSessionId(): string;
  onDraftReady(event: NoteDraftReadyEvent): void;
  onOcrBlank?(imageUri: string): void;
}
