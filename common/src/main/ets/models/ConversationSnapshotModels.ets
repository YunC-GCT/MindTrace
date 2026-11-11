/**
 * ConversationSnapshotModels.ets — 与 UI 无关的会话快照契约
 *
 * 路径: common/src/main/ets/models/ConversationSnapshotModels.ets
 * 职责: 定义业务服务消费的稳定会话快照形状与投影写入端口
 * 依赖: ./AgentMemoryModels
 *
 * 数据流:
 *   聊天 UI 适配器 → 会话快照 DTO → 投影 / 删除服务
 *
 * ArkTS 1.1 strict 适配:
 *   - DTO 只含持久化数据，不 import 任何 UI 模型或组件
 */

import { ChatMessageWriteRequest } from './AgentMemoryModels';

export type ConversationSnapshotRole = 'user' | 'assistant' | 'system';

export interface ConversationMessageSnapshot {
  sessionId: string;
  role: ConversationSnapshotRole;
  content: string;
  messageKey: string;
  sequence: number;
  runId?: string;
  origin: string;
  contextEligible: boolean;
}

export interface ConversationSessionSnapshot {
  id: string;
  name: string;
  messages: ConversationMessageSnapshot[];
}

export interface ChatProjectionWriter {
  saveMessage(request: ChatMessageWriteRequest): Promise<void>;
}
