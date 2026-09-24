/**
 * ConversationSessionReducer.ets - Pure session-targeted conversation updates.
 *
 * Path: entry/src/main/ets/services/ConversationSessionReducer.ets
 * Responsibility: Apply a current run event to exactly one existing session.
 * Dependencies: ConversationIdentity; ChatModels.
 *
 * Data flow:
 *   Run-scoped event -> identity/current checks -> immutable session array update.
 *
 * ArkTS 1.1 strict adaptation:
 *   - Reducer inputs and results use named interfaces and explicit collection types.
 */

import { ChatMessageIdPolicy, ConversationRunRef, requireConversationRunRef } from './ConversationIdentity';
import { ChatMsg, ChatSession } from '../overlays/AgentFloatWindow/chat/ChatModels';

export type ConversationSessionEvent =
  | 'add-user-message'
  | 'add-ai-message'
  | 'add-ai-placeholder'
  | 'append-ai-message'
  | 'finish-ai-message';

export interface ConversationSessionReduceResult {
  accepted: boolean;
  sessions: ChatSession[];
  diagnostic: string;
}

export class ConversationSessionReducer {
  static updateMessages(
    sessions: ChatSession[],
    ref: ConversationRunRef,
    current: boolean,
    event: ConversationSessionEvent,
    update: (messages: ChatMsg[]) => ChatMsg[],
  ): ConversationSessionReduceResult {
    try {
      requireConversationRunRef(ref);
    } catch (error) {
      return ConversationSessionReducer.rejected(sessions, ref, event, 'INVALID_RUN_REF');
    }
    if (!current) {
      return ConversationSessionReducer.rejected(sessions, ref, event, 'STALE_RUN_EVENT');
    }
    const targetIndex: number = sessions.findIndex((session: ChatSession): boolean => session.id === ref.sessionId);
    if (targetIndex < 0) {
      return ConversationSessionReducer.rejected(sessions, ref, event, 'SESSION_NOT_FOUND');
    }
    const nextMessages: ChatMsg[] = update(sessions[targetIndex].messages);
    if (!ConversationSessionReducer.hasUniqueMessageIds(nextMessages)) {
      return ConversationSessionReducer.rejected(sessions, ref, event, 'DUPLICATE_CHAT_MESSAGE_ID');
    }
    const nextSessions: ChatSession[] = [];
    for (let index: number = 0; index < sessions.length; index += 1) {
      const session: ChatSession = sessions[index];
      if (index === targetIndex) {
        nextSessions.push({ id: session.id, name: session.name, messages: nextMessages });
      } else {
        nextSessions.push(session);
      }
    }
    return { accepted: true, sessions: nextSessions, diagnostic: 'code=ACCEPTED' };
  }

  private static hasUniqueMessageIds(messages: ChatMsg[]): boolean {
    const ids: Set<number> = new Set<number>();
    for (const message of messages) {
      if (!ChatMessageIdPolicy.isValid(message.id) || ids.has(message.id)) {
        return false;
      }
      ids.add(message.id);
    }
    return true;
  }

  private static rejected(
    sessions: ChatSession[],
    ref: ConversationRunRef,
    event: ConversationSessionEvent,
    code: string,
  ): ConversationSessionReduceResult {
    return {
      accepted: false,
      sessions: sessions,
      diagnostic: 'code=' + code + '; event=' + event
        + '; sessionId=' + ref.sessionId + '; runId=' + ref.runId,
    };
  }
}
