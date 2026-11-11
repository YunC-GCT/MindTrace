/**
 * NoteOutcomeMapper.ets — NoteCommand ↔ BranchRequest 的入口映射（A4 4c 后旧 DispatchResult 已下线）
 *
 * 路径: agents/src/main/ets/core/dispatch/NoteOutcomeMapper.ets
 * 职责: ① NoteCommand → 旧 BranchRequest/DispatchOptions（复用现有分支实现）；
 *       ③ 抛错 → cancelled(committed=false) / failed(NODE_ERROR)。
 * 依赖: common 的 BranchRequest + NoteCommand/NoteOutcome。
 *
 * 边界（A3 迁移期）:
 *   - 只在这一个文件里做语义映射；分支模块不感知 NoteCommand/NoteOutcome。
 *   - committed 的 noteId/version 由分支直接构造；commitKey 优先命令携带值，
 *     其次 preparedCandidate.commitKey，capture 用持久层合成的 `capture:<noteId>` 口径。
 *   - cancelled(committed=true) 还拿不到：持久层尚未把事务结果回传给分支（记在 tasks.md 未勾选项）。
 */
import { NOTE_CANCELLED_MESSAGE, isRetryableNoteErrorCode } from 'common';
import type {
  DispatchPayload,
  BranchRequest,
  KnowledgeUnit,
  NoteCommand,
  NoteGenerationResult,
  NoteOutcome,
} from 'common';
import type { DispatchOptions } from './DispatchOptions';

export class NoteOutcomeMapper {
  /** NoteCommand → 旧 BranchRequest（generation/prepared 走原有分支）。 */
  static toRequest(command: NoteCommand): BranchRequest {
    // operationId 透传给分支，供 NoteOutcome 构造。
    const source = command.source !== undefined ? command.source : 'app';
    if (command.kind === 'preparedCandidate') {
      const candidate: KnowledgeUnit | undefined = command.preparedCandidate !== undefined
        ? command.preparedCandidate.candidate : undefined;
      const payload: DispatchPayload = command.payload !== undefined
        ? command.payload
        : { kind: 'text', text: candidate !== undefined ? candidate.content : '' };
      return { source: source, payload: payload, preparedCandidate: command.preparedCandidate, commitKey: command.commitKey };
    }
    if (command.kind === 'generation' || command.kind === 'regenerate') {
      const payload: DispatchPayload = command.payload !== undefined
        ? command.payload
        : { kind: 'text', text: '' };
      return { source: source, payload: payload, generation: command.generation, commitKey: command.commitKey };
    }
    const payload: DispatchPayload = command.payload !== undefined
      ? command.payload
      : { kind: 'text', text: '' };
    return { source: source, payload: payload, commitKey: command.commitKey };
  }

  /** NoteCommand → 旧 DispatchOptions：按命令形状决定 persist / analysisOnly，其余字段透传。 */
  static toOptions(command: NoteCommand, options: DispatchOptions): DispatchOptions {
    const copy: DispatchOptions = {};
    copy.persist = command.kind === 'capture' || command.kind === 'preparedCandidate';
    copy.analysisOnly = command.kind === 'analysisOnly';
    copy.includeRawText = command.includeRawText !== undefined ? command.includeRawText : options.includeRawText;
    copy.dao = options.dao;
    copy.noteWritePort = options.noteWritePort;
    copy.generationRepository = options.generationRepository;
    copy.knowledgeModel = options.knowledgeModel;
    copy.cancellationToken = options.cancellationToken;
    copy.runContext = options.runContext;
    copy.progressSink = options.progressSink;
    copy.onNodeTiming = options.onNodeTiming;
    copy.subjectVocabulary = options.subjectVocabulary;
    copy.runEventSink = options.runEventSink;
    copy.skipLlmClassification = options.skipLlmClassification;
    copy.compactStructure = options.compactStructure;
    return copy;
  }


  /** 抛错 → 入口取消 / 兜底失败。 */
  static fromThrown(command: NoteCommand, error: Error): NoteOutcome {
    const message: string = error.message;
    if (message.indexOf(NOTE_CANCELLED_MESSAGE) >= 0) {
      return {
        kind: 'cancelled',
        operationId: command.operationId,
        route: 'D1',
        durationMs: 0,
        committed: false,
      };
    }
    const code: string = NoteOutcomeMapper.codeFromMessage(message);
    return {
      kind: 'failed',
      operationId: command.operationId,
      route: 'D1',
      durationMs: 0,
      code: code,
      message: message,
      retryable: isRetryableNoteErrorCode(code),
    };
  }

  /** 旧 seam 里只有中文文案的错误，补成稳定错误码（ADR-0019 (c)）。 */
  private static codeFromMessage(message: string): string {
    if (message.indexOf('VERSION_CONFLICT') >= 0) { return 'VERSION_CONFLICT'; }
    if (message.indexOf(NOTE_CANCELLED_MESSAGE) >= 0) { return 'CANCELLED'; }
    if (message.indexOf('候选内容已变化') >= 0 || message.indexOf('草稿检查点不匹配') >= 0) {
      return 'APPROVAL_HASH_MISMATCH';
    }
    if (message.indexOf('缺少草稿检查点') >= 0 || message.indexOf('草稿运行不存在') >= 0) {
      return 'PREPARED_CHECKPOINT_MISSING';
    }
    return 'NODE_ERROR';
  }

  private static resolveCommitKey(command: NoteCommand, unit: KnowledgeUnit): string {
    if (command.commitKey !== undefined && command.commitKey.length > 0) {
      return command.commitKey;
    }
    if (command.kind === 'preparedCandidate' && command.preparedCandidate !== undefined) {
      const prepared = command.preparedCandidate;
      if (prepared.commitKey !== undefined && prepared.commitKey.length > 0) {
        return prepared.commitKey;
      }
      return prepared.runId + ':' + prepared.checkpointId + ':' + prepared.candidateHash;
    }
    return 'capture:' + unit.id;
  }

  private static firstQuestion(generation: NoteGenerationResult): string {
    if (generation.questions !== undefined && generation.questions.length > 0) {
      const question: string = generation.questions[0];
      if (question.length > 0) {
        return question;
      }
    }
    return 'needs-input';
  }
}
