/**
 * NoteWritePortAdapter.ets — NoteWritePort 的 entry 侧实现（判定 + 幂等 + CAS + 取消）
 *
 * 路径: entry/src/main/ets/database/NoteWritePortAdapter.ets
 * 职责: 把「写一条 Note」的协议逻辑收敛到一处：commitKey 幂等、expectedVersion CAS、
 *       审批哈希校验、取消语义、错误码与 retryable 分流；持久化交给注入的 NoteWriteStore。
 * 依赖: common 的契约与纯判定（decideWrite 从 common barrel 引入）；运行期只依赖注入的 store。
 *
 * 数据流:
 *   NoteAgent / HITL 确认 → commit(unit, command) → queryCommit → decideWrite → store.insert / update
 *
 * 契约实现（#238 / ADR-0019 (d)，顺序不得交换）:
 *   1. commitKey 空 → COMMIT_KEY_REQUIRED（不碰存储）
 *   2. 已取消且未写 → 返回 cancelled 且 committed=false 的终态，不做 IO
 *   3. 同 commitKey 已落过 → duplicate=true，返回首次 noteId / version / committedAt，不再写
 *   4. expectedVersion 与当前版本不等 → VERSION_CONFLICT（不可重试）
 *   5. 传了 approvedCheckpointHash 但当前快照没有/不一致 → APPROVAL_HASH_MISMATCH
 *   6. 其余 → insert（无 id）/ update（有 id）
 *   7. store 抛错：NotePortError 原样保留 code/retryable；其他错误包成 NOTE_WRITE_FAILED(retryable=true)
 *
 * 取消语义（ADR-0019）:
 *   - 提交前取消 → cancelled=true / committed=false，不产生副作用；
 *   - 提交后取消 → cancelled=true / committed=true，并带回 noteId / version / commitKey；
 *   - 已落库的写不能靠 token 撤回；调用方用同一 commitKey 重放即可判定是否已提交。
 */
import { NotePortError, NOTE_WRITE_ERROR_FAILED, decideWrite } from 'common';
import type {
  CancellationToken,
  KnowledgeUnit,
  NoteSnapshot,
  NoteWriteCommand,
  NoteWriteOutcome,
  NoteWritePort,
  NoteWriteSnapshot,
  NoteWriteStore,
  WriteDecision,
} from 'common';

export class NoteWritePortAdapter implements NoteWritePort {
  private readonly store: NoteWriteStore;

  constructor(store: NoteWriteStore) {
    this.store = store;
  }

  async commit(unit: KnowledgeUnit, command: NoteWriteCommand): Promise<NoteWriteOutcome> {
    // 1. commitKey 必填先于任何 IO：空 key 不能借落库动作去探测。
    if (command.commitKey.trim().length === 0) {
      throw new NotePortError('COMMIT_KEY_REQUIRED', 'commitKey is required for every durable write', false);
    }

    // 2. 提交前取消：返回终态，不产生副作用。
    if (NoteWritePortAdapter.isCancelled(command.cancellationToken)) {
      return NoteWritePortAdapter.cancelledOutcome(command.commitKey);
    }

    // 3. 幂等重放：同 commitKey 已落过就返回首次结果，不产生第二次写入。
    const replayed: NoteWriteSnapshot | null = await this.readCommit(command.commitKey);
    if (replayed !== null) {
      return NoteWritePortAdapter.toOutcome(replayed, command.commitKey, true, command.cancellationToken);
    }

    // 4. 取当前 note 快照（没有 id 视为新建）。
    const snapshot: NoteWriteSnapshot | null = unit.id.length > 0 ? await this.readSnapshot(unit.id) : null;
    const decision: WriteDecision = decideWrite(snapshot, command);
    if (decision.kind === 'duplicate' && snapshot !== null) {
      return NoteWritePortAdapter.toOutcome(snapshot, command.commitKey, true, command.cancellationToken);
    }
    if (decision.kind === 'conflict' || decision.kind === 'reject') {
      throw new NotePortError(decision.code, decision.message, decision.retryable);
    }

    // 5. 落库：insert 或 update（update 的 CAS 版本优先取命令里的 expectedVersion）。
    const written: NoteWriteSnapshot = decision.kind === 'insert'
      ? await this.insert(unit, command)
      : await this.update(unit, command, snapshot);
    return NoteWritePortAdapter.toOutcome(written, command.commitKey, false, command.cancellationToken);
  }

  private async readCommit(commitKey: string): Promise<NoteWriteSnapshot | null> {
    try {
      return await this.store.queryCommit(commitKey);
    } catch (e) {
      if (e instanceof NotePortError) {
        throw new NotePortError(e.code, e.message, e.retryable);
      }
      throw new NotePortError(NOTE_WRITE_ERROR_FAILED, NoteWritePortAdapter.messageOf(e), true);
    }
  }

  private async readSnapshot(noteId: string): Promise<NoteWriteSnapshot | null> {
    try {
      return await this.store.querySnapshot(noteId);
    } catch (e) {
      if (e instanceof NotePortError) {
        throw new NotePortError(e.code, e.message, e.retryable);
      }
      throw new NotePortError(NOTE_WRITE_ERROR_FAILED, NoteWritePortAdapter.messageOf(e), true);
    }
  }

  private async insert(unit: KnowledgeUnit, command: NoteWriteCommand): Promise<NoteWriteSnapshot> {
    try {
      return await this.store.insert(unit, command);
    } catch (e) {
      if (e instanceof NotePortError) {
        throw new NotePortError(e.code, e.message, e.retryable);
      }
      throw new NotePortError(NOTE_WRITE_ERROR_FAILED, NoteWritePortAdapter.messageOf(e), true);
    }
  }

  private async update(unit: KnowledgeUnit, command: NoteWriteCommand,
    snapshot: NoteSnapshot | null): Promise<NoteWriteSnapshot> {
    const expectedVersion: number = command.expectedVersion !== undefined
      ? command.expectedVersion
      : (snapshot !== null ? snapshot.version : 0);
    try {
      return await this.store.update(unit, expectedVersion, command);
    } catch (e) {
      if (e instanceof NotePortError) {
        throw new NotePortError(e.code, e.message, e.retryable);
      }
      throw new NotePortError(NOTE_WRITE_ERROR_FAILED, NoteWritePortAdapter.messageOf(e), true);
    }
  }

  private static messageOf(e: Object): string {
    return e instanceof Error ? e.message : String(e);
  }

  private static isCancelled(token?: CancellationToken): boolean {
    return token !== undefined && token.isCancelled();
  }

  private static cancelledOutcome(commitKey: string): NoteWriteOutcome {
    const outcome: NoteWriteOutcome = {
      noteId: '',
      version: 0,
      commitKey: commitKey,
      duplicate: false,
      committed: false,
      cancelled: true,
    };
    return outcome;
  }

  private static toOutcome(snapshot: NoteWriteSnapshot, commitKey: string, duplicate: boolean,
    token?: CancellationToken): NoteWriteOutcome {
    const outcome: NoteWriteOutcome = {
      noteId: snapshot.noteId,
      version: snapshot.version,
      commitKey: commitKey,
      duplicate: duplicate || snapshot.duplicate === true,
      committed: true,
      cancelled: NoteWritePortAdapter.isCancelled(token),
    };
    if (snapshot.committedAt !== undefined) {
      outcome.committedAt = snapshot.committedAt;
    }
    return outcome;
  }
}
