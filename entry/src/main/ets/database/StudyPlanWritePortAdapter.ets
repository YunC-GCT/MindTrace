/**
 * StudyPlanWritePortAdapter.ets — StudyPlanWritePort 的 entry 侧实现（幂等 + CAS）
 *
 * 路径: entry/src/main/ets/database/StudyPlanWritePortAdapter.ets
 * 职责: 待办写入协议：operationId 幂等、expectedVersion CAS、错误码与 retryable 分流；
 *       持久化交给注入的 StudyPlanWriteStore（生产是 StudyPlanWriteStoreDao）。
 * 依赖: common 的契约与错误类型；运行期只依赖注入的 store。
 *
 * 数据流:
 *   待办 UI → create / update / complete → StudyPlanWriteStore → study_plan + study_plan_op
 *
 * 契约（#238 / §17.5，待办语义，ADR-0022）:
 *   - operationId 必填；同一 operationId 重放返回首次结果（duplicate=true），不再写。
 *   - create：item.id 可为空（由存储生成）；重复 id 由存储唯一约束拒绝。
 *   - update：不存在 → STUDY_PLAN_NOT_FOUND；expectedVersion 不一致 → VERSION_CONFLICT（不可重试）。
 *   - complete：不存在 → STUDY_PLAN_NOT_FOUND；已完成的重复调用按幂等成功返回。
 *   - 存储失败统一 STUDY_PLAN_WRITE_FAILED(retryable=true)。
 */
import {
  STUDY_PLAN_ERROR_INVALID_PLAN,
  STUDY_PLAN_ERROR_NOT_FOUND,
  STUDY_PLAN_ERROR_OPERATION_REQUIRED,
  STUDY_PLAN_ERROR_VERSION_CONFLICT,
  STUDY_PLAN_ERROR_WRITE_FAILED,
  StudyPlanError,
} from 'common';
import type {
  StudyPlanOperationRecord,
  StudyPlanRecord,
  StudyPlanWriteCommand,
  StudyPlanWriteOutcome,
  StudyPlanWritePort,
  StudyPlanWriteRecord,
  StudyPlanWriteStore,
} from 'common';

export class StudyPlanWritePortAdapter implements StudyPlanWritePort {
  private readonly store: StudyPlanWriteStore;

  constructor(store: StudyPlanWriteStore) {
    this.store = store;
  }

  async create(item: StudyPlanRecord, command: StudyPlanWriteCommand): Promise<StudyPlanWriteOutcome> {
    StudyPlanWritePortAdapter.validateCommand(command);
    StudyPlanWritePortAdapter.validateItem(item);
    const replayed: StudyPlanWriteOutcome | null = await this.replay(command.operationId);
    if (replayed !== null) {
      return replayed;
    }
    const written: StudyPlanWriteRecord = await this.writeInsert(item, command);
    return StudyPlanWritePortAdapter.toOutcome(written, command.operationId, false);
  }

  async update(item: StudyPlanRecord, command: StudyPlanWriteCommand): Promise<StudyPlanWriteOutcome> {
    StudyPlanWritePortAdapter.validateCommand(command);
    if (item.id.length === 0) {
      throw new StudyPlanError(STUDY_PLAN_ERROR_INVALID_PLAN, 'update requires a plan id', false);
    }
    const replayed: StudyPlanWriteOutcome | null = await this.replay(command.operationId);
    if (replayed !== null) {
      return replayed;
    }
    const existing: StudyPlanWriteRecord = await this.requireExisting(item.id);
    StudyPlanWritePortAdapter.checkVersion(existing, command);
    const written: StudyPlanWriteRecord = await this.writeUpdate(item, command);
    return StudyPlanWritePortAdapter.toOutcome(written, command.operationId, false);
  }

  async complete(id: string, command: StudyPlanWriteCommand): Promise<StudyPlanWriteOutcome> {
    StudyPlanWritePortAdapter.validateCommand(command);
    if (id.length === 0) {
      throw new StudyPlanError(STUDY_PLAN_ERROR_INVALID_PLAN, 'complete requires a plan id', false);
    }
    const replayed: StudyPlanWriteOutcome | null = await this.replay(command.operationId);
    if (replayed !== null) {
      return replayed;
    }
    const existing: StudyPlanWriteRecord = await this.requireExisting(id);
    StudyPlanWritePortAdapter.checkVersion(existing, command);
    if (existing.isDone) {
      // 已完成是幂等终态：不回写、不报错。
      return StudyPlanWritePortAdapter.toOutcome(existing, command.operationId, true);
    }
    let written: StudyPlanWriteRecord;
    try {
      written = await this.store.setDone(id, true, command);
    } catch (e) {
      throw new StudyPlanError(STUDY_PLAN_ERROR_WRITE_FAILED, StudyPlanWritePortAdapter.messageOf(e), true);
    }
    return StudyPlanWritePortAdapter.toOutcome(written, command.operationId, false);
  }

  private async replay(operationId: string): Promise<StudyPlanWriteOutcome | null> {
    let operation: StudyPlanOperationRecord | null = null;
    try {
      operation = await this.store.queryOperation(operationId);
    } catch (e) {
      throw new StudyPlanError(STUDY_PLAN_ERROR_WRITE_FAILED, StudyPlanWritePortAdapter.messageOf(e), true);
    }
    if (operation === null) {
      return null;
    }
    const outcome: StudyPlanWriteOutcome = {
      id: operation.planId,
      version: operation.version,
      operationId: operation.operationId,
      duplicate: true,
      committedAt: operation.committedAt,
    };
    return outcome;
  }

  private async requireExisting(id: string): Promise<StudyPlanWriteRecord> {
    let existing: StudyPlanWriteRecord | null = null;
    try {
      existing = await this.store.queryRecord(id);
    } catch (e) {
      throw new StudyPlanError(STUDY_PLAN_ERROR_WRITE_FAILED, StudyPlanWritePortAdapter.messageOf(e), true);
    }
    if (existing === null) {
      throw new StudyPlanError(STUDY_PLAN_ERROR_NOT_FOUND, 'study plan not found: ' + id, false);
    }
    return existing;
  }

  private async writeInsert(item: StudyPlanRecord, command: StudyPlanWriteCommand): Promise<StudyPlanWriteRecord> {
    try {
      return await this.store.insertRecord(item, command);
    } catch (e) {
      throw new StudyPlanError(STUDY_PLAN_ERROR_WRITE_FAILED, StudyPlanWritePortAdapter.messageOf(e), true);
    }
  }

  private async writeUpdate(item: StudyPlanRecord, command: StudyPlanWriteCommand): Promise<StudyPlanWriteRecord> {
    try {
      return await this.store.updateRecord(item, command);
    } catch (e) {
      throw new StudyPlanError(STUDY_PLAN_ERROR_WRITE_FAILED, StudyPlanWritePortAdapter.messageOf(e), true);
    }
  }

  private static checkVersion(existing: StudyPlanWriteRecord, command: StudyPlanWriteCommand): void {
    const expected: number | undefined = command.expectedVersion;
    if (expected !== undefined && existing.version !== expected) {
      throw new StudyPlanError(STUDY_PLAN_ERROR_VERSION_CONFLICT,
        'version conflict: expected ' + expected.toString() + ', actual ' + existing.version.toString(), false);
    }
  }

  private static validateCommand(command: StudyPlanWriteCommand): void {
    if (command.operationId.trim().length === 0) {
      throw new StudyPlanError(STUDY_PLAN_ERROR_OPERATION_REQUIRED,
        'operationId is required for every durable write', false);
    }
  }

  private static validateItem(item: StudyPlanRecord): void {
    if (item.title.trim().length === 0) {
      throw new StudyPlanError(STUDY_PLAN_ERROR_INVALID_PLAN, 'title must not be empty', false);
    }
  }

  private static toOutcome(record: StudyPlanWriteRecord, operationId: string,
    duplicate: boolean): StudyPlanWriteOutcome {
    const outcome: StudyPlanWriteOutcome = {
      id: record.id,
      version: record.version,
      operationId: operationId,
      duplicate: duplicate,
      committedAt: Date.now(),
    };
    return outcome;
  }

  private static messageOf(e: Object): string {
    return e instanceof Error ? e.message : String(e);
  }
}
