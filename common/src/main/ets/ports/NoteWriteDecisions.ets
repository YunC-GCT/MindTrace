/**
 * NoteWriteDecisions.ets — Note 写入纯判定（幂等 / CAS / 审批哈希）
 *
 * 路径: common/src/main/ets/ports/NoteWriteDecisions.ets
 * 职责: 把一次写入应落到的五种分支（insert / update / duplicate / conflict / reject）做成纯函数，
 *       不读库、不写库、不 import 任何 Kit，便于 Node 侧直接装载做契约测试。
 * 依赖: ./NoteWritePort (NoteWriteCommand，相对路径，避免 barrel 循环)
 *
 * 数据流:
 *   NoteWritePort 适配器 → decideWrite(existing, command) → insert / update / duplicate / 冲突 / 拒绝
 *
 * 判定顺序（严格按 #238 / ADR-0019 (d)，不得交换）:
 *   1. commitKey 空 → reject / COMMIT_KEY_REQUIRED / 不可重试
 *   2. existing=null 且 expectedVersion>0 → conflict / NOTE_NOT_FOUND / 不可重试
 *   3. existing 的 commitKey 与命令相同 → duplicate（不是错误，code 为空串）
 *   4. expectedVersion 有值且与 existing.version 不等 → conflict / VERSION_CONFLICT / 可重试
 *   5. approvedCheckpointHash 有值且与 existing 的不同 → reject / APPROVAL_HASH_MISMATCH / 可重试
 *      （existing=null 时没有可比较的哈希，同样视为不一致，不能静默 insert）
 *   6. existing=null → insert；否则 → update
 *
 * ArkTS 1.1 strict 适配:
 *   - 用字符串字面量联合类型（项目已有先例），不写 enum，调用方可直接按 kind 判别。
 *   - 每个返回值都显式标注 WriteDecision，避免无类型对象字面量。
 */
import { NoteWriteCommand } from './NoteWritePort';

// 判定所需的现有 Note 投影；只包含判定真正用到的字段。
export interface NoteSnapshot {
  noteId: string;
  version: number;
  commitKey?: string;
  approvedCheckpointHash?: string;
}

export type WriteDecisionKind = 'insert' | 'update' | 'duplicate' | 'conflict' | 'reject';

// 判定结果：非失败分支 code 为空串；失败分支 code 取 ADR-0019 错误码。
export interface WriteDecision {
  kind: WriteDecisionKind;
  code: string;        // 非失败时为空串
  message: string;
  retryable: boolean;
}

// 内部构造器：集中保证 WriteDecision 的字段完整，避免各分支漏字段。
function decision(kind: WriteDecisionKind, code: string, message: string, retryable: boolean): WriteDecision {
  const result: WriteDecision = {
    kind: kind,
    code: code,
    message: message,
    retryable: retryable,
  };
  return result;
}

export function decideWrite(existing: NoteSnapshot | null, command: NoteWriteCommand): WriteDecision {
  const expectedVersion: number | undefined = command.expectedVersion;
  const approvalHash: string | undefined = command.approvedCheckpointHash;
  const approvalRequired: boolean = approvalHash !== undefined && approvalHash.length > 0;

  // 1. commitKey 必填。空串 / 纯空白都视为缺失，宁可拒绝也不静默双写。
  if (typeof command.commitKey !== 'string' || command.commitKey.trim().length === 0) {
    return decision('reject', 'COMMIT_KEY_REQUIRED', 'commitKey is required for every durable write', false);
  }

  // 2. 目标不存在却带着正数 expectedVersion：调用方持有陈旧 UI，不能当成 insert。
  //    expectedVersion=0 表示“期望尚不存在”，所以只有 > 0 才判 NOTE_NOT_FOUND。
  if (existing === null && expectedVersion !== undefined && expectedVersion > 0) {
    return decision('conflict', 'NOTE_NOT_FOUND',
      'note not found for expectedVersion=' + expectedVersion.toString(), false);
  }

  // 3. 同 commitKey 重放优先于版本检查：这是幂等成功，不是冲突。
  if (existing !== null && existing.commitKey !== undefined && existing.commitKey === command.commitKey) {
    return decision('duplicate', '', 'duplicate commitKey replay; no second write', false);
  }

  // 4. 有 expectedVersion 即 CAS。落后（或超前）都返回冲突；同一请求重放不会成功，
  //    所以 retryable=false —— 调用方必须重读最新版本再提交（ADR-0019 (c)）。
  if (existing !== null && expectedVersion !== undefined && existing.version !== expectedVersion) {
    return decision('conflict', 'VERSION_CONFLICT',
      'version conflict: expected ' + expectedVersion.toString() + ', actual ' + existing.version.toString(), false);
  }

  // 5. 审批哈希有值即必须一致；不一致说明候选已过期。
  //    existing=null 时没有可比较的 approvedCheckpointHash，同样视为不一致：
  //    传了审批哈希却找不到现有 note，不能静默 insert，否则会绕过 HITL 校验。
  //    重放同一请求只会再次不匹配，故 retryable=false：正确动作是丢弃陈旧候选、重新预览。
  if (approvalRequired && (existing === null || existing.approvedCheckpointHash !== approvalHash)) {
    return decision('reject', 'APPROVAL_HASH_MISMATCH',
      'approved checkpoint hash does not match the current note', false);
  }

  // 6. 兜底：无现有行插入，有现有行更新。
  if (existing === null) {
    return decision('insert', '', 'insert new note', false);
  }
  return decision('update', '', 'update existing note', false);
}
