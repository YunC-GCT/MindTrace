/**
 * CommandExecutor.ets — 命令执行器（spec 039；替代原 CommandExecutor）
 *
 * 路径: agents/src/main/ets/core/CommandExecutor.ets
 * 职责: 一条 NoteCommand 的 run 生命周期：建 run（runId=operationId）→ preflight/路由（委托 CommandRouter）
 *       → 调具体 workflow（capture/generation/regenerate/prepared）→ committed 信封 verify → terminal 事件 + settle。
 *       异常统一映射五终态（NoteOutcomeMapper），不判断业务分支、不碰 DAO。
 * 依赖: common（NoteCommand/NoteOutcome/RunContext/NoteGenerationRepository 等）、
 *       ./dispatch/{DispatchOptions,BatchSupport,NoteOutcomeMapper,RunEventSink}、./CommandRouter、
 *       ../workflows/{WorkflowContext,NoteCaptureWorkflow,NoteGenerationWorkflow,NoteRegenerateWorkflow,NotePreparedWorkflow}
 * 数据流: 调用方（AiService 等）→ CommandExecutor.dispatchCommand(command, options) → CommandRouter
 *       → workflow.run() → NoteOutcome（五终态）→ run_event(start/terminal) + sink.settle()
 *
 * 边界: 保留 `dispatchCommand` / `dispatchSetCommand` 方法名（ADR-0019 调用方签名不变）。
 *       CaptureGraph 的节点执行在各 workflow 内部，本类不感知。
 */
import {
  Logger,
  RunContext,
  createRootRunContext,
  PreparedCandidate,
  NoteGenerationCheckpoint,
  NoteGenerationRepository,
  isRetryableNoteErrorCode,
} from 'common';
import type {
  NoteBatchOutcome,
  NoteCommand,
  NoteOutcome,
} from 'common';
import type { CaptureSetOptions, DispatchOptions } from './dispatch/DispatchOptions';
import { isBatchCancelled, withRunContext } from './dispatch/BatchSupport';
import { NoteOutcomeMapper } from './dispatch/NoteOutcomeMapper';
import {
  DISPATCH_EVENT_START,
  DISPATCH_EVENT_TERMINAL,
  RUN_EVENT_APPROVAL_REJECTED,
  RUN_EVENT_COMMIT_COMMITTED,
  RUN_EVENT_NODE_ENDED,
  approvalRejectedPayload,
  commitCommittedPayload,
  dispatchStartPayload,
  dispatchTerminalPayload,
  nodeEndedPayload,
} from './dispatch/RunEventSink';
import { CommandRouter, RouterPreflightResult } from './CommandRouter';
import type { WorkflowContext } from '../workflows/WorkflowContext';
import { NoteCaptureWorkflow } from '../workflows/NoteCaptureWorkflow';
import { NoteGenerationWorkflow } from '../workflows/NoteGenerationWorkflow';
import { NoteRegenerateWorkflow } from '../workflows/NoteRegenerateWorkflow';
import { NotePreparedWorkflow } from '../workflows/NotePreparedWorkflow';

// DispatchOptions / CaptureSetOptions 已抽到 ./dispatch/DispatchOptions，这里重导出保持既有 import 路径。
export type { CaptureSetOptions, DispatchOptions } from './dispatch/DispatchOptions';

const log = new Logger('CommandExecutor');

interface EnvelopeViolation {
  code: string;
  message: string;
  retryable: boolean;
}

export class CommandExecutor {
  // 与 StateGraph 老的 maxNodeRuns=128 保持一致：接线不改变各条路径的可用节点数。
  private static readonly RUN_BUDGET: number = 128;
  private readonly router: CommandRouter;
  private readonly captureWorkflow: NoteCaptureWorkflow = new NoteCaptureWorkflow();
  private readonly generationWorkflow: NoteGenerationWorkflow = new NoteGenerationWorkflow();
  private readonly regenerateWorkflow: NoteRegenerateWorkflow = new NoteRegenerateWorkflow();
  private readonly preparedWorkflow: NotePreparedWorkflow = new NotePreparedWorkflow();

  constructor(router?: CommandRouter) {
    this.router = router !== undefined ? router : new CommandRouter();
  }

  // 预算与取消只走调用参数。四条 workflow 都从这里拿上下文，免得哪条忘了转发就把刹车和预算一起丢掉。
  private resolveRunContext(options: DispatchOptions): RunContext {
    return options.runContext ?? createRootRunContext(
      'dispatch-' + Date.now().toString(),
      CommandExecutor.RUN_BUDGET,
      0,
      options.cancellationToken ?? null,
    );
  }

  // A4 4c Step2：分支直接返回 NoteOutcome 后，旧出口由 NoteOutcomeMapper 补的字段要在这里补回：
  // ① committed 幂等信封（noteId + version + commitKey，ADR-0019 (d)）——capture 走 legacy DAO
  //    时持久层只回 noteId/version，commitKey 沿用 `capture:<noteId>` 口径；
  // ② failed.retryable 缺省值（ADR-0019 (c)：由稳定错误码决定能否重试）。
  private static normalizeInvokedOutcome(command: NoteCommand, outcome: NoteOutcome): NoteOutcome {
    if (outcome.kind === 'failed' && outcome.retryable === undefined) {
      outcome.retryable = isRetryableNoteErrorCode(outcome.code !== undefined ? outcome.code : '');
    }
    const needsEnvelope: boolean = outcome.kind === 'committed'
      || (outcome.kind === 'cancelled' && outcome.committed === true);
    if (!needsEnvelope || (outcome.commitKey !== undefined && outcome.commitKey.length > 0)) {
      return outcome;
    }
    if (command.commitKey !== undefined && command.commitKey.length > 0) {
      outcome.commitKey = command.commitKey;
      return outcome;
    }
    if (command.kind === 'preparedCandidate' && command.preparedCandidate !== undefined) {
      const prepared: PreparedCandidate = command.preparedCandidate;
      if (prepared.commitKey !== undefined && prepared.commitKey.length > 0) {
        outcome.commitKey = prepared.commitKey;
      } else {
        outcome.commitKey = prepared.runId + ':' + prepared.checkpointId + ':' + prepared.candidateHash;
      }
      return outcome;
    }
    const noteId: string = outcome.noteId !== undefined ? outcome.noteId : '';
    if (noteId.length > 0) {
      outcome.commitKey = 'capture:' + noteId;
    }
    return outcome;
  }

  // ADR-0019 (d)：committed 必须带 noteId + version + commitKey（写端口/事务结果），否则不得算成功。
  private static verifyOutcome(outcome: NoteOutcome): EnvelopeViolation | undefined {
    if (outcome.kind !== 'committed') {
      return undefined;
    }
    const noteId: string = outcome.noteId !== undefined ? outcome.noteId : '';
    const commitKey: string = outcome.commitKey !== undefined ? outcome.commitKey : '';
    if (noteId.length === 0 || outcome.version === undefined || commitKey.length === 0) {
      return {
        code: 'PERSIST_ERROR',
        message: 'committed 终态缺少 noteId/version/commitKey 信封',
        retryable: false,
      };
    }
    return undefined;
  }

  private static failedOutcome(command: NoteCommand, code: string, message: string,
    retryable: boolean): NoteOutcome {
    const failed: NoteOutcome = {
      kind: 'failed',
      operationId: command.operationId,
      route: 'D1',
      durationMs: 0,
      code: code,
      message: message,
      retryable: retryable,
    };
    return failed;
  }

  private workflowFor(id: string): NoteCaptureWorkflow | NoteGenerationWorkflow
    | NoteRegenerateWorkflow | NotePreparedWorkflow {
    if (id === 'generation') {
      return this.generationWorkflow;
    }
    if (id === 'regenerate') {
      return this.regenerateWorkflow;
    }
    if (id === 'prepared') {
      return this.preparedWorkflow;
    }
    return this.captureWorkflow;
  }

  // A4：run 事件写出是尽力而为的 —— sink 抛错只记日志，不影响命令结果。
  private static async emitRunEvent(
    options: DispatchOptions,
    runId: string,
    kind: string,
    payloadJson: string,
  ): Promise<void> {
    const sink = options.runEventSink;
    if (sink === undefined) {
      return;
    }
    try {
      await sink.emit(runId, { kind: kind, payloadJson: payloadJson });
      log.info('run_event kind=' + kind + ' runId=' + runId);
    } catch (e) {
      log.warn('run event sink failed kind=' + kind + ' runId=' + runId
        + ' err=' + (e instanceof Error ? e.message : String(e)));
    }
  }

  // A4：终态回写 run 记录（RunStorePort），同样尽力而为。
  private static async settleRun(options: DispatchOptions, runId: string, outcome: NoteOutcome): Promise<void> {
    const sink = options.runEventSink;
    if (sink === undefined || sink.settle === undefined) {
      return;
    }
    try {
      await sink.settle(runId, outcome);
    } catch (e) {
      log.warn('run settle failed runId=' + runId + ' err=' + (e instanceof Error ? e.message : String(e)));
    }
  }

  /**
   * ADR-0019 / A3d：批量命令入口（一个 set 一个 run）。
   * 顺序执行 commands，共享同一个 RunContext；逐项仍是 NoteOutcome，单项失败不打断整批；
   * 取消后剩余项记 cancelled(committed=false)，不混进 failed。
   */
  async dispatchSetCommand(
    commands: NoteCommand[],
    options: DispatchOptions = {},
    onOutcome?: (index: number, outcome: NoteOutcome) => void,
  ): Promise<NoteBatchOutcome> {
    const startedAt: number = Date.now();
    const shared: RunContext = this.resolveRunContext(options);
    const items: NoteOutcome[] = [];
    let committed: number = 0;
    let failed: number = 0;
    let cancelled: number = 0;
    let needsInput: number = 0;
    let stop: boolean = false;
    for (let i = 0; i < commands.length; i++) {
      const command: NoteCommand = commands[i];
      if (stop || isBatchCancelled(options)) {
        const skipped: NoteOutcome = {
          kind: 'cancelled',
          operationId: command.operationId,
          route: 'D1',
          durationMs: 0,
          committed: false,
        };
        items.push(skipped);
        cancelled += 1;
        if (onOutcome !== undefined) { onOutcome(i, skipped); }
        continue;
      }
      const outcome: NoteOutcome = await this.dispatchCommand(command, withRunContext(options, shared));
      items.push(outcome);
      if (outcome.kind === 'committed') {
        committed += 1;
      } else if (outcome.kind === 'cancelled') {
        cancelled += 1;
        stop = true;
      } else if (outcome.kind === 'needsInput') {
        needsInput += 1;
      } else {
        failed += 1;
      }
      if (onOutcome !== undefined) { onOutcome(i, outcome); }
    }
    const result: NoteBatchOutcome = {
      total: commands.length,
      committed: committed,
      failed: failed,
      cancelled: cancelled,
      needsInput: needsInput,
      items: items,
      durationMs: Date.now() - startedAt,
    };
    return result;
  }

  /** 命令主入口：preflight → workflow → verify → terminal/settle；保留 dispatchCommand 名称以兼容 ADR-0019 调用方。 */
  async dispatchCommand(command: NoteCommand, options: DispatchOptions = {}): Promise<NoteOutcome> {
    const request = NoteOutcomeMapper.toRequest(command);
    const effective: DispatchOptions = NoteOutcomeMapper.toOptions(command, options);
    await CommandExecutor.emitRunEvent(
      options, command.operationId, DISPATCH_EVENT_START, dispatchStartPayload(command));

    const preflight: RouterPreflightResult = await this.router.preflight(command, options);
    if (preflight.errorCode !== undefined) {
      const message: string = preflight.errorMessage !== undefined
        ? preflight.errorMessage : preflight.errorCode;
      await CommandExecutor.emitRunEvent(options, command.operationId, RUN_EVENT_APPROVAL_REJECTED,
        approvalRejectedPayload(preflight.errorCode, message));
      return CommandExecutor.failedOutcome(command, preflight.errorCode, message, preflight.retryable === true);
    }

    let outcome: NoteOutcome;
    if (preflight.outcome !== undefined) {
      outcome = preflight.outcome;
    } else {
      // spec 039 S3：节点结束时发 node.ended（runId=operationId）；原 onNodeTiming 回调保持透传。
      const userTiming: ((step: string, elapsedMs: number) => void) | undefined = effective.onNodeTiming;
      effective.onNodeTiming = (step: string, elapsedMs: number): void => {
        if (userTiming !== undefined) {
          userTiming(step, elapsedMs);
        }
        CommandExecutor.emitRunEvent(options, command.operationId, RUN_EVENT_NODE_ENDED,
          nodeEndedPayload(step, elapsedMs)).catch((): void => {});
      };
      const context: WorkflowContext = {
        request: request,
        options: effective,
        runContext: this.resolveRunContext(options),
        startedAt: Date.now(),
      };
      try {
        const workflow = this.workflowFor(this.router.resolve(command));
        outcome = CommandExecutor.normalizeInvokedOutcome(
          command, await workflow.run(command, context));
      } catch (e) {
        const error: Error = e instanceof Error ? e : new Error(String(e));
        outcome = NoteOutcomeMapper.fromThrown(command, error);
      }
    }

    const violation: EnvelopeViolation | undefined = CommandExecutor.verifyOutcome(outcome);
    if (violation !== undefined) {
      return CommandExecutor.failedOutcome(command, violation.code, violation.message, violation.retryable);
    }

    if (outcome.kind === 'committed') {
      await CommandExecutor.emitRunEvent(options, command.operationId, RUN_EVENT_COMMIT_COMMITTED,
        commitCommittedPayload(outcome));
    }
    await CommandExecutor.emitRunEvent(
      options, command.operationId, DISPATCH_EVENT_TERMINAL, dispatchTerminalPayload(outcome));
    await CommandExecutor.settleRun(options, command.operationId, outcome);
    return outcome;
  }
}
