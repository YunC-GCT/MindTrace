/**
 * NoteWritePort.ets — Note 写入端口契约（commitKey 幂等 / expectedVersion CAS / 审批哈希）
 *
 * 路径: common/src/main/ets/ports/NoteWritePort.ets
 * 职责: 只声明入口侧 Note 写入端口、命令形状与稳定错误类型；不含 DAO、Kit 或任何实现。
 * 依赖: ../models/CommonTypes (KnowledgeUnit，相对路径，避免 barrel 循环)
 *
 * 数据流:
 *   Dispatcher / 未来 NoteAgent → NoteWritePort.commit(unit, command) → entry 适配器 → NoteDao 事务
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

// 一次 Note 写入的幂等命令。commitKey 必填，其余为可选约束。
export interface NoteWriteCommand {
  commitKey: string;                 // 必填，幂等键
  expectedVersion?: number;          // 有值即 CAS
  approvedCheckpointHash?: string;   // 有值即要求审批哈希一致
}

// 写入端口的成功回执：duplicate=true 表示同 commitKey 重放，未产生第二次写入。
export interface NoteWriteOutcome {
  noteId: string;
  version: number;
  commitKey: string;
  duplicate: boolean;
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
