/**
 * AgentChatContracts.ets - Stable UI callbacks consumed by the conversation facade.
 *
 * Path: entry/src/main/ets/services/AgentChatContracts.ets
 * Responsibility: Define session/run-scoped UI, stream, draft, and read seams.
 * Dependencies: conversation contracts; common note-generation contracts.
 *
 * Data flow:
 *   Conversation workflow event -> typed callback contract -> session-owned UI state.
 */
import { common } from '@kit.AbilityKit';
import { NoteDraftReadyEvent } from 'common';
import { ConversationMessageEvent } from '../workflows/conversation/ConversationTypes';
import { ChatMessageOrigin, ChatMessageOutcome } from '../workflows/conversation/ConversationState';
import { ConversationRunRef } from './ConversationIdentity';

export interface AgentChatCallbacks {
  addUserMsg: (ref: ConversationRunRef, content: string, origin: ChatMessageOrigin) => number;
  addAiMsg: (
    ref: ConversationRunRef,
    content: string,
    origin?: ChatMessageOrigin,
    outcome?: ChatMessageOutcome,
  ) => number;
  addAiMsgEmpty: (ref: ConversationRunRef, origin: ChatMessageOrigin) => number;
  updateAiMsg: (ref: ConversationRunRef, id: number, event: ConversationMessageEvent) => void;
  updateRunEvent: (ref: ConversationRunRef, event: ConversationMessageEvent) => void;
  finishAiMsg: (ref: ConversationRunRef, id: number, outcome?: ChatMessageOutcome) => void;
  terminateAiRun: (ref: ConversationRunRef, outcome: ChatMessageOutcome) => void;
  getUserMessageId: (ref: ConversationRunRef) => number;
  commitHistory: (ref: ConversationRunRef) => Promise<boolean>;
  reportDiagnostic: (ref: ConversationRunRef, diagnostic: string) => void;
  cancelDraftsByRun?: (sessionId: string, parentConversationRunId: string) => Promise<void>;
  setBusy: (ref: ConversationRunRef, value: boolean) => void;
  getContext: () => common.UIAbilityContext;
  getConversationText: (ref: ConversationRunRef, excludeLatestUser: boolean) => string;
  onDraftReady: (ref: ConversationRunRef, event: NoteDraftReadyEvent) => void;
  onOcrBlank?: (ref: ConversationRunRef, imageUri: string) => void;
}
