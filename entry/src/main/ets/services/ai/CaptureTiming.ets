/**
 * CaptureTiming.ets — 采集成败耗时日志（从 AiService 抽出）
 *
 * 路径: entry/src/main/ets/services/ai/CaptureTiming.ets
 * 职责: capture / captureSet 的序号分配与耗时汇总日志（纯格式化，不碰调度与数据库）。
 * 依赖: common Logger。
 *
 * 拆出原因（2026-10-31）：AiService 已 1150 行，序号/日志格式化属于旁路能力，
 * 与「调度编排」无关；先搬出这类无状态逻辑，作为 AiService 分片重构的第一片。
 */
import { Logger } from 'common';

export class CaptureTiming {
  private static seq: number = 0;
  private static readonly timingLog: Logger = new Logger('AICapture');

  /** 每次 capture / captureSet 进入时分配一个自增序号，供日志关联。 */
  static nextSeq(): number {
    CaptureTiming.seq += 1;
    return CaptureTiming.seq;
  }

  static logCapture(
    seq: number,
    outcome: string,
    resolveMs: number,
    nodeTotals: Map<string, number>,
    nodeVisits: Map<string, number>,
    totalMs: number,
  ): void {
    CaptureTiming.timingLog.info(CaptureTiming.formatCapture(seq, outcome, resolveMs, nodeTotals, nodeVisits, totalMs));
  }

  static logCaptureSet(
    seq: number,
    total: number,
    done: number,
    failed: number,
    cancelled: number,
    totalMs: number,
  ): void {
    CaptureTiming.timingLog.info('CAPTURE_SET_TIMING seq=' + seq.toString()
      + ' total=' + total.toString() + ' done=' + done.toString()
      + ' failed=' + failed.toString() + ' cancelled=' + cancelled.toString()
      + ' totalMs=' + totalMs.toString());
  }

  private static formatCapture(
    seq: number,
    outcome: string,
    resolveMs: number,
    nodeTotals: Map<string, number>,
    nodeVisits: Map<string, number>,
    totalMs: number,
  ): string {
    const ocrMs: number = nodeTotals.get('capture') ?? 0;
    const classifyMs: number = nodeTotals.get('classify') ?? 0;
    const draftMs: number = nodeTotals.get('structure') ?? 0;
    const truthCheckMs: number = nodeTotals.get('truth_check') ?? 0;
    const persistMs: number = nodeTotals.get('persist') ?? 0;
    const accountedMs: number = resolveMs + ocrMs + classifyMs + draftMs + truthCheckMs + persistMs;
    const otherMs: number = Math.max(0, totalMs - accountedMs);
    return 'CAPTURE_TIMING seq=' + seq.toString()
      + ' outcome=' + outcome
      + ' resolveMs=' + resolveMs.toString()
      + ' ocrMs=' + ocrMs.toString()
      + ' classifyMs=' + classifyMs.toString()
      + ' draftMs=' + draftMs.toString()
      + ' truthCheckMs=' + truthCheckMs.toString()
      + ' persistMs=' + persistMs.toString()
      + ' otherMs=' + otherMs.toString()
      + ' totalMs=' + totalMs.toString()
      + ' visits=capture:' + (nodeVisits.get('capture') ?? 0).toString()
      + ',classify:' + (nodeVisits.get('classify') ?? 0).toString()
      + ',structure:' + (nodeVisits.get('structure') ?? 0).toString()
      + ',truth_check:' + (nodeVisits.get('truth_check') ?? 0).toString()
      + ',persist:' + (nodeVisits.get('persist') ?? 0).toString();
  }
}
