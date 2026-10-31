/**
 * NoteOutcomeMapper.ets — 旧 DispatchRequest/DispatchResult ↔ 新 NoteCommand/NoteOutcome 的迁移适配器
 *
 * 路径: agents/src/main/ets/core/dispatch/NoteOutcomeMapper.ets
 * 职责: ① NoteCommand → 旧 DispatchRequest/DispatchOptions（复用现有分支实现）；
 *       ② 旧 DispatchResult → NoteOutcome（补稳定错误码、retryable、needsInput/readyPreview/committed 判别）；
 *       ③ 抛错 → cancelled(committed=false) / failed(NODE_ERROR)。
 * 依赖: common 的 DispatchRequest/DispatchResult（旧契约）+ NoteCommand/NoteOutcome（新契约）。
 *
 * 边界（A3 迁移期）:
 *   - 只在这一个文件里做语义映射；分支模块不感知 NoteCommand/NoteOutcome。
 *   - committed 的 noteId/version 取自 DispatchResult.data（迁移期尽力而为）；commitKey 优先命令携带值，
 *     其次 preparedCandidate.commitKey，capture 用持久层合成的 `capture:<noteId>` 口径。
 *   - cancelled(committed=true) 还拿不到：持久层尚未把事务结果回传给分支（记在 tasks.md 未勾选项）。
 */
import { NOTE_CANCELLED_MESSAGE, isRetryableNoteErrorCode } from 'common';
import type {
  DispatchPayload,
  DispatchRequest,
  DispatchResult,
  KnowledgeUnit,
  NoteCommand,
  NoteGenerationResult,
  NoteOutcome,
} from 'common';
import type { DispatchOptions } from './DispatchOptions';

export class NoteOutcomeMapper {
  /** NoteCommand → 旧 DispatchRequest（generation/prepared 走原有分支）。 */
  static toRequest(command: NoteCommand): DispatchRequest {
    const source = command.source !== undefined ? command.source : 'app';
    if (command.kind === 'preparedCandidate') {
      const candidate: KnowledgeUnit | undefined = command.preparedCandidate !== undefined
        ? command.preparedCandidate.candidate : undefined;
      const payload: DispatchPayload = command.payload !== undefined
        ? command.payload
        : { kind: 'text', text: candidate !== undefined ? candidate.content : '' };
      return { source: source, payload: payload, preparedCandidate: command.preparedCandidate };
    }
    if (command.kind === 'generation' || command.kind === 'regenerate') {
      const payload: DispatchPayload = command.payload !== undefined
        ? command.payload
        : { kind: 'text', text: '' };
      return { source: source, payload: payload, generation: command.generation };
    }
    const payload: DispatchPayload = command.payload !== undefined
      ? command.payload
      : { kind: 'text', text: '' };
    return { source: source, payload: payload };
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
    // 新 seam 需要分支回填迁移字段（cancelled(committed) / 稳定错误码 / retriable）。
    copy.reportCancellation = true;
    return copy;
  }

  /** 旧 DispatchResult → NoteOutcome。错误码/retryable/终态判别集中在这里。 */
  static toOutcome(command: NoteCommand, result: DispatchResult): NoteOutcome {
    const durationMs: number = result.durationMs;
    if (!result.success) {
      const message: string = result.errorMessage !== undefined ? result.errorMessage : '';
      const code: string = result.errorCode !== undefined
        ? result.errorCode
        : NoteOutcomeMapper.codeFromMessage(message);
      if (result.cancelledCommitted !== undefined) {
        const cancelledUnit: KnowledgeUnit | undefined = result.cancelledCommitted === true ? result.data : undefined;
        const knownKey: string | undefined = result.cancelledCommitKey !== undefined
          && result.cancelledCommitKey.length > 0 ? result.cancelledCommitKey : undefined;
        return {
          kind: 'cancelled',
          operationId: command.operationId,
          route: 'D1',
          durationMs: durationMs,
          committed: result.cancelledCommitted,
          noteId: result.cancelledNoteId,
          version: result.cancelledVersion !== undefined
            ? result.cancelledVersion
            : (cancelledUnit !== undefined ? cancelledUnit.version : undefined),
          commitKey: knownKey !== undefined
            ? knownKey
            : (cancelledUnit !== undefined ? NoteOutcomeMapper.resolveCommitKey(command, cancelledUnit) : undefined),
          unit: cancelledUnit,
          classification: result.classification,
          recognizedText: result.recognizedText,
        };
      }
      if (code === 'CANCELLED' || message.indexOf(NOTE_CANCELLED_MESSAGE) >= 0) {
        return {
          kind: 'cancelled',
          operationId: command.operationId,
          route: 'D1',
          durationMs: durationMs,
          committed: false,
        };
      }
      const generation: NoteGenerationResult | undefined = result.generation;
      if (generation !== undefined && generation.status === 'needs-input') {
        return {
          kind: 'needsInput',
          operationId: command.operationId,
          route: 'D1',
          durationMs: durationMs,
          reason: message.length > 0 ? message : NoteOutcomeMapper.firstQuestion(generation),
          issues: generation.issues !== undefined ? generation.issues : [],
          generation: generation,
        };
      }
      return {
        kind: 'failed',
        operationId: command.operationId,
        route: 'D1',
        durationMs: durationMs,
        code: code,
        message: message,
        retryable: result.errorRetryable !== undefined
          ? result.errorRetryable : isRetryableNoteErrorCode(code),
        classification: result.classification,
        recognizedText: result.recognizedText,
        generation: generation,
      };
    }
    const unit: KnowledgeUnit | undefined = result.data;
    const generation: NoteGenerationResult | undefined = result.generation;
    if (command.kind === 'generation' || command.kind === 'regenerate') {
      const runId: string = generation !== undefined
        ? generation.runId
        : (command.generation !== undefined ? command.generation.runId : '');
      const checkpointId: string = generation !== undefined && generation.bestCheckpointId !== undefined
        ? generation.bestCheckpointId : '';
      return {
        kind: 'readyPreview',
        operationId: command.operationId,
        route: 'D1',
        durationMs: durationMs,
        runId: runId,
        checkpointId: checkpointId,
        draft: unit,
        classification: result.classification,
        recognizedText: result.recognizedText,
        generation: generation,
      };
    }
    if (command.kind === 'analysisOnly') {
      return {
        kind: 'readyPreview',
        operationId: command.operationId,
        route: 'D1',
        durationMs: durationMs,
        runId: '',
        checkpointId: '',
        classification: result.classification,
        recognizedText: result.recognizedText,
      };
    }
    // ADR-0019 (d)：没有写结果不得返回 committed。
    if (unit === undefined) {
      return {
        kind: 'failed',
        operationId: command.operationId,
        route: 'D1',
        durationMs: durationMs,
        code: 'PERSIST_ERROR',
        message: '命令要求持久化，但分支没有返回写入结果',
        retryable: false,
      };
    }
    return {
      kind: 'committed',
      operationId: command.operationId,
      route: 'D1',
      durationMs: durationMs,
      noteId: unit.id,
      version: unit.version,
      commitKey: NoteOutcomeMapper.resolveCommitKey(command, unit),
      unit: unit,
      classification: result.classification,
      recognizedText: result.recognizedText,
      generation: generation,
    };
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
