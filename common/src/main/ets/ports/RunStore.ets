/**
 * RunStore.ets — Run 持久化端口契约（接口 + 明确存储缺口）
 *
 * 路径: common/src/main/ets/ports/RunStore.ets
 * 职责: 只定义 run 记录与 Port 方法；本切片不实现生产适配器，也不伪造持久化。
 * 依赖: 无（零 Kit、零模型依赖）
 *
 * 数据流（目标态，尚未接线）:
 *   Dispatcher / NoteAgent → RunStorePort.create / get / update → Run 持久化实现（待迁移票）
 *
 * 明确缺口（必须先开迁移票，见 tasks.md #238 未决项）:
 *   1. parentRunId：note_generation_run 只有 parent_conversation_run_id（对话级），
 *      没有 parent_run_id（run 级父子图），父子图关系无处落库。
 *   2. 事件序号：没有 run_event 表（DatabaseHelper 现有 13 张表里没有 run_event），
 *      因此 eventId / 单调 sequence / 重放游标都无存储位置。
 *   3. 五终态落库：现有 run status 只有 NoteGenerationRepository 的运行态，没有
 *      running / readyPreview / cancelled / failed / timedOut 的统一终态列，也没有
 *      cancelled(committed=true) 所需的 committed_note_id / committed_version 组合。
 *   落地需要 ALTER TABLE 或新表 + 迁移/回滚方案；本切片只固定接口形状。
 *
 * ArkTS 1.1 strict 适配:
 *   - status 用字符串字面量联合类型（项目已有先例），调用方按值判别。
 *   - 可选字段显式声明，不使用索引签名。
 */

export type RunStatus = 'running' | 'readyPreview' | 'cancelled' | 'failed' | 'timedOut';

// 一条 run 的最小可恢复记录。parentRunId / eventId / sequence 目标态需要新列或新表。
export interface RunRecord {
  runId: string;
  parentRunId?: string;
  status: RunStatus;
  checkpointId?: string;
  committedNoteId?: string;
  committedVersion?: number;
  updatedAt: number;
}

// Run 持久化端口：create / get / update 都必须保留 committed 事实，不能被 cancelled 覆盖。
export interface RunStorePort {
  create(record: RunRecord): Promise<void>;
  get(runId: string): Promise<RunRecord | null>;
  update(record: RunRecord): Promise<void>;
}
