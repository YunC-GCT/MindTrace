/**
 * ConversationSnapshotModels.ets - UI-independent conversation persistence contracts.
 *
 * Path: entry/src/main/ets/models/ConversationSnapshotModels.ets
 * Responsibility: Define the stable snapshot shape consumed by business services.
 * Dependencies: none.
 *
 * Data flow:
 *   Chat UI adapter -> conversation snapshot DTO -> projection/deletion services.
 *
 * ArkTS 1.1 strict adaptation:
 *   - DTOs contain only persistence data; no UI model or component imports.
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
