/**
 * ChatSession.ets — 智能体浮窗会话持久化管理(spec 021 ticket-5, #141)
 *
 * 路径: entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatSession.ets
 * 职责: 为 AgentFloatWindow 封装会话 ID、文件快照初始化、保存、强制 flush 与后台 flush seam。
 * 依赖: @kit.ArkData(preferences); services/ChatFilesDirSeam; services/ChatHistoryPersistence。
 *
 * 数据流:
 *   AgentFloatWindow → ChatSessionManager → ChatHistoryPersistence
 *   EntryAbility.onBackground → ChatSessionManager.flushActive
 *
 * 边界:
 * - Preferences 仅作为旧历史迁移读取源,生产保存走应用私有文件快照。
 * - ChatSessionManager 不持 UI 引用;只接收调用方传入的纯 ChatSession[] 快照。
 * - Active-session handoff uses the full in-memory copy; persistence removes
 *   UI-only reasoningExpanded through ChatHistoryPersistence.
 * - filesDir 由 ChatFilesDirSeam 注入;缺失时由持久化服务阻塞而不回退 Preferences 写入。
 *
 * ArkTS 1.1 strict 适配: 显式返回类型;无 any/unknown;无构造器参数属性。
 */

import { preferences } from '@kit.ArkData';
import { ChatSession, copyChatSessionsForMemory } from './ChatModels';
import { ChatFilesDirSeam } from '../../../services/ChatFilesDirSeam';
import {
  ChatHistoryLoadResult,
  ChatHistoryPersistence,
  ChatHistoryPreferencesPort,
  ChatHistorySaveResult,
  ChatHistoryStorePort,
  PreferencesChatHistoryPort,
  createFileChatHistoryStore,
  chatSnapshotPath,
} from '../../../services/ChatHistoryPersistence';

export function sid(): string {
  return Date.now().toString(36);
}

export class ChatSessionManager {
  private static activeManager: ChatSessionManager | null = null;
  private static latestSessions: ChatSession[] | undefined;
  private resolvedFilesDir: string = '';
  private persistence: ChatHistoryPersistence | null = null;
  private lastLoadResult: ChatHistoryLoadResult | null = null;
  private lastSaveResult: ChatHistorySaveResult | null = null;

  recordFilesDir(filesDir: string): void {
    this.resolvedFilesDir = filesDir.length > 0 ? filesDir : '';
  }

  getResolvedSnapshotPath(): string {
    return this.resolvedFilesDir.length === 0 ? '' : ChatFilesDirSeam.snapshotFile(this.resolvedFilesDir);
  }

  hasFilesDir(): boolean {
    return this.resolvedFilesDir.length > 0;
  }

  getLastLoadResult(): ChatHistoryLoadResult | null {
    return this.lastLoadResult;
  }

  getLastSaveResult(): ChatHistorySaveResult | null {
    return this.lastSaveResult;
  }

  async init(ctx: Context): Promise<ChatSession[]> {
    const prefs: preferences.Preferences = await preferences.getPreferences(ctx, 'chat_history');
    const store: ChatHistoryStorePort = createFileChatHistoryStore();
    const preferencePort: ChatHistoryPreferencesPort = new PreferencesChatHistoryPort(prefs);
    this.persistence = new ChatHistoryPersistence(store, preferencePort, chatSnapshotPath(this.resolvedFilesDir));
    ChatSessionManager.activeManager = this;
    this.lastLoadResult = await this.persistence.load();
    ChatSessionManager.latestSessions = this.lastLoadResult.sessions;
    return this.lastLoadResult.sessions;
  }

  save(sessions: ChatSession[], force: boolean = false): Promise<ChatHistorySaveResult> {
    if (this.persistence === null) {
      const result: ChatHistorySaveResult = ChatSessionManager.notInitializedResult();
      this.lastSaveResult = result;
      return Promise.resolve(result);
    }
    ChatSessionManager.latestSessions = sessions;
    return this.persistence.save(sessions, force).then((result: ChatHistorySaveResult): ChatHistorySaveResult => {
      return this.rememberSaveResult(result);
    });
  }

  flush(sessions: ChatSession[]): Promise<ChatHistorySaveResult> {
    if (this.persistence === null) {
      const result: ChatHistorySaveResult = ChatSessionManager.notInitializedResult();
      this.lastSaveResult = result;
      return Promise.resolve(result);
    }
    ChatSessionManager.latestSessions = sessions;
    return this.persistence.save(sessions, true).then((result: ChatHistorySaveResult): ChatHistorySaveResult => {
      return this.rememberSaveResult(result);
    });
  }

  retry(): Promise<ChatHistorySaveResult> {
    if (this.persistence === null) {
      const result: ChatHistorySaveResult = ChatSessionManager.notInitializedResult();
      this.lastSaveResult = result;
      return Promise.resolve(result);
    }
    return this.persistence.retry().then((result: ChatHistorySaveResult): ChatHistorySaveResult => {
      return this.rememberSaveResult(result);
    });
  }

  private rememberSaveResult(result: ChatHistorySaveResult): ChatHistorySaveResult {
    this.lastSaveResult = result;
    if (!result.success) {
      console.warn('[ChatSessionManager] chat history persistence recoverable: ' + result.diagnostic);
    }
    return result;
  }

  static flushActive(): Promise<ChatHistorySaveResult> {
    if (ChatSessionManager.activeManager === null || ChatSessionManager.latestSessions === undefined) {
      const result: ChatHistorySaveResult = {
        success: false,
        state: 'not-initialized',
        stage: 'PREPARE',
        transport: 'taskpool',
        retryable: false,
        diagnostic: 'stage=PREPARE; reason=no-active-chat-session; schemaVersion=1; ts=' + Date.now().toString(),
      };
      return Promise.resolve(result);
    }
    const sessions: ChatSession[] = copyChatSessionsForMemory(ChatSessionManager.latestSessions);
    return ChatSessionManager.activeManager.flush(sessions);
  }

  private static notInitializedResult(): ChatHistorySaveResult {
    const result: ChatHistorySaveResult = {
      success: false,
      state: 'not-initialized',
      stage: 'PREPARE',
      transport: 'taskpool',
      retryable: false,
      diagnostic: 'stage=PREPARE; reason=not-initialized; schemaVersion=1; ts=' + Date.now().toString(),
    };
    return result;
  }

}
