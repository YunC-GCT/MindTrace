/**
 * NoteDetailRenderBenchmarkHarness.ets — #185 NoteDetail target-device measurement seam
 *
 * Path: entry/src/main/ets/benchmark/NoteDetailRenderBenchmarkHarness.ets
 * Responsibility: Mount the real read-only NoteDetailOverlay with deterministic fixtures and
 *                 collect externally supplied frame/memory samples for one benchmark run.
 * Dependencies: NoteDetailOverlay, NoteDetailRenderFixtures, NoteDetailRenderMetrics.
 *
 * Data flow:
 *   run props -> deterministic fixture -> real NoteDetailOverlay -> metrics snapshot/hilog
 *   device profiler -> exported frame/memory functions -> metrics snapshot
 *
 * Design notes:
 *   - This component is intentionally absent from main_pages.json and EntryAbility.
 *   - Frame duration and memory come from the target-device profiler; no synthetic values are used.
 *   - Metrics are enabled before the child overlay mounts and disabled when the harness unmounts.
 *
 * ArkTS 1.1 strict:
 *   - Literal unions and benchmark objects have explicit types.
 *   - No any/unknown, dynamic property access, network, randomness, or LLM dependency.
 */

import { NoteDetailOverlay } from '../overlays/NoteDetailOverlay/NoteDetailOverlay'
import {
  NoteDetailBenchmarkFixture,
  NoteDetailFixtureId,
  NoteDetailFixtureNoteType,
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
  @Prop noteType: NoteDetailFixtureNoteType = '概念'
  @Prop lengthProfile: NoteDetailLengthProfile = 'long'
  @Prop runIndex: number = 0
  @Prop coldWarmTag: NoteDetailColdWarmTag = 'cold'
  @Prop aiHelperVisible: boolean = false
  @Prop cacheTag: NoteDetailCacheTag = 'cold'
  private fixture: NoteDetailBenchmarkFixture = createNoteDetailBenchmarkFixture('A', '概念', 'long')

  aboutToAppear(): void {
    this.fixture = createNoteDetailBenchmarkFixture(this.fixtureId, this.noteType, this.lengthProfile)
    const config: NoteDetailBenchmarkRunConfig = {
      fixtureId: this.fixtureId,
      runIndex: this.runIndex,
      coldWarmTag: this.coldWarmTag,
      noteType: this.noteType,
      lengthProfile: this.lengthProfile,
      aiHelperVisible: this.aiHelperVisible,
      cacheTag: this.cacheTag,
    }
    NoteDetailRenderMetrics.enableForRun(config)
  }

  aboutToDisappear(): void {
    NoteDetailRenderMetrics.markStable()
    NoteDetailRenderMetrics.dumpSnapshotHilog()
    NoteDetailRenderMetrics.disable()
  }

  build() {
    NoteDetailOverlay({
      note: this.fixture.note,
      unit: this.fixture.unit,
      units: this.fixture.units,
      isCreating: false,
      generatedDraft: null,
    })
  }
}
