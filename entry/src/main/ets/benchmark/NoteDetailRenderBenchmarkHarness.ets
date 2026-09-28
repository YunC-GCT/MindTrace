/**
 * NoteDetailRenderBenchmarkHarness.ets — #185 NoteDetail target-device measurement seam
 *
 * 路径: entry/src/main/ets/benchmark/NoteDetailRenderBenchmarkHarness.ets
 * 职责: 以确定性 fixture 挂载真实只读 NoteDetailOverlay，并采集单次运行数据。
 * 依赖: NoteDetailOverlay, AgentFloatWindow, NoteDetailRenderFixtures, NoteDetailRenderMetrics.
 *
 * 数据流:
 *   run props -> deterministic fixture -> real NoteDetailOverlay -> metrics snapshot/hilog
 *   device profiler -> exported frame/memory functions -> metrics snapshot
 *
 * Design notes:
 *   - This component is intentionally absent from main_pages.json and EntryAbility.
 *   - Frame duration and memory come from the target-device profiler; no synthetic values are used.
 *   - Metrics are enabled before the child overlay mounts and disabled when the harness unmounts.
 *   - A 100ms observer records the first 500ms quiet window without coupling it to overlay close time.
 *
 * ArkTS 1.1 strict:
 *   - Literal unions and benchmark objects have explicit types.
 *   - No any/unknown, dynamic property access, network, randomness, or LLM dependency.
 */

import { NoteDetailOverlay } from '../overlays/NoteDetailOverlay/NoteDetailOverlay'
import { AgentFloatWindow } from '../overlays/AgentFloatWindow/AgentFloatWindow'
import { ChatMsg } from '../overlays/AgentFloatWindow/chat/ChatModels'
import {
  NoteDetailBenchmarkFixture,
  NoteDetailFixtureId,
  NoteDetailRendererFamily,
  NoteDetailLengthProfile,
  createNoteDetailBenchmarkFixture,
} from '../services/NoteDetailRenderFixtures'
import {
  NoteDetailBenchmarkRunConfig,
  NoteDetailCacheTag,
  NoteDetailColdWarmTag,
  NoteDetailRenderMetrics,
  NoteDetailRenderMetricsSnapshot,
} from '../services/NoteDetailRenderMetrics'

const BENCHMARK_AI_HELPER_MESSAGES: ChatMsg[] = [{
  id: 185001,
  role: 'ai',
  content: '离线 AI 助手竞争负载\n\n$$\\int_0^1 x^2\\,dx=\\frac{1}{3}$$',
  ts: 1789956000000,
  streaming: false,
  reasoning: '',
  origin: 'chat',
  outcome: 'completed',
  runId: 'note-detail-benchmark-ai-helper',
  sequence: 1,
  messageKey: 'note-detail-benchmark-ai-helper:assistant',
}]

export function recordNoteDetailBenchmarkFrame(durationMs: number,
  observedAt: number = Date.now()): void {
  NoteDetailRenderMetrics.recordFrameDuration(durationMs, observedAt)
}

export function recordNoteDetailBenchmarkMemory(heapUsedKb: number, totalHeapKb: number): void {
  NoteDetailRenderMetrics.recordMemory(heapUsedKb, totalHeapKb)
}

export function snapshotNoteDetailBenchmark(): NoteDetailRenderMetricsSnapshot {
  return NoteDetailRenderMetrics.snapshot()
}

@Component
export struct NoteDetailRenderBenchmarkHarness {
  @Prop fixtureId: NoteDetailFixtureId = 'A'
  @Prop rendererFamily: NoteDetailRendererFamily = '概念'
  @Prop lengthProfile: NoteDetailLengthProfile = 'long'
  @Prop runIndex: number = 0
  @Prop coldWarmTag: NoteDetailColdWarmTag = 'cold'
  @Prop aiHelperVisible: boolean = false
  @Prop webKeepAliveEnabled: boolean = false
  @Prop cacheTag: NoteDetailCacheTag = 'cold'
  private fixture: NoteDetailBenchmarkFixture = createNoteDetailBenchmarkFixture('A', '概念', 'long')
  private stableProbeTimerId: number = -1

  aboutToAppear(): void {
    this.fixture = createNoteDetailBenchmarkFixture(this.fixtureId, this.rendererFamily, this.lengthProfile)
    const config: NoteDetailBenchmarkRunConfig = {
      fixtureId: this.fixtureId,
      runIndex: this.runIndex,
      coldWarmTag: this.coldWarmTag,
      rendererFamily: this.rendererFamily,
      lengthProfile: this.lengthProfile,
      aiHelperVisible: this.aiHelperVisible,
      webKeepAliveEnabled: this.webKeepAliveEnabled,
      cacheTag: this.cacheTag,
    }
    NoteDetailRenderMetrics.enableForRun(config)
    this.stableProbeTimerId = setInterval((): void => {
      NoteDetailRenderMetrics.markStable()
    }, 100)
  }

  aboutToDisappear(): void {
    if (this.stableProbeTimerId >= 0) {
      clearInterval(this.stableProbeTimerId)
      this.stableProbeTimerId = -1
    }
    NoteDetailRenderMetrics.markStable()
    NoteDetailRenderMetrics.dumpSnapshotHilog()
    NoteDetailRenderMetrics.disable()
  }

  build() {
    Stack() {
      NoteDetailOverlay({
        note: this.fixture.note,
        unit: this.fixture.unit,
        units: this.fixture.units,
        isCreating: false,
        generatedDraft: null,
      })
      if (this.aiHelperVisible) {
        AgentFloatWindow({
          show: true,
          benchmarkFixtureMode: true,
          benchmarkFixtureMessages: BENCHMARK_AI_HELPER_MESSAGES,
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
