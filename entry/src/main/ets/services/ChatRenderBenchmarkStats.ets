/**
 * ChatRenderBenchmarkStats.ets — chat 渲染基准测量 seam(恒开计数器 + 门控样本缓冲)
 *
 * 路径: entry/src/main/ets/services/ChatRenderBenchmarkStats.ets
 * 职责: 为 #124 基准提供进程内计数: Web 创建、高度更新、缓存命中/未命中、渲染降级。
 *       计数器恒开(纯整数自增,零分配),不改变任何渲染决策;样本快照为 enable 基线差值;
 *       结构化 hilog dump 仅在 enable 期间输出,默认关闭。
 * 依赖: @kit.PerformanceAnalysisKit(hilog)
 *
 * 数据流:
 *   MathTextRenderer 埋点 → recordXxx() → snapshot()/dumpSnapshotHilog() → harness 报告
 *
 * 设计要点:
 *   - 计数语义冻结: recordXxx N 次调用 → snapshot 计数恰为 N(基线为 0 时)。
 *   - recordHeightUpdate 覆盖所有 webHeight 赋值(含估算);recordHeightApplied 仅覆盖真实
 *     高度回传应用(Web 回调/缓存高度),并在 enable 期间缓冲 run 内首次/最后时间戳
 *     (harness 用其计算 T_firstDeltaToVisible/finish→visible/T_finishToStable)。
 *   - recordWebWorkStart + recordHeightApplied 形成每个 Web 工作单元 create→first-height-applied
 *     样本;该样本才可用于预算推导,避免用 run 级 proxy 代替 per-unit 分布。
 *   - enableForRun(fixtureId, runIndex) 将当前累计值记为基线;snapshot 返回基线差值。
 *   - disable() 把样本冻结为 disable 时刻的差值(缓冲停止、样本保留);再次 enable 恢复实时差值。
 *   - 计数器恒开;hilog dump 仅 enable 期间输出,默认关闭;resetCountersForTest() 仅供测试。
 *   - 结构化 hilog: [ChatRenderBench] fixture=<id> run=<n> metric=<name> value=<number>
 *
 * ArkTS 1.1 strict 适配:
 *   - static 方法内不用 this,一律用类名;无 any/unknown。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const LOG_TAG: string = 'ChatRenderBench';

export interface BenchmarkStatsSnapshot {
  webCreateCount: number;
  heightUpdateCount: number;
  heightAppliedCount: number;
  cacheHitCount: number;
  cacheMissCount: number;
  degradationCount: number;
  webWorkStartCount: number;
  webWorkDurationSamplesMs: number[];
  // run 内门控时间戳缓冲(enable 期间才记录;-1 = 未观测到);只由真实高度回传应用驱动
  firstHeightAppliedTs: number;
  lastHeightAppliedTs: number;
  fixtureId: string;
  runIndex: number;
}

// 恒开累计计数器(单调递增,仅 resetCountersForTest 清零)
let webCreateTotal: number = 0;
let heightUpdateTotal: number = 0;
let heightAppliedTotal: number = 0;
let cacheHitTotal: number = 0;
let cacheMissTotal: number = 0;
let degradationTotal: number = 0;
let webWorkStartTotal: number = 0;

// enable 时捕获的基线 + 标签
let baselineWebCreate: number = 0;
let baselineHeightUpdate: number = 0;
let baselineHeightApplied: number = 0;
let baselineCacheHit: number = 0;
let baselineCacheMiss: number = 0;
let baselineDegradation: number = 0;
let baselineWebWorkStart: number = 0;
let enabled: boolean = false;
let activeFixtureId: string = '';
let activeRunIndex: number = -1;
// run 内首次/最后真实高度回传应用时间戳(门控缓冲,enableForRun 时清空)
let firstHeightAppliedTs: number = -1;
let lastHeightAppliedTs: number = -1;
// disable 时冻结的最后一次样本(缓冲停止,样本保留)
let frozenSnapshot: BenchmarkStatsSnapshot | null = null;
let pendingWebWorkStartTs: number[] = [];
let webWorkDurationSamplesMs: number[] = [];

export class ChatRenderBenchmarkStats {
  public static recordWebCreate(): void {
    webCreateTotal += 1;
  }

  public static recordWebWorkStart(): void {
    webWorkStartTotal += 1;
    if (enabled) {
      pendingWebWorkStartTs.push(Date.now());
    }
  }

  // 所有 webHeight 赋值点(含估算)统一计数;纯整数自增,不记录时间戳
  public static recordHeightUpdate(): void {
    heightUpdateTotal += 1;
  }

  // 真实高度回传应用(Web 回调/缓存高度): 计数 + enable 期间缓冲首次/最后时间戳
  public static recordHeightApplied(): void {
    heightAppliedTotal += 1;
    if (enabled) {
      const now: number = Date.now();
      if (firstHeightAppliedTs < 0) {
        firstHeightAppliedTs = now;
      }
      lastHeightAppliedTs = now;
      if (pendingWebWorkStartTs.length > 0) {
        const startedAt: number = pendingWebWorkStartTs.shift() ?? now;
        webWorkDurationSamplesMs.push(Math.max(0, now - startedAt));
      }
    }
  }

  public static recordCacheHit(): void {
    cacheHitTotal += 1;
  }

  public static recordCacheMiss(): void {
    cacheMissTotal += 1;
  }

  public static recordDegradation(): void {
    degradationTotal += 1;
  }

  // 开始一次运行: 当前累计值记为基线,快照即返回本次运行的增量
  public static enableForRun(fixtureId: string, runIndex: number): void {
    baselineWebCreate = webCreateTotal;
    baselineHeightUpdate = heightUpdateTotal;
    baselineHeightApplied = heightAppliedTotal;
    baselineCacheHit = cacheHitTotal;
    baselineCacheMiss = cacheMissTotal;
    baselineDegradation = degradationTotal;
    baselineWebWorkStart = webWorkStartTotal;
    activeFixtureId = fixtureId;
    activeRunIndex = runIndex;
    firstHeightAppliedTs = -1;
    lastHeightAppliedTs = -1;
    pendingWebWorkStartTs = [];
    webWorkDurationSamplesMs = [];
    frozenSnapshot = null;
    enabled = true;
  }

  // 停止本次运行: 缓冲冻结为 disable 时刻的样本(计数器保留,继续累计)
  public static disable(): void {
    if (enabled) {
      frozenSnapshot = ChatRenderBenchmarkStats.liveSnapshot();
    }
    enabled = false;
  }

  // 读取当前快照: 各计数 = 累计值 - enable 基线;从未 enable 时基线为 0(累计值)。
  // disable 后返回冻结样本;再次 enable 后恢复实时差值。
  public static snapshot(): BenchmarkStatsSnapshot {
    if (!enabled && frozenSnapshot !== null) {
      const frozen: BenchmarkStatsSnapshot = frozenSnapshot;
      return {
        webCreateCount: frozen.webCreateCount,
        heightUpdateCount: frozen.heightUpdateCount,
        heightAppliedCount: frozen.heightAppliedCount,
        cacheHitCount: frozen.cacheHitCount,
        cacheMissCount: frozen.cacheMissCount,
        degradationCount: frozen.degradationCount,
        webWorkStartCount: frozen.webWorkStartCount,
        webWorkDurationSamplesMs: frozen.webWorkDurationSamplesMs.slice(),
        firstHeightAppliedTs: frozen.firstHeightAppliedTs,
        lastHeightAppliedTs: frozen.lastHeightAppliedTs,
        fixtureId: frozen.fixtureId,
        runIndex: frozen.runIndex,
      };
    }
    return ChatRenderBenchmarkStats.liveSnapshot();
  }

  // 结构化 hilog dump;仅在 enable 期间输出,默认关闭(生产零噪音)
  public static dumpSnapshotHilog(): void {
    if (!enabled) {
      return;
    }
    const snapshot: BenchmarkStatsSnapshot = ChatRenderBenchmarkStats.snapshot();
    ChatRenderBenchmarkStats.logMetric(snapshot, 'webCreateCount', snapshot.webCreateCount);
    ChatRenderBenchmarkStats.logMetric(snapshot, 'heightUpdateCount', snapshot.heightUpdateCount);
    ChatRenderBenchmarkStats.logMetric(snapshot, 'heightAppliedCount', snapshot.heightAppliedCount);
    ChatRenderBenchmarkStats.logMetric(snapshot, 'webWorkStartCount', snapshot.webWorkStartCount);
    ChatRenderBenchmarkStats.logMetric(snapshot, 'webWorkDurationSampleCount', snapshot.webWorkDurationSamplesMs.length);
    ChatRenderBenchmarkStats.logMetric(snapshot, 'cacheHitCount', snapshot.cacheHitCount);
    ChatRenderBenchmarkStats.logMetric(snapshot, 'cacheMissCount', snapshot.cacheMissCount);
    ChatRenderBenchmarkStats.logMetric(snapshot, 'degradationCount', snapshot.degradationCount);
    ChatRenderBenchmarkStats.logMetric(snapshot, 'firstHeightAppliedTs', snapshot.firstHeightAppliedTs);
    ChatRenderBenchmarkStats.logMetric(snapshot, 'lastHeightAppliedTs', snapshot.lastHeightAppliedTs);
  }

  // 测试缝: 清零全部计数与基线,关闭 enable
  public static resetCountersForTest(): void {
    webCreateTotal = 0;
    heightUpdateTotal = 0;
    heightAppliedTotal = 0;
    cacheHitTotal = 0;
    cacheMissTotal = 0;
    degradationTotal = 0;
    webWorkStartTotal = 0;
    baselineWebCreate = 0;
    baselineHeightUpdate = 0;
    baselineHeightApplied = 0;
    baselineCacheHit = 0;
    baselineCacheMiss = 0;
    baselineDegradation = 0;
    baselineWebWorkStart = 0;
    enabled = false;
    activeFixtureId = '';
    activeRunIndex = -1;
    firstHeightAppliedTs = -1;
    lastHeightAppliedTs = -1;
    pendingWebWorkStartTs = [];
    webWorkDurationSamplesMs = [];
    frozenSnapshot = null;
  }

  private static liveSnapshot(): BenchmarkStatsSnapshot {
    return {
      webCreateCount: webCreateTotal - baselineWebCreate,
      heightUpdateCount: heightUpdateTotal - baselineHeightUpdate,
      heightAppliedCount: heightAppliedTotal - baselineHeightApplied,
      cacheHitCount: cacheHitTotal - baselineCacheHit,
      cacheMissCount: cacheMissTotal - baselineCacheMiss,
      degradationCount: degradationTotal - baselineDegradation,
      webWorkStartCount: webWorkStartTotal - baselineWebWorkStart,
      webWorkDurationSamplesMs: webWorkDurationSamplesMs.slice(),
      firstHeightAppliedTs: firstHeightAppliedTs,
      lastHeightAppliedTs: lastHeightAppliedTs,
      fixtureId: activeFixtureId,
      runIndex: activeRunIndex,
    };
  }

  private static logMetric(snapshot: BenchmarkStatsSnapshot, metricName: string, value: number): void {
    const line: string = '[ChatRenderBench] fixture=' + snapshot.fixtureId
      + ' run=' + snapshot.runIndex.toString()
      + ' metric=' + metricName
      + ' value=' + value.toString();
    hilog.info(DOMAIN, LOG_TAG, '%{public}s', line);
  }
}
