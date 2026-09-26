/**
 * ConversationSnapshotMapper.ets - Translate UI sessions to persistence DTOs.
 *
 * Path: entry/src/main/ets/services/ConversationSnapshotMapper.ets
 * Responsibility: Keep ChatSession presentation details out of persistence services.
 * Dependencies: ChatModels, ConversationSnapshotModels.
 *
 * Data flow:
 *   UI ChatSession[] -> validated snapshot DTOs -> file/RDB persistence coordinators.
 */
import { ChatMsg, ChatSession, usableAsContext } from '../overlays/AgentFloatWindow/chat/ChatModels';
import {
  ConversationMessageSnapshot,
  ConversationSessionSnapshot,
} from '../models/ConversationSnapshotModels';

export class ConversationSnapshotMapper {
  static fromSessions(sessions: ChatSession[]): ConversationSessionSnapshot[] {
    const snapshots: ConversationSessionSnapshot[] = [];
    for (const session of sessions) {
      const messages: ConversationMessageSnapshot[] = [];
      for (const message of session.messages) {
        messages.push(ConversationSnapshotMapper.fromMessage(session.id, message));
      }
      snapshots.push({ id: session.id, name: session.name, messages: messages });
    }
    return snapshots;
  }

  static retainExistingSessions(
    snapshots: ConversationSessionSnapshot[],
    sessions: ChatSession[],
  ): ChatSession[] {
    const retained: ChatSession[] = [];
    for (const snapshot of snapshots) {
      const session: ChatSession | undefined = sessions.find(
        (candidate: ChatSession): boolean => candidate.id === snapshot.id,
      );
      if (session !== undefined) { retained.push(session); }
    }
    return retained;
  }

  private static fromMessage(sessionId: string, message: ChatMsg): ConversationMessageSnapshot {
    return {
      sessionId: sessionId,
      role: message.role === 'ai' ? 'assistant' : message.role,
      content: message.content,
      messageKey: message.messageKey ?? 'legacy:' + sessionId + ':' + message.id.toString(),
      sequence: message.sequence ?? message.id,
      runId: message.runId,
      origin: message.origin ?? 'legacy',
      contextEligible: usableAsContext(message),
    };
  }
}
