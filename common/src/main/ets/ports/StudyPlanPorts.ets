/**
 * StudyPlanPorts.ets — 学习计划读侧契约（现状待办语义，不是复习计划）
 *
 * 路径: common/src/main/ets/ports/StudyPlanPorts.ets
 * 职责: 只固定 `study_plan` 当前“待办”读侧的形状；不定义写侧、不定义复习评分/掌握度。
 * 依赖: 无（零 Kit、零模型依赖）
 *
 * 数据流（目标态，尚未接线）:
 *   UI / ViewModel → StudyPlanReadPort.listPending / get → entry 适配器 → study_plan 表
 *
 * 领域边界:
 *   - 现状 `study_plan` 是待办表（id / title / is_done / priority / linked_note_id / created_at /
 *     due_date），没有 subject 列。`subject` 在适配器里只能由 linked note 派生，或返回空串；
 *     本切片不新增列。
 *   - `study_plan` 升级为间隔复习计划（review_item / review_log、评分、掌握度）必须等 #242 拍板，
 *     本切片不预埋复习字段，也不定义 StudyPlanWritePort。
 *
 * ArkTS 1.1 strict 适配:
 *   - 纯 interface + 字符串字段，布尔字段用 done，不使用索引签名或对象字面量类型。
 *   - 与既有 models/StudyPlan.ets 的 @Observed UI 类同名，barrel 导出时使用
 *     StudyPlanPendingItem 这个别名，避免覆盖既有导出。
 */

// 读侧的待办项。dueAt 是截止时间戳（ms），0 表示无截止；done 对应 is_done。
export interface StudyPlanItem {
  id: string;
  subject: string;
  title: string;
  dueAt: number;
  done: boolean;
}

// barrel 导出名：既有的 models/StudyPlan.StudyPlanItem 是 UI @Observed 类，不能重名。
export type StudyPlanPendingItem = StudyPlanItem;

// 读侧端口：只读待办，不提供写入/复习评分能力。
export interface StudyPlanReadPort {
  listPending(subject?: string): Promise<StudyPlanItem[]>;
  get(id: string): Promise<StudyPlanItem | null>;
}

// 持久层原始行：字段与 study_plan 表一致（isDone / dueDate 是存储名，不是端口名）。
export interface StudyPlanRecord {
  id: string;
  title: string;
  isDone: boolean;
  priority: number;
  linkedNoteId: string;
  createdAt: number;
  dueDate: number;
}

// DAO 需要满足的最小存储缝：契约在 common，实现（StudyPlanDao）在 entry。
export interface StudyPlanReadStore {
  queryAll(): Promise<StudyPlanRecord[]>;
}

// 读侧稳定错误码：结构与其他 Port 一致，供 UI / A2A 分流。
export const STUDY_PLAN_ERROR_READ_FAILED: string = 'STUDY_PLAN_READ_FAILED';

// ==================== 写侧（待办语义，不是复习评分） ====================

// 写命令：operationId 必填作为幂等键；expectedVersion 有值即 CAS（schema v17 给 study_plan 加了 version 列）。
export interface StudyPlanWriteCommand {
  operationId: string;
  expectedVersion?: number;
}

// 写回执：duplicate=true 表示同一 operationId 重放，未产生第二次写入。
export interface StudyPlanWriteOutcome {
  id: string;
  version: number;
  operationId: string;
  duplicate: boolean;
  committedAt?: number;
}

// 持久层写记录：比读记录多 version（CAS 用）。
export interface StudyPlanWriteRecord extends StudyPlanRecord {
  version: number;
}

// 幂等操作记录：与写入放在同一事务里。
export interface StudyPlanOperationRecord {
  operationId: string;
  planId: string;
  kind: string;
  version: number;
  committedAt: number;
}

// 写侧存储缝：契约在 common，实现（StudyPlanWriteStoreDao）在 entry。
// 三个写方法都带 command（operationId），DAO 必须把「业务写入 + 操作记录」放在同一事务里。
export interface StudyPlanWriteStore {
  queryOperation(operationId: string): Promise<StudyPlanOperationRecord | null>;
  queryRecord(id: string): Promise<StudyPlanWriteRecord | null>;
  insertRecord(item: StudyPlanRecord, command: StudyPlanWriteCommand): Promise<StudyPlanWriteRecord>;
  updateRecord(item: StudyPlanRecord, command: StudyPlanWriteCommand): Promise<StudyPlanWriteRecord>;
  setDone(id: string, done: boolean, command: StudyPlanWriteCommand): Promise<StudyPlanWriteRecord>;
}

// 写侧稳定错误（结构与其他端口一致）。
export class StudyPlanError extends Error {
  readonly code: string;
  readonly retryable: boolean;

  constructor(code: string, message: string, retryable: boolean) {
    super(message);
    this.name = 'StudyPlanError';
    this.code = code;
    this.retryable = retryable;
  }
}

// 写侧端口：待办 CRUD，不提供复习评分/掌握度（那属 ReviewAgent，ADR-0022）。
export interface StudyPlanWritePort {
  create(item: StudyPlanRecord, command: StudyPlanWriteCommand): Promise<StudyPlanWriteOutcome>;
  update(item: StudyPlanRecord, command: StudyPlanWriteCommand): Promise<StudyPlanWriteOutcome>;
  complete(id: string, command: StudyPlanWriteCommand): Promise<StudyPlanWriteOutcome>;
}

// 写侧稳定错误码（与 ADR-0019 的分流口径一致）。
export const STUDY_PLAN_ERROR_OPERATION_REQUIRED: string = 'OPERATION_ID_REQUIRED';
export const STUDY_PLAN_ERROR_INVALID_PLAN: string = 'INVALID_STUDY_PLAN';
export const STUDY_PLAN_ERROR_NOT_FOUND: string = 'STUDY_PLAN_NOT_FOUND';
export const STUDY_PLAN_ERROR_VERSION_CONFLICT: string = 'VERSION_CONFLICT';
export const STUDY_PLAN_ERROR_WRITE_FAILED: string = 'STUDY_PLAN_WRITE_FAILED';
