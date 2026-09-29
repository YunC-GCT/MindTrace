/**
 * NoteDetailRenderBenchmarkHost.ets — #189 根级冷开/重复打开设备实验宿主
 *
 * 路径: entry/src/main/ets/benchmark/NoteDetailRenderBenchmarkHost.ets
 * 职责: 在同一应用根生命周期中关闭并重新挂载真实 NoteDetail 基准 surface。
 * 依赖: NoteDetailRenderBenchmarkHarness, NoteDetailBenchmarkLaunch.
 *
 * 数据流:
 *   root launch config -> cold harness -> close gap -> warm harness -> hilog snapshots
 *
 * 设计约束:
 *   - WebKeepAlive 只能由 Index root 挂载，本宿主不得拥有保活 Web。
 *   - 每轮留出 4 秒渲染窗口和 1 秒关闭窗口，便于采集稳定与 render-exit 证据。
 */

import { NoteDetailRenderBenchmarkHarness } from './NoteDetailRenderBenchmarkHarness'
import { NoteDetailBenchmarkLaunchConfig } from '../services/NoteDetailBenchmarkLaunch'
import { NoteDetailCacheTag, NoteDetailColdWarmTag } from '../services/NoteDetailRenderMetrics'

const BENCHMARK_OPEN_WINDOW_MS: number = 4000
const BENCHMARK_CLOSED_WINDOW_MS: number = 1000

@Component
export struct NoteDetailRenderBenchmarkHost {
  @Prop config: NoteDetailBenchmarkLaunchConfig = NoteDetailBenchmarkLaunchConfig.disabled()
  @State overlayVisible: boolean = true
  @State completed: boolean = false
  @State currentRunIndex: number = 0
  @State coldWarmTag: NoteDetailColdWarmTag = 'cold'
  @State cacheTag: NoteDetailCacheTag = 'cold'
  private timerId: number = -1

  aboutToAppear(): void {
    this.scheduleClose()
  }

  aboutToDisappear(): void {
    this.cancelTimer()
  }

  private scheduleClose: () => void = (): void => {
    this.cancelTimer()
    this.timerId = setTimeout((): void => {
      this.overlayVisible = false
      if (this.currentRunIndex === 0) {
        this.timerId = setTimeout((): void => {
          this.currentRunIndex = 1
          this.coldWarmTag = 'warm'
          this.cacheTag = 'mixed'
          this.overlayVisible = true
          this.scheduleClose()
        }, BENCHMARK_CLOSED_WINDOW_MS)
      } else {
        this.completed = true
        this.timerId = -1
      }
    }, BENCHMARK_OPEN_WINDOW_MS)
  }

  private cancelTimer: () => void = (): void => {
    if (this.timerId >= 0) {
      clearTimeout(this.timerId)
      this.timerId = -1
    }
  }

  build() {
    Stack() {
      if (this.overlayVisible) {
        NoteDetailRenderBenchmarkHarness({
          fixtureId: this.config.fixtureId,
          rendererFamily: this.config.rendererFamily,
          lengthProfile: this.config.lengthProfile,
          runIndex: this.currentRunIndex,
          coldWarmTag: this.coldWarmTag,
          aiHelperVisible: this.config.aiHelperVisible,
          webKeepAliveEnabled: this.config.webKeepAliveEnabled,
          cacheTag: this.cacheTag,
        })
      } else {
        Column({ space: 8 }) {
          Text(this.completed ? 'Benchmark complete' : 'Preparing warm reopen')
            .fontSize(16)
            .fontColor('#FFFFFFFF')
          Text('Results: hilog tag NoteDetailBench')
            .fontSize(12)
            .fontColor('#99FFFFFF')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#FF101218')
      }
    }
    .width('100%')
    .height('100%')
  }
}
