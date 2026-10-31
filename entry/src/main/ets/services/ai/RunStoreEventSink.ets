/**
 * RunStoreEventSink.ets — RunEventSink 的 entry 实现（落 run_store / run_event）
 *
 * 路径: entry/src/main/ets/services/ai/RunStoreEventSink.ets
 * 职责: 把 Dispatcher 命令 seam 的 start/terminal 事件写进 RunStorePort（run_store / run_event）。
 *       首次事件自动建 run 记录；写出尽力而为，失败只记日志（可观测性不打挂业务）。
 * 依赖: common RunStorePort / RunRecord；agents RunEventSink 契约。
 */
import { Logger, RunRecord } from 'common';
import type { RunEventSink, DispatchRunEvent } from 'agents';
import type { RunStorePort } from 'common';

const log: Logger = new Logger('RunStoreEventSink');

export class RunStoreEventSink implements RunEventSink {
  private readonly port: RunStorePort;

  constructor(port: RunStorePort) {
    this.port = port;
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
