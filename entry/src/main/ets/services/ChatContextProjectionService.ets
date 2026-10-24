/**
 * ChatContextProjectionService.ets - Idempotent file-history to RDB context projection.
 *
 * Path: entry/src/main/ets/services/ChatContextProjectionService.ets
 * Responsibility: Replay context-eligible snapshot messages with stable message keys and order.
 * Dependencies: AgentMemoryService, ConversationSnapshotModels.
 *
 * Data flow:
 *   trusted conversation snapshots -> context eligibility -> ChatMessageDao.upsert.
 *
 * ArkTS 1.1 strict adaptation:
 *   - Explicit loops and message types keep the projection deterministic and testable.
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ChatProjectionWriter,
  ConversationMessageSnapshot,
  ConversationSessionSnapshot,
} from '../models/ConversationSnapshotModels';
import type { ChatHistoryClearControl } from './ChatHistoryClearControl';
import { getChatHistoryClearControl } from './ChatHistoryClearControl';
import { AgentMemoryService } from './AgentMemoryService';

export interface ChatProjectionResult {
  projected: number;
  failures: number;
  diagnostic: string;
}

export class ChatContextProjectionService {
  private readonly memory: ChatProjectionWriter;

  constructor(context: common.UIAbilityContext | null, writer?: ChatProjectionWriter) {
    if (writer !== undefined) {
      this.memory = writer;
    } else if (context !== null) {
      this.memory = new AgentMemoryService(context);
    } else {
      throw new Error('CHAT_PROJECTION_WRITER_REQUIRED');
    }
  }

  async reconcile(sessions: ConversationSessionSnapshot[]): Promise<ChatProjectionResult> {
    const clearControl: ChatHistoryClearControl | undefined = getChatHistoryClearControl();
    if (clearControl !== undefined && clearControl.getState().clearState === 'pending') {
      hilog.debug(0xA2A0, 'ChatHistoryClear', 'code=CHAT_HISTORY_PROJECTION_SKIPPED reason=clear-in-progress');
      return {
        projected: 0,
        failures: 0,
        diagnostic: 'code=CHAT_HISTORY_PROJECTION_SKIPPED; reason=clear-in-progress',
      };
    }
    let projected: number = 0;
    let failures: number = 0;
    for (const session of sessions) {
      for (const message of session.messages) {
        if (!message.contextEligible || message.content.trim().length === 0) { continue; }
        try {
          await this.project(session.id, message);
          projected += 1;
        } catch (error) {
          failures += 1;
        }
      }
    }
    return {
      projected: projected,
      failures: failures,
      diagnostic: failures === 0 ? 'code=CHAT_PROJECTION_RECONCILED' : 'code=CHAT_PROJECTION_RETRY_PENDING',
    };
  }

  private async project(sessionId: string, message: ConversationMessageSnapshot): Promise<void> {
    await this.memory.saveMessage({
      sessionId: sessionId,
      role: message.role,
      content: message.content,
      messageKey: message.messageKey,
      sequence: message.sequence,
      runId: message.runId,
      origin: message.origin,
    });
  }
}
