/**
 * ChatHistoryClearCoordinator.ets — 清空全部聊天历史的跨存储协调器
 *
 * 路径: entry/src/main/ets/services/ChatHistoryClearCoordinator.ets
 * 职责: 按 prepare → rdb → verify → snapshot → finalize 顺序编排清空，维护 pending/epoch 语义。
 * 依赖: @kit.ArkData relationalStore；@kit.PerformanceAnalysisKit hilog；./ChatHistoryClearControl
 *
 * 数据流:
 *   UI/ViewModel → ChatHistoryClearCoordinator.clearAll()
 *     → ChatHistoryClearControl.beginClear()
 *     → deps.quiesce() → deps.store 事务删除 → querySql 复核
 *     → deps.flushSnapshot([]) → control.commit() → deps.refreshCards()
 *
 * 语义:
 *   - 纯服务：依赖全部构造注入，不 new 全局单例、不引用 UI。
 *   - prepare/rdb 失败：control.abort() 回退 epoch，旧快照继续可用。
 *   - verify/snapshot 失败：已提交的删除不回退，保留 pending 让下次启动走恢复。
 *   - 日志只含状态与计数，不含聊天正文/会话名/message id。
 *
 * ArkTS 1.1 strict 适配:
 *   - 显式 interface/返回类型；无 any/unknown/解构；catch 不标注类型。
 */
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ChatHistoryClearControl } from './ChatHistoryClearControl';
import type { ChatSession } from '../overlays/AgentFloatWindow/chat/ChatModels';
import type { ChatHistorySaveResult } from './ChatHistoryPersistence';

const DOMAIN: number = 0xA2A0;
const TAG: string = 'ChatHistoryClear';

export interface ChatHistoryClearDeps {
  store: relationalStore.RdbStore;                       // 来自 DatabaseHelper.getStore()
  quiesce: () => Promise<void>;                          // 取消并等待所有 in-flight run
  flushSnapshot: (sessions: ChatSession[]) => Promise<ChatHistorySaveResult>;  // 调用方传 ChatSessionManager.flush([])
  refreshCards: () => Promise<void>;                     // 调用方传 CardSnapshotService.refresh
}

export interface ChatHistoryClearResult {
  success: boolean;
  stage: 'prepare' | 'rdb' | 'verify' | 'snapshot' | 'finalize';
  epoch: number;
  chatRows: number;
  derivedRows: number;
  diagnostic: string;
}

export class ChatHistoryClearCoordinator {
  private readonly deps: ChatHistoryClearDeps;
  private readonly control: ChatHistoryClearControl;

  constructor(deps: ChatHistoryClearDeps, control: ChatHistoryClearControl) {
    this.deps = deps;
    this.control = control;
  }

  async clearAll(): Promise<ChatHistoryClearResult> {
    let epoch: number = this.control.getState().historyEpoch;
    try {
      epoch = this.control.beginClear();
      await this.deps.quiesce();
    } catch (error) {
      this.control.abort();
      return this.failure('prepare', epoch, 0, 0, 'code=CHAT_HISTORY_CLEAR_PREPARE_FAILED', true);
    }

    const rdbFailed: ChatHistoryClearResult | undefined = await this.deleteAllChatRows(epoch);
    if (rdbFailed !== undefined) {
      return rdbFailed;
    }

    let chatRows: number = 0;
    let derivedRows: number = 0;
    try {
      chatRows = await this.countRows('SELECT COUNT(*) FROM chat_message');
      derivedRows = await this.countRows(
        "SELECT COUNT(*) FROM agent_memory WHERE type IN ('summary','pending_note','ocr_result')");
    } catch (error) {
      // 删除已提交，不回退；保留 pending 等待下次启动恢复。
      return this.failure('verify', epoch, chatRows, derivedRows,
        'code=CHAT_HISTORY_CLEAR_VERIFY_FAILED', true);
    }
    if (chatRows > 0 || derivedRows > 0) {
      return this.failure('verify', epoch, chatRows, derivedRows,
        'code=CHAT_HISTORY_CLEAR_VERIFY_FAILED; chatRows=' + chatRows.toString()
          + '; derivedRows=' + derivedRows.toString(), true);
    }

    try {
      const saved: ChatHistorySaveResult = await this.deps.flushSnapshot([]);
      if (saved.state !== 'completed') {
        return this.failure('snapshot', epoch, chatRows, derivedRows,
          'code=CHAT_HISTORY_CLEAR_SNAPSHOT_FAILED; saveState=' + saved.state, true);
      }
    } catch (error) {
      return this.failure('snapshot', epoch, chatRows, derivedRows,
        'code=CHAT_HISTORY_CLEAR_SNAPSHOT_FAILED', true);
    }

    this.control.commit();
    try {
      await this.deps.refreshCards();
    } catch (error) {
      // 数据、空快照与 epoch 已落盘并 commit；卡片缓存刷新失败不影响清空结果，仅记录。
      hilog.warn(DOMAIN, TAG,
        'code=CHAT_HISTORY_CLEAR_CARD_REFRESH_FAILED; epoch=%{public}d', epoch);
    }

    hilog.info(DOMAIN, TAG,
      'code=CHAT_HISTORY_CLEAR_SUCCEEDED scope=all chatRows=%{public}d derivedRows=%{public}d epoch=%{public}d',
      chatRows, derivedRows, epoch);
    return {
      success: true,
      stage: 'finalize',
      epoch: epoch,
      chatRows: chatRows,
      derivedRows: derivedRows,
      diagnostic: 'code=CHAT_HISTORY_CLEAR_SUCCEEDED; scope=all',
    };
  }

  /** 在一个事务里删除聊天消息与三类派生记忆；失败回滚 + abort，成功返回 undefined。 */
  private async deleteAllChatRows(epoch: number): Promise<ChatHistoryClearResult | undefined> {
    let tx: relationalStore.Transaction | undefined = undefined;
    try {
      tx = await this.deps.store.createTransaction();
      await tx.execute('DELETE FROM chat_message');
      await tx.execute(
        'DELETE FROM agent_memory WHERE type IN (?,?,?)',
        ['summary', 'pending_note', 'ocr_result'],
      );
      await tx.commit();
      return undefined;
    } catch (error) {
      if (tx !== undefined) {
        // 与 NoteDao.rollback(transaction) 同一写法：RdbStore Transaction 上是 rollback()。
        try {
          await tx.rollback();
        } catch (rollbackError) {
        }
      }
      this.control.abort();
      return this.failure('rdb', epoch, 0, 0, 'code=CHAT_HISTORY_CLEAR_RDB_FAILED', true);
    }
  }

  private async countRows(sql: string): Promise<number> {
    const rs: relationalStore.ResultSet = await this.deps.store.querySql(sql);
    try {
      if (!rs.goToFirstRow()) {
        return 0;
      }
      return rs.getLong(0);
    } finally {
      rs.close();
    }
  }

  private failure(
    stage: 'prepare' | 'rdb' | 'verify' | 'snapshot' | 'finalize',
    epoch: number,
    chatRows: number,
    derivedRows: number,
    diagnostic: string,
    retryable: boolean,
  ): ChatHistoryClearResult {
    hilog.error(DOMAIN, TAG,
      'code=CHAT_HISTORY_CLEAR_FAILED stage=%{public}s retryable=%{public}d epoch=%{public}d',
      stage, retryable ? 1 : 0, epoch);
    return {
      success: false,
      stage: stage,
      epoch: epoch,
      chatRows: chatRows,
      derivedRows: derivedRows,
      diagnostic: diagnostic,
    };
  }
}
