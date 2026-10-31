/**
 * RunStoreAdapter.ets — RunStorePort 的 entry 侧实现（校验 / committed 保护 / 错误分流）
 *
 * 路径: entry/src/main/ets/database/RunStoreAdapter.ets
 * 职责: 把 run 生命周期协议收敛到一处：runId 校验、create 幂等检查、update 时
 *       **committed 事实不被 cancelled 覆盖**、事件序号透传、错误码与 retryable 分流；
 *       持久化交给注入的 RunStoreStore（生产是 RunStoreDao）。
 * 依赖: common 的契约与错误类型；运行期只依赖注入的 store。
 *
 * 数据流:
 *   Dispatcher / NoteAgent → create / update / appendEvent → RunStoreStore → run_store / run_event
 *
 * 契约（#238 / §17.5）:
 *   - create：runId 必填、status 合法；同 runId 重复 create → RUN_EXISTS（不可重试）。
 *   - update：run 不存在 → RUN_NOT_FOUND（不可重试）；已有 committedNoteId 时，取消态不覆盖它。
 *   - appendEvent：runId / kind 必填，sequence 由存储层单调分配。
 *   - listEvents：afterSequence 默认 0，limit 默认 50、上限 200。
 *   - 存储失败统一 RUN_STORE_FAILED(retryable=true)；各类错误码不被压平。
 */
import {
  RUN_EVENTS_DEFAULT_LIMIT,
  RUN_EVENTS_MAX_LIMIT,
  RUN_STORE_ERROR_FAILED,
  RUN_STORE_ERROR_INVALID_RUN,
  RUN_STORE_ERROR_RUN_EXISTS,
  RUN_STORE_ERROR_RUN_NOT_FOUND,
  RunStoreError,
} from 'common';
import type { RunEvent, RunRecord, RunStorePort, RunStoreStore } from 'common';

const LEGAL_STATUSES: string[] = ['running', 'readyPreview', 'committed', 'cancelled', 'failed', 'timedOut'];

export class RunStoreAdapter implements RunStorePort {
  private readonly store: RunStoreStore;

  constructor(store: RunStoreStore) {
    this.store = store;
  }

  async create(record: RunRecord): Promise<void> {
    RunStoreAdapter.validateRecord(record);
    let existing: RunRecord | null = null;
    try {
      existing = await this.store.queryRecord(record.runId);
    } catch (e) {
      throw new RunStoreError(RUN_STORE_ERROR_FAILED, RunStoreAdapter.messageOf(e), true);
    }
    if (existing !== null) {
      throw new RunStoreError(RUN_STORE_ERROR_RUN_EXISTS, 'run already exists: ' + record.runId, false);
    }
    try {
      await this.store.insertRecord(record);
    } catch (e) {
      throw new RunStoreError(RUN_STORE_ERROR_FAILED, RunStoreAdapter.messageOf(e), true);
    }
  }

  async get(runId: string): Promise<RunRecord | null> {
    if (runId.length === 0) {
      throw new RunStoreError(RUN_STORE_ERROR_INVALID_RUN, 'runId must not be empty', false);
    }
    try {
      return await this.store.queryRecord(runId);
    } catch (e) {
      throw new RunStoreError(RUN_STORE_ERROR_FAILED, RunStoreAdapter.messageOf(e), true);
    }
  }

  async update(record: RunRecord): Promise<void> {
    RunStoreAdapter.validateRecord(record);
    let existing: RunRecord | null = null;
    try {
      existing = await this.store.queryRecord(record.runId);
    } catch (e) {
      throw new RunStoreError(RUN_STORE_ERROR_FAILED, RunStoreAdapter.messageOf(e), true);
    }
    if (existing === null) {
      throw new RunStoreError(RUN_STORE_ERROR_RUN_NOT_FOUND, 'run not found: ' + record.runId, false);
    }
    const merged: RunRecord = RunStoreAdapter.mergeCommitted(existing, record);
    try {
      await this.store.updateRecord(merged);
    } catch (e) {
      throw new RunStoreError(RUN_STORE_ERROR_FAILED, RunStoreAdapter.messageOf(e), true);
    }
  }

  async appendEvent(runId: string, kind: string, payloadJson: string): Promise<RunEvent> {
    if (runId.length === 0 || kind.length === 0) {
      throw new RunStoreError(RUN_STORE_ERROR_INVALID_RUN, 'runId and kind are required', false);
    }
    try {
      return await this.store.appendEvent(runId, kind, payloadJson.length > 0 ? payloadJson : '{}', Date.now());
    } catch (e) {
      throw new RunStoreError(RUN_STORE_ERROR_FAILED, RunStoreAdapter.messageOf(e), true);
    }
  }

  async listEvents(runId: string, afterSequence?: number, limit?: number): Promise<RunEvent[]> {
    if (runId.length === 0) {
      throw new RunStoreError(RUN_STORE_ERROR_INVALID_RUN, 'runId must not be empty', false);
    }
    const after: number = afterSequence === undefined || afterSequence < 0 ? 0 : afterSequence;
    let effectiveLimit: number = limit === undefined ? RUN_EVENTS_DEFAULT_LIMIT : limit;
    if (effectiveLimit < 1) {
      effectiveLimit = 1;
    }
    if (effectiveLimit > RUN_EVENTS_MAX_LIMIT) {
      effectiveLimit = RUN_EVENTS_MAX_LIMIT;
    }
    try {
      return await this.store.listEvents(runId, after, effectiveLimit);
    } catch (e) {
      throw new RunStoreError(RUN_STORE_ERROR_FAILED, RunStoreAdapter.messageOf(e), true);
    }
  }

  // committed 是既成事实：取消/失败态的回写不得把它抹掉。
  private static mergeCommitted(existing: RunRecord, incoming: RunRecord): RunRecord {
    const merged: RunRecord = {
      runId: incoming.runId,
      status: incoming.status,
      updatedAt: incoming.updatedAt,
    };
    merged.parentRunId = incoming.parentRunId !== undefined ? incoming.parentRunId : existing.parentRunId;
    merged.checkpointId = incoming.checkpointId !== undefined ? incoming.checkpointId : existing.checkpointId;
    merged.committedNoteId = incoming.committedNoteId !== undefined
      ? incoming.committedNoteId
      : existing.committedNoteId;
    merged.committedVersion = incoming.committedVersion !== undefined
      ? incoming.committedVersion
      : existing.committedVersion;
    return merged;
  }

  private static validateRecord(record: RunRecord): void {
    if (record.runId.length === 0) {
      throw new RunStoreError(RUN_STORE_ERROR_INVALID_RUN, 'runId must not be empty', false);
    }
    if (LEGAL_STATUSES.indexOf(record.status) < 0) {
      throw new RunStoreError(RUN_STORE_ERROR_INVALID_RUN, 'illegal run status: ' + record.status, false);
    }
  }

  private static messageOf(e: Object): string {
    return e instanceof Error ? e.message : String(e);
  }
}
