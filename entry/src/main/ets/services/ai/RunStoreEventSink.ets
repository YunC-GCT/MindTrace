/**
 * RunStoreEventSink.ets — RunEventSink 的 entry 实现（落 run_store / run_event）
 *
 * 路径: entry/src/main/ets/services/ai/RunStoreEventSink.ets
 * 职责: 把 Dispatcher 命令 seam 的 start/terminal 事件写进 RunStorePort（run_store / run_event）。
 *       首次事件自动建 run 记录；写出尽力而为，失败只记日志（可观测性不打挂业务）。
 * 依赖: common RunStorePort / RunRecord；agents RunEventSink 契约。
 */
import { Logger, RunRecord } from 'common';
import type { RunStatus } from 'common';
import type { NoteOutcome } from 'common';
import type { RunEventSink, DispatchRunEvent } from 'agents';
import type { RunStorePort } from 'common';

const log: Logger = new Logger('RunStoreEventSink');

export class RunStoreEventSink implements RunEventSink {
  private readonly port: RunStorePort;

  constructor(port: RunStorePort) {
    this.port = port;
  }

  /** A4 4b-2b：终态回写 run 记录（status / committed 事实）。写失败只记日志。 */
  async settle(runId: string, outcome: NoteOutcome): Promise<void> {
    try {
      const existing: RunRecord | null = await this.port.get(runId);
      if (existing === null) {
        return;
      }
      const updated: RunRecord = {
        runId: existing.runId,
        parentRunId: existing.parentRunId,
        status: RunStoreEventSink.statusOf(outcome),
        checkpointId: existing.checkpointId,
        committedNoteId: outcome.kind === 'committed' ? outcome.noteId : existing.committedNoteId,
        committedVersion: outcome.kind === 'committed' ? outcome.version : existing.committedVersion,
        updatedAt: Date.now(),
      };
      await this.port.update(updated);
    } catch (e) {
      log.warn('run settle failed runId=' + runId + ' err=' + (e instanceof Error ? e.message : String(e)));
    }
  }

  // RunStatus 尚无 'committed'：committed 事实由 committedNoteId/Version 承载，status 保持 running（记在 tasks.md 4b-2b 遗留）。
  private static statusOf(outcome: NoteOutcome): RunStatus {
    if (outcome.kind === 'failed') { return 'failed'; }
    if (outcome.kind === 'cancelled') { return 'cancelled'; }
    if (outcome.kind === 'readyPreview' || outcome.kind === 'needsInput') { return 'readyPreview'; }
    return 'running';
  }

  async emit(runId: string, event: DispatchRunEvent): Promise<void> {
    try {
      const existing: RunRecord | null = await this.port.get(runId);
      if (existing === null) {
        const record: RunRecord = {
          runId: runId,
          status: 'running',
          updatedAt: Date.now(),
        };
        await this.port.create(record);
      }
      await this.port.appendEvent(runId, event.kind, event.payloadJson);
    } catch (e) {
      log.warn('run event write failed runId=' + runId + ' kind=' + event.kind
        + ' err=' + (e instanceof Error ? e.message : String(e)));
    }
  }
}
