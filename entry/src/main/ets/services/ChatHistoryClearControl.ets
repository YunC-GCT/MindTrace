/**
 * ChatHistoryClearControl.ets — 清空对话历史控制存储
 *
 * 路径: entry/src/main/ets/services/ChatHistoryClearControl.ets
 * 职责: 用 Preferences 持久化清空状态、快照 epoch 与 pending token，为历史快照读写提供代际门禁。
 * 依赖: @kit.AbilityKit common；@kit.ArkData preferences；@kit.PerformanceAnalysisKit hilog
 *
 * 数据流:
 *   UI/协调器 → init(ctx) → beginClear / commit / abort
 *   ChatHistoryPersistence.save / load → getChatHistoryClearControl() → getState / isSnapshotBlocked
 *
 * 语义:
 *   - clear_state='pending' 时，任何快照都不得作为当前历史返回。
 *   - history_epoch 单调递增；epoch 小于当前值的历史快照视为过期。
 *   - 读写失败一律降级为默认值，只记录不含聊天正文/会话名/message id 的诊断日志。
 *
 * ArkTS 1.1 strict 适配:
 *   - 显式 type/interface；无 any/unknown/解构；同步 Preferences 使用 Sync 后缀 API。
 */
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';

export type ChatClearState = 'none' | 'pending' | 'completed';

export interface ChatClearControlState {
  clearState: ChatClearState;
  historyEpoch: number;
  pendingToken: string;
}

const STORE_NAME: string = 'chat_history_control';
const KEY_CLEAR_STATE: string = 'clear_state';
const KEY_HISTORY_EPOCH: string = 'history_epoch';
const KEY_PENDING_TOKEN: string = 'pending_token';
const DEFAULT_STATE: ChatClearState = 'none';
const DEFAULT_EPOCH: number = 0;
const DEFAULT_TOKEN: string = '';
const DOMAIN: number = 0xA2A0;
const TAG: string = 'ChatHistoryClear';

let activeControl: ChatHistoryClearControl | undefined = undefined;

/**
 * 返回最近一次 init() 的控制对象；未初始化时返回 undefined。
 * ChatHistoryPersistence 借此在拿不到控制对象时按 epoch=0 降级。
 */
export function getChatHistoryClearControl(): ChatHistoryClearControl | undefined {
  return activeControl;
}

export class ChatHistoryClearControl {
  private store: preferences.Preferences | undefined = undefined;
  private clearState: ChatClearState = DEFAULT_STATE;
  private historyEpoch: number = DEFAULT_EPOCH;
  private pendingToken: string = DEFAULT_TOKEN;

  /** 打开固定 store；已存在则读取三个键，任何异常都退回默认值。 */
  init(ctx: common.UIAbilityContext | Context): void {
    activeControl = this;
    try {
      const options: preferences.Options = { name: STORE_NAME };
      this.store = preferences.getPreferencesSync(ctx, options);
    } catch (error) {
      this.store = undefined;
      this.clearState = DEFAULT_STATE;
      this.historyEpoch = DEFAULT_EPOCH;
      this.pendingToken = DEFAULT_TOKEN;
      this.logError('CHAT_HISTORY_CONTROL_INIT_FAILED', 'store');
      return;
    }
    this.clearState = this.readClearState();
    this.historyEpoch = this.readHistoryEpoch();
    this.pendingToken = this.readPendingToken();
  }

  getState(): ChatClearControlState {
    return {
      clearState: this.clearState,
      historyEpoch: this.historyEpoch,
      pendingToken: this.pendingToken,
    };
  }

  /** epoch += 1，写 pending 状态与新 token，flush 后返回新 epoch。 */
  beginClear(): number {
    const nextEpoch: number = this.historyEpoch + 1;
    const token: string = nextEpoch.toString() + '-' + Date.now().toString();
    this.historyEpoch = nextEpoch;
    this.clearState = 'pending';
    this.pendingToken = token;
    this.persist('pending', nextEpoch, token);
    return nextEpoch;
  }

  /** 清空完成：写 completed、清空 token，epoch 不变。 */
  commit(): void {
    this.clearState = 'completed';
    this.pendingToken = DEFAULT_TOKEN;
    this.persist('completed', this.historyEpoch, DEFAULT_TOKEN);
  }

  /** 清空放弃：撤销 beginClear 的 epoch 自增，把 pending 改回 none。 */
  abort(): void {
    if (this.clearState !== 'pending') {
      return;
    }
    // beginClear 已把 epoch +1；回退后旧快照 epoch(N) 才不会永久低于控制 epoch(N+1)。
    this.historyEpoch = Math.max(0, this.historyEpoch - 1);
    this.clearState = DEFAULT_STATE;
    this.persist(DEFAULT_STATE, this.historyEpoch, this.pendingToken);
  }

  isSnapshotBlocked(snapshotEpoch: number): boolean {
    if (this.clearState === 'pending') {
      return true;
    }
    return snapshotEpoch < this.historyEpoch;
  }

  private readClearState(): ChatClearState {
    if (this.store === undefined) {
      return DEFAULT_STATE;
    }
    try {
      const value: preferences.ValueType = this.store.getSync(KEY_CLEAR_STATE, DEFAULT_STATE);
      if (typeof value !== 'string') {
        this.logError('CHAT_HISTORY_CONTROL_READ_INVALID', KEY_CLEAR_STATE);
        return DEFAULT_STATE;
      }
      if (value === 'none' || value === 'pending' || value === 'completed') {
        return value as ChatClearState;
      }
      this.logError('CHAT_HISTORY_CONTROL_READ_INVALID', KEY_CLEAR_STATE);
      return DEFAULT_STATE;
    } catch (error) {
      this.logError('CHAT_HISTORY_CONTROL_READ_FAILED', KEY_CLEAR_STATE);
      return DEFAULT_STATE;
    }
  }

  private readHistoryEpoch(): number {
    if (this.store === undefined) {
      return DEFAULT_EPOCH;
    }
    try {
      const value: preferences.ValueType = this.store.getSync(KEY_HISTORY_EPOCH, DEFAULT_EPOCH);
      if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0) {
        this.logError('CHAT_HISTORY_CONTROL_READ_INVALID', KEY_HISTORY_EPOCH);
        return DEFAULT_EPOCH;
      }
      return value;
    } catch (error) {
      this.logError('CHAT_HISTORY_CONTROL_READ_FAILED', KEY_HISTORY_EPOCH);
      return DEFAULT_EPOCH;
    }
  }

  private readPendingToken(): string {
    if (this.store === undefined) {
      return DEFAULT_TOKEN;
    }
    try {
      const value: preferences.ValueType = this.store.getSync(KEY_PENDING_TOKEN, DEFAULT_TOKEN);
      if (typeof value !== 'string') {
        this.logError('CHAT_HISTORY_CONTROL_READ_INVALID', KEY_PENDING_TOKEN);
        return DEFAULT_TOKEN;
      }
      return value;
    } catch (error) {
      this.logError('CHAT_HISTORY_CONTROL_READ_FAILED', KEY_PENDING_TOKEN);
      return DEFAULT_TOKEN;
    }
  }

  private persist(state: ChatClearState, epoch: number, token: string): void {
    if (this.store === undefined) {
      this.logError('CHAT_HISTORY_CONTROL_WRITE_FAILED', 'store');
      return;
    }
    try {
      this.store.putSync(KEY_CLEAR_STATE, state);
      this.store.putSync(KEY_HISTORY_EPOCH, epoch);
      this.store.putSync(KEY_PENDING_TOKEN, token);
      // 同步写接口必须用 flushSync 落盘，等价于 flush()。
      this.store.flushSync();
    } catch (error) {
      this.logError('CHAT_HISTORY_CONTROL_WRITE_FAILED', 'store');
    }
  }

  private logError(code: string, key: string): void {
    hilog.error(DOMAIN, TAG, 'code=%{public}s key=%{public}s', code, key);
  }
}
