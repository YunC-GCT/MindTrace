/**
 * NoteDetailRenderMetrics.ets — NoteDetail surface 专属性能观测适配器
 *
 * 路径: entry/src/main/ets/services/NoteDetailRenderMetrics.ets
 * 职责: 门控采集打开到首屏/公式/稳定时间、Web 工作、高度变化、长帧、render-exit、
 *       稳态内存与只读子树生命周期；默认关闭，不参与渲染决策。
 * 依赖: @kit.PerformanceAnalysisKit(hilog)
 *
 * 数据流:
 *   NoteDetailOverlay/MathTextRenderer/harness → recordXxx() → snapshot()/dumpSnapshotHilog()
 *
 * 设计要点:
 *   - surface 固定为 noteDetail，不导入 chat message、Document 或持久化模型。
 *   - stable 仅在最近一次计划工作/高度变化后静默满 500ms 时成立。
 *   - 长帧只接纳 open 后 500ms 窗口内的帧，阈值严格为 >32ms。
 *   - enableForRun 捕获一次 run 标签；disable 后冻结快照，便于异步写证据。
 *
 * ArkTS 1.1 strict 适配:
 *   - 使用显式接口和字段；static 方法内不用 this；无 any/unknown/索引签名。
 */

import { hilog } from '@kit.PerformanceAnalysisKit'

export type NoteDetailMetricSurface = 'none' | 'noteDetail'
export type NoteDetailColdWarmTag = 'cold' | 'warm'
export type NoteDetailCacheTag = 'cold' | 'hit' | 'mixed'

export const NOTE_DETAIL_METRIC_SURFACE: string = 'noteDetail'
export const NOTE_DETAIL_LONG_FRAME_MS: number = 32
export const NOTE_DETAIL_STABILITY_QUIET_MS: number = 500

const DOMAIN: number = 0x0000
const LOG_TAG: string = 'NoteDetailBench'

export interface NoteDetailBenchmarkRunConfig {
  fixtureId: string
  runIndex: number
  coldWarmTag: NoteDetailColdWarmTag
  noteType: string
  lengthProfile: string
  aiHelperVisible: boolean
  cacheTag: NoteDetailCacheTag
}

export interface NoteDetailRenderMetricsSnapshot {
  surface: string
  fixtureId: string
  runIndex: number
  coldWarmTag: NoteDetailColdWarmTag
  noteType: string
  lengthProfile: string
  aiHelperVisible: boolean
  cacheTag: NoteDetailCacheTag
  openStartedAt: number
  firstVisibleTs: number
  firstFormulaVisibleTs: number
  stableTs: number
  openToFirstVisibleMs: number
  formulaVisibleMs: number
  openToStableMs: number
  webCreateCount: number
  webCreatesPerFrame: number[]
  maxWebCreatesPerFrame: number
  webWorkStartCount: number
  webWorkDurationSamplesMs: number[]
  heightUpdateCount: number
  heightAppliedCount: number
  cacheHitCount: number
  cacheMissCount: number
  degradationCount: number
  longFrameCount: number
  consecutiveLongFramePairCount: number
  hasConsecutiveLongFrames: boolean
  frameDurationsMs: number[]
  renderExitCount: number
  renderExitReasons: number[]
  heapUsedKb: number
  totalHeapKb: number
  headerMountCount: number
  headerUnmountCount: number
  bodyMountCount: number
  bodyUnmountCount: number
  bodyInputChangeCount: number
  editStateCount: number
  deleteConfirmCount: number
  draftStateCount: number
  discardConfirmCount: number
  lastViewportHeight: number
  lastHeightChangeTs: number
}

let enabled: boolean = false
let activeConfig: NoteDetailBenchmarkRunConfig | null = null
let openStartedAt: number = -1
let firstVisibleTs: number = -1
let firstFormulaVisibleTs: number = -1
let stableTs: number = -1
let lastScheduledWorkTs: number = -1
let lastHeightChangeTs: number = -1
let lastViewportHeight: number = -1
let webCreateCount: number = 0
let pendingWebCreateTs: number[] = []
let webCreatesPerFrame: number[] = []
let maxWebCreatesPerFrame: number = 0
let lastFrameObservedAt: number = -1
let webWorkStartCount: number = 0
let webWorkDurationSamplesMs: number[] = []
let pendingWebWorkStartTs: number[] = []
let heightUpdateCount: number = 0
let heightAppliedCount: number = 0
let cacheHitCount: number = 0
let cacheMissCount: number = 0
let degradationCount: number = 0
let longFrameCount: number = 0
let consecutiveLongFramePairCount: number = 0
let previousFrameWasLong: boolean = false
let frameDurationsMs: number[] = []
let renderExitCount: number = 0
let renderExitReasons: number[] = []
let heapUsedKb: number = -1
let totalHeapKb: number = -1
let headerMountCount: number = 0
let headerUnmountCount: number = 0
let bodyMountCount: number = 0
let bodyUnmountCount: number = 0
let bodyInputChangeCount: number = 0
let editStateCount: number = 0
let deleteConfirmCount: number = 0
let draftStateCount: number = 0
let discardConfirmCount: number = 0
let frozenSnapshot: NoteDetailRenderMetricsSnapshot | null = null

function emptyConfig(): NoteDetailBenchmarkRunConfig {
  return {
    fixtureId: '',
    runIndex: -1,
    coldWarmTag: 'cold',
    noteType: '',
    lengthProfile: '',
    aiHelperVisible: false,
    cacheTag: 'cold',
  }
}

function resetRunValues(startedAt: number): void {
  openStartedAt = startedAt
  firstVisibleTs = -1
  firstFormulaVisibleTs = -1
  stableTs = -1
  lastScheduledWorkTs = startedAt
  lastHeightChangeTs = startedAt
  lastViewportHeight = -1
  webCreateCount = 0
  pendingWebCreateTs = []
  webCreatesPerFrame = []
  maxWebCreatesPerFrame = 0
  lastFrameObservedAt = startedAt
  webWorkStartCount = 0
  webWorkDurationSamplesMs = []
  pendingWebWorkStartTs = []
  heightUpdateCount = 0
  heightAppliedCount = 0
  cacheHitCount = 0
  cacheMissCount = 0
  degradationCount = 0
  longFrameCount = 0
  consecutiveLongFramePairCount = 0
  previousFrameWasLong = false
  frameDurationsMs = []
  renderExitCount = 0
  renderExitReasons = []
  heapUsedKb = -1
  totalHeapKb = -1
  headerMountCount = 0
  headerUnmountCount = 0
  bodyMountCount = 0
  bodyUnmountCount = 0
  bodyInputChangeCount = 0
  editStateCount = 0
  deleteConfirmCount = 0
  draftStateCount = 0
  discardConfirmCount = 0
  frozenSnapshot = null
}

function elapsedOrMissing(timestamp: number): number {
  return timestamp >= 0 && openStartedAt >= 0 ? timestamp - openStartedAt : -1
}

function copySnapshot(snapshot: NoteDetailRenderMetricsSnapshot): NoteDetailRenderMetricsSnapshot {
  return {
    surface: snapshot.surface,
    fixtureId: snapshot.fixtureId,
    runIndex: snapshot.runIndex,
    coldWarmTag: snapshot.coldWarmTag,
    noteType: snapshot.noteType,
    lengthProfile: snapshot.lengthProfile,
    aiHelperVisible: snapshot.aiHelperVisible,
    cacheTag: snapshot.cacheTag,
    openStartedAt: snapshot.openStartedAt,
    firstVisibleTs: snapshot.firstVisibleTs,
    firstFormulaVisibleTs: snapshot.firstFormulaVisibleTs,
    stableTs: snapshot.stableTs,
    openToFirstVisibleMs: snapshot.openToFirstVisibleMs,
    formulaVisibleMs: snapshot.formulaVisibleMs,
    openToStableMs: snapshot.openToStableMs,
    webCreateCount: snapshot.webCreateCount,
    webCreatesPerFrame: snapshot.webCreatesPerFrame.slice(),
    maxWebCreatesPerFrame: snapshot.maxWebCreatesPerFrame,
    webWorkStartCount: snapshot.webWorkStartCount,
    webWorkDurationSamplesMs: snapshot.webWorkDurationSamplesMs.slice(),
    heightUpdateCount: snapshot.heightUpdateCount,
    heightAppliedCount: snapshot.heightAppliedCount,
    cacheHitCount: snapshot.cacheHitCount,
    cacheMissCount: snapshot.cacheMissCount,
    degradationCount: snapshot.degradationCount,
    longFrameCount: snapshot.longFrameCount,
    consecutiveLongFramePairCount: snapshot.consecutiveLongFramePairCount,
    hasConsecutiveLongFrames: snapshot.hasConsecutiveLongFrames,
    frameDurationsMs: snapshot.frameDurationsMs.slice(),
    renderExitCount: snapshot.renderExitCount,
    renderExitReasons: snapshot.renderExitReasons.slice(),
    heapUsedKb: snapshot.heapUsedKb,
    totalHeapKb: snapshot.totalHeapKb,
    headerMountCount: snapshot.headerMountCount,
    headerUnmountCount: snapshot.headerUnmountCount,
    bodyMountCount: snapshot.bodyMountCount,
    bodyUnmountCount: snapshot.bodyUnmountCount,
    bodyInputChangeCount: snapshot.bodyInputChangeCount,
    editStateCount: snapshot.editStateCount,
    deleteConfirmCount: snapshot.deleteConfirmCount,
    draftStateCount: snapshot.draftStateCount,
    discardConfirmCount: snapshot.discardConfirmCount,
    lastViewportHeight: snapshot.lastViewportHeight,
    lastHeightChangeTs: snapshot.lastHeightChangeTs,
  }
}

export class NoteDetailRenderMetrics {
  public static enableForRun(config: NoteDetailBenchmarkRunConfig, startedAt: number = Date.now()): void {
    activeConfig = config
    resetRunValues(startedAt)
    enabled = true
  }

  public static isEnabled(): boolean {
    return enabled
  }

  public static disable(): void {
    if (enabled) {
      frozenSnapshot = NoteDetailRenderMetrics.liveSnapshot()
    }
    enabled = false
  }

  public static recordWebCreate(timestamp: number = Date.now()): void {
    if (!enabled) { return }
    webCreateCount += 1
    pendingWebCreateTs.push(timestamp)
    lastScheduledWorkTs = timestamp
  }

  public static recordWebWorkStart(timestamp: number = Date.now()): void {
    if (!enabled) { return }
    webWorkStartCount += 1
    pendingWebWorkStartTs.push(timestamp)
    lastScheduledWorkTs = timestamp
  }

  public static recordHeightUpdate(timestamp: number = Date.now()): void {
    if (!enabled) { return }
    heightUpdateCount += 1
    lastScheduledWorkTs = timestamp
    lastHeightChangeTs = timestamp
    stableTs = -1
  }

  public static recordHeightApplied(timestamp: number = Date.now()): void {
    if (!enabled) { return }
    heightAppliedCount += 1
    lastScheduledWorkTs = timestamp
    lastHeightChangeTs = timestamp
    stableTs = -1
    if (firstFormulaVisibleTs < 0) {
      firstFormulaVisibleTs = timestamp
    }
    if (pendingWebWorkStartTs.length > 0) {
      const fallbackStart: number = timestamp
      const startedAt: number = pendingWebWorkStartTs.shift() ?? fallbackStart
      webWorkDurationSamplesMs.push(Math.max(0, timestamp - startedAt))
    }
  }

  public static recordCacheHit(): void {
    if (enabled) { cacheHitCount += 1 }
  }

  public static recordCacheMiss(): void {
    if (enabled) { cacheMissCount += 1 }
  }

  public static recordDegradation(): void {
    if (enabled) { degradationCount += 1 }
  }

  public static recordViewportHeight(height: number, timestamp: number = Date.now()): void {
    if (!enabled || height <= 0) { return }
    if (firstVisibleTs < 0) {
      firstVisibleTs = timestamp
    }
    if (lastViewportHeight < 0 || Math.abs(lastViewportHeight - height) > 0.1) {
      lastViewportHeight = height
      lastHeightChangeTs = timestamp
      lastScheduledWorkTs = timestamp
      stableTs = -1
    }
  }

  public static markStable(timestamp: number = Date.now()): boolean {
    if (!enabled) { return false }
    const lastActivity: number = Math.max(lastScheduledWorkTs, lastHeightChangeTs)
    if (lastActivity < 0 || timestamp - lastActivity < NOTE_DETAIL_STABILITY_QUIET_MS) {
      return false
    }
    stableTs = timestamp
    return true
  }

  public static recordFrameDuration(durationMs: number, observedAt: number = Date.now()): void {
    if (!enabled || durationMs < 0 || openStartedAt < 0
      || observedAt - openStartedAt > NOTE_DETAIL_STABILITY_QUIET_MS) {
      return
    }
    let createsThisFrame: number = 0
    const remainingCreateTs: number[] = []
    for (const createdAt of pendingWebCreateTs) {
      if (createdAt <= observedAt) {
        if (createdAt > lastFrameObservedAt) {
          createsThisFrame += 1
        }
      } else {
        remainingCreateTs.push(createdAt)
      }
    }
    pendingWebCreateTs = remainingCreateTs
    lastFrameObservedAt = observedAt
    webCreatesPerFrame.push(createsThisFrame)
    maxWebCreatesPerFrame = Math.max(maxWebCreatesPerFrame, createsThisFrame)
    frameDurationsMs.push(durationMs)
    const isLong: boolean = durationMs > NOTE_DETAIL_LONG_FRAME_MS
    if (isLong) {
      longFrameCount += 1
      if (previousFrameWasLong) {
        consecutiveLongFramePairCount += 1
      }
    }
    previousFrameWasLong = isLong
  }

  public static recordRenderExit(reason: number): void {
    if (!enabled) { return }
    renderExitCount += 1
    renderExitReasons.push(reason)
  }

  public static recordMemory(heapKb: number, totalKb: number): void {
    if (!enabled) { return }
    heapUsedKb = heapKb
    totalHeapKb = totalKb
  }

  public static recordHeaderMount(): void {
    if (enabled) { headerMountCount += 1 }
  }

  public static recordHeaderUnmount(): void {
    if (enabled) { headerUnmountCount += 1 }
  }

  public static recordBodyMount(): void {
    if (enabled) { bodyMountCount += 1 }
  }

  public static recordBodyUnmount(): void {
    if (enabled) { bodyUnmountCount += 1 }
  }

  public static recordBodyInputChange(): void {
    if (enabled) { bodyInputChangeCount += 1 }
  }

  public static recordEditState(): void {
    if (enabled) { editStateCount += 1 }
  }

  public static recordDeleteConfirm(): void {
    if (enabled) { deleteConfirmCount += 1 }
  }

  public static recordDraftState(): void {
    if (enabled) { draftStateCount += 1 }
  }

  public static recordDiscardConfirm(): void {
    if (enabled) { discardConfirmCount += 1 }
  }

  public static snapshot(): NoteDetailRenderMetricsSnapshot {
    if (!enabled && frozenSnapshot !== null) {
      return copySnapshot(frozenSnapshot)
    }
    return NoteDetailRenderMetrics.liveSnapshot()
  }

  public static dumpSnapshotHilog(): void {
    if (!enabled) { return }
    const snapshot: NoteDetailRenderMetricsSnapshot = NoteDetailRenderMetrics.snapshot()
    NoteDetailRenderMetrics.logMetric(snapshot, 'openToFirstVisibleMs', snapshot.openToFirstVisibleMs)
    NoteDetailRenderMetrics.logMetric(snapshot, 'formulaVisibleMs', snapshot.formulaVisibleMs)
    NoteDetailRenderMetrics.logMetric(snapshot, 'openToStableMs', snapshot.openToStableMs)
    NoteDetailRenderMetrics.logMetric(snapshot, 'webCreateCount', snapshot.webCreateCount)
    NoteDetailRenderMetrics.logMetric(snapshot, 'maxWebCreatesPerFrame', snapshot.maxWebCreatesPerFrame)
    NoteDetailRenderMetrics.logMetric(snapshot, 'webWorkStartCount', snapshot.webWorkStartCount)
    NoteDetailRenderMetrics.logMetric(snapshot, 'heightUpdateCount', snapshot.heightUpdateCount)
    NoteDetailRenderMetrics.logMetric(snapshot, 'heightAppliedCount', snapshot.heightAppliedCount)
    NoteDetailRenderMetrics.logMetric(snapshot, 'cacheHitCount', snapshot.cacheHitCount)
    NoteDetailRenderMetrics.logMetric(snapshot, 'cacheMissCount', snapshot.cacheMissCount)
    NoteDetailRenderMetrics.logMetric(snapshot, 'degradationCount', snapshot.degradationCount)
    NoteDetailRenderMetrics.logMetric(snapshot, 'longFrameCount', snapshot.longFrameCount)
    NoteDetailRenderMetrics.logMetric(snapshot, 'consecutiveLongFramePairCount',
      snapshot.consecutiveLongFramePairCount)
    NoteDetailRenderMetrics.logMetric(snapshot, 'renderExitCount', snapshot.renderExitCount)
    NoteDetailRenderMetrics.logMetric(snapshot, 'heapUsedKb', snapshot.heapUsedKb)
    NoteDetailRenderMetrics.logMetric(snapshot, 'totalHeapKb', snapshot.totalHeapKb)
    NoteDetailRenderMetrics.logMetric(snapshot, 'headerMountCount', snapshot.headerMountCount)
    NoteDetailRenderMetrics.logMetric(snapshot, 'headerUnmountCount', snapshot.headerUnmountCount)
    NoteDetailRenderMetrics.logMetric(snapshot, 'bodyMountCount', snapshot.bodyMountCount)
    NoteDetailRenderMetrics.logMetric(snapshot, 'bodyUnmountCount', snapshot.bodyUnmountCount)
    NoteDetailRenderMetrics.logMetric(snapshot, 'bodyInputChangeCount', snapshot.bodyInputChangeCount)
    NoteDetailRenderMetrics.logMetric(snapshot, 'editStateCount', snapshot.editStateCount)
    NoteDetailRenderMetrics.logMetric(snapshot, 'deleteConfirmCount', snapshot.deleteConfirmCount)
    NoteDetailRenderMetrics.logMetric(snapshot, 'draftStateCount', snapshot.draftStateCount)
    NoteDetailRenderMetrics.logMetric(snapshot, 'discardConfirmCount', snapshot.discardConfirmCount)
    let sampleIndex: number = 0
    while (sampleIndex < snapshot.webWorkDurationSamplesMs.length) {
      NoteDetailRenderMetrics.logIndexedMetric(snapshot, 'webWorkDurationMs', sampleIndex,
        snapshot.webWorkDurationSamplesMs[sampleIndex])
      sampleIndex += 1
    }
    sampleIndex = 0
    while (sampleIndex < snapshot.webCreatesPerFrame.length) {
      NoteDetailRenderMetrics.logIndexedMetric(snapshot, 'webCreatesPerFrame', sampleIndex,
        snapshot.webCreatesPerFrame[sampleIndex])
      sampleIndex += 1
    }
    sampleIndex = 0
    while (sampleIndex < snapshot.renderExitReasons.length) {
      NoteDetailRenderMetrics.logIndexedMetric(snapshot, 'renderExitReason', sampleIndex,
        snapshot.renderExitReasons[sampleIndex])
      sampleIndex += 1
    }
  }

  public static resetForTest(): void {
    enabled = false
    activeConfig = null
    resetRunValues(-1)
  }

  private static liveSnapshot(): NoteDetailRenderMetricsSnapshot {
    const config: NoteDetailBenchmarkRunConfig = activeConfig === null ? emptyConfig() : activeConfig
    return {
      surface: NOTE_DETAIL_METRIC_SURFACE,
      fixtureId: config.fixtureId,
      runIndex: config.runIndex,
      coldWarmTag: config.coldWarmTag,
      noteType: config.noteType,
      lengthProfile: config.lengthProfile,
      aiHelperVisible: config.aiHelperVisible,
      cacheTag: config.cacheTag,
      openStartedAt: openStartedAt,
      firstVisibleTs: firstVisibleTs,
      firstFormulaVisibleTs: firstFormulaVisibleTs,
      stableTs: stableTs,
      openToFirstVisibleMs: elapsedOrMissing(firstVisibleTs),
      formulaVisibleMs: elapsedOrMissing(firstFormulaVisibleTs),
      openToStableMs: elapsedOrMissing(stableTs),
      webCreateCount: webCreateCount,
      webCreatesPerFrame: webCreatesPerFrame.slice(),
      maxWebCreatesPerFrame: maxWebCreatesPerFrame,
      webWorkStartCount: webWorkStartCount,
      webWorkDurationSamplesMs: webWorkDurationSamplesMs.slice(),
      heightUpdateCount: heightUpdateCount,
      heightAppliedCount: heightAppliedCount,
      cacheHitCount: cacheHitCount,
      cacheMissCount: cacheMissCount,
      degradationCount: degradationCount,
      longFrameCount: longFrameCount,
      consecutiveLongFramePairCount: consecutiveLongFramePairCount,
      hasConsecutiveLongFrames: consecutiveLongFramePairCount > 0,
      frameDurationsMs: frameDurationsMs.slice(),
      renderExitCount: renderExitCount,
      renderExitReasons: renderExitReasons.slice(),
      heapUsedKb: heapUsedKb,
      totalHeapKb: totalHeapKb,
      headerMountCount: headerMountCount,
      headerUnmountCount: headerUnmountCount,
      bodyMountCount: bodyMountCount,
      bodyUnmountCount: bodyUnmountCount,
      bodyInputChangeCount: bodyInputChangeCount,
      editStateCount: editStateCount,
      deleteConfirmCount: deleteConfirmCount,
      draftStateCount: draftStateCount,
      discardConfirmCount: discardConfirmCount,
      lastViewportHeight: lastViewportHeight,
      lastHeightChangeTs: lastHeightChangeTs,
    }
  }

  private static logMetric(snapshot: NoteDetailRenderMetricsSnapshot,
    metricName: string, value: number): void {
    const line: string = NoteDetailRenderMetrics.logPrefix(snapshot)
      + ' metric=' + metricName + ' value=' + value.toString()
    hilog.info(DOMAIN, LOG_TAG, '%{public}s', line)
  }

  private static logIndexedMetric(snapshot: NoteDetailRenderMetricsSnapshot,
    metricName: string, sampleIndex: number, value: number): void {
    const line: string = NoteDetailRenderMetrics.logPrefix(snapshot)
      + ' metric=' + metricName + ' sample=' + sampleIndex.toString()
      + ' value=' + value.toString()
    hilog.info(DOMAIN, LOG_TAG, '%{public}s', line)
  }

  private static logPrefix(snapshot: NoteDetailRenderMetricsSnapshot): string {
    return '[NoteDetailBench] surface=' + snapshot.surface
      + ' fixture=' + snapshot.fixtureId
      + ' run=' + snapshot.runIndex.toString()
      + ' coldWarm=' + snapshot.coldWarmTag
      + ' noteType=' + snapshot.noteType
      + ' length=' + snapshot.lengthProfile
      + ' ai=' + (snapshot.aiHelperVisible ? '1' : '0')
      + ' cache=' + snapshot.cacheTag
  }
}
