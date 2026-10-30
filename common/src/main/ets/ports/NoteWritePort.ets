/**
 * NoteWritePort.ets — Note 写入端口契约（commitKey 幂等 / expectedVersion CAS / 审批哈希）
 *
 * 路径: common/src/main/ets/ports/NoteWritePort.ets
 * 职责: 只声明入口侧 Note 写入端口、命令形状与稳定错误类型；不含 DAO、Kit 或任何实现。
 * 依赖: ../models/CommonTypes (KnowledgeUnit)、./NoteWriteDecisions (NoteSnapshot，纯投影)、
 *       ../llm/CancellationToken (取消令牌，type-only)
 *
 * 数据流:
 *   Dispatcher / 未来 NoteAgent → NoteWritePort.commit(unit, command) → entry 适配器 → NoteDao 事务
 *
 * 错误码归属:
 *   COMMIT_KEY_REQUIRED / VERSION_CONFLICT / NOTE_NOT_FOUND / APPROVAL_HASH_MISMATCH 属 ADR-0019 (c)
 *   NoteOutcome 码表；NOTE_WRITE_FAILED 是**端口传输层**的兜底码（存储 IO 失败），不进 ADR 码表。
 *
 * 契约（ADR-0019 (d) 与 #238 切片 A）:
 *   - commitKey 必填；同一 commitKey 重放必须返回首次 noteId/version（duplicate=true），不产生第二次写入。
 *   - expectedVersion 有值即 CAS；existing.version 不相等时返回 VERSION_CONFLICT。
 *   - approvedCheckpointHash 有值即要求 existing.approvedCheckpointHash 一致，防止绕过 HITL。
 *   - retryable 的语义是「同一请求重放能否成功」，与 ADR-0019 (c) 错误码表一致：
 *     VERSION_CONFLICT / APPROVAL_HASH_MISMATCH / NOTE_NOT_FOUND / COMMIT_KEY_REQUIRED 全为 false，
 *     因为正确动作是重读状态或重新预览，而不是原样再发一次。
 *
 * ArkTS 1.1 strict 适配:
 *   - 可选字段用 `?:`，判定侧显式与 undefined 比较，不做解构。
 *   - 错误类显式声明字段并在构造器赋值，不使用构造器参数属性简写。
 */
import { KnowledgeUnit } from '../models/CommonTypes';
import type { NoteSnapshot } from './NoteWriteDecisions';
import type { CancellationToken } from '../llm/CancellationToken';

// 一次 Note 写入的幂等命令。commitKey 必填，其余为可选约束。
export interface NoteWriteCommand {
  commitKey: string;                 // 必填，幂等键
  expectedVersion?: number;          // 有值即 CAS
  approvedCheckpointHash?: string;   // 有值即要求审批哈希一致
  cancellationToken?: CancellationToken; // 提交前后检查取消；已提交不可撤回
  // 提交记录的业务元数据（写入 note_generation_commit；缺省由适配器给占位值）
  runId?: string;
  checkpointId?: string;
  sourceIds?: string[];
  generationMetadata?: string;
}

// 写入端口的成功回执：duplicate=true 表示同 commitKey 重放，未产生第二次写入。
// cancelled=true 表示调用方在提交前后取消：committed 如实反映是否已落库（ADR-0019「取消语义」）。
export interface NoteWriteOutcome {
  noteId: string;
  version: number;
  commitKey: string;
  duplicate: boolean;
  committed: boolean;
  cancelled: boolean;
  /** 首次提交时间（ms）；重放时沿用首次值，供卡片 / Trace 判断落后于哪个提交 */
  committedAt?: number;
}

// 端口层稳定错误：code 取 ADR-0019 错误码，retryable 供 UI / A2A / HITL 分流。
export class NotePortError extends Error {
  readonly code: string;
  readonly retryable: boolean;

  constructor(code: string, message: string, retryable: boolean) {
    super(message);
    this.name = 'NotePortError';
    this.code = code;
    this.retryable = retryable;
  }
}

// 写入端口。实现由 entry 侧适配器提供，common 不依赖任何 Kit。
export interface NoteWritePort {
  commit(unit: KnowledgeUnit, command: NoteWriteCommand): Promise<NoteWriteOutcome>;
}

// 写入所需的最小存储缝（契约在 common，实现在 entry）：
//   queryCommit    —— 幂等查：这个 commitKey 有没有落过，返回首次 noteId / version
//   querySnapshot  —— 取当前 note 的版本与审批哈希，供 CAS / HITL 校验
//   insert / update —— 真正的持久化，必须和 commitKey 记录在同一事务里
// 存储实现可以回填 duplicate（事务内发现重放）与 committedAt（提交时间），端口据此区分竞态重放。
export interface NoteWriteSnapshot extends NoteSnapshot {
  duplicate?: boolean;
  committedAt?: number;
}

export interface NoteWriteStore {
  queryCommit(commitKey: string): Promise<NoteWriteSnapshot | null>;
  querySnapshot(noteId: string): Promise<NoteWriteSnapshot | null>;
  insert(unit: KnowledgeUnit, command: NoteWriteCommand): Promise<NoteWriteSnapshot>;
  update(unit: KnowledgeUnit, expectedVersion: number, command: NoteWriteCommand): Promise<NoteWriteSnapshot>;
}

// 写入侧稳定错误码（ADR-0019 (c)）：与 decideWrite 的判定码保持一致。
export const NOTE_WRITE_ERROR_FAILED: string = 'NOTE_WRITE_FAILED';

// NoteSnapshot 定义在 NoteWriteDecisions（纯判定与适配器共用同一投影，避免两套字段）。
