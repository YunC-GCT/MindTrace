/**
 * NoteDetailRenderBaseline.test.ets — #185 fixture 与 surface 指标纯逻辑测试
 *
 * 路径: entry/src/test/NoteDetailRenderBaseline.test.ets
 * 职责: 验证 A/B/C/C′、short/long、六 renderer 输入以及确定性指标快照语义。
 * 依赖: Hypium, NoteDetailRenderFixtures, NoteDetailRenderMetrics
 *
 * 数据流:
 *   固定 fixture/合成时间戳 → 公共 seam → 行为断言
 *
 * ArkTS 1.1 strict 适配:
 *   - 对象字面量使用显式接口；不使用 any/unknown/解构。
 */

import { describe, it, expect } from '@ohos/hypium'
import {
  NOTE_DETAIL_FIXTURES,
  NOTE_DETAIL_RENDERER_FAMILIES,
  NOTE_DETAIL_SHORT_CODE_UNITS,
  NOTE_DETAIL_LONG_CODE_UNITS,
  NoteDetailBenchmarkFixture,
  NoteDetailFixtureId,
  createNoteDetailBenchmarkFixture,
  countNoteDetailFormulaPairs,
  noteDetailFormulaGaps,
} from '../main/ets/services/NoteDetailRenderFixtures'
import {
  NoteDetailBenchmarkRunConfig,
  NoteDetailRenderMetrics,
  NoteDetailRenderMetricsSnapshot,
} from '../main/ets/services/NoteDetailRenderMetrics'
import {
  recordNoteDetailBenchmarkFrame,
  recordNoteDetailBenchmarkMemory,
  snapshotNoteDetailBenchmark,
} from '../main/ets/benchmark/NoteDetailRenderBenchmarkHarness'
import {
  KEEP_ALIVE_MAX_RECOVERY,
  WebKeepAliveRecoveryBudget,
} from '../main/ets/shared/atoms/WebKeepAlive'

const expectedFormulaCount = (id: NoteDetailFixtureId): number => {
  if (id === 'A') { return 0 }
  if (id === 'B') { return 2 }
  return 6
}

export default function noteDetailRenderBaselineTest(): void {
  describe('NoteDetailRenderBaseline.issue185_fixtures', () => {
    it('A_B_C_C_prime_are_offline_and_formula_counts_are_0_2_6_6', 0, () => {
      expect(NOTE_DETAIL_FIXTURES.length).assertEqual(4)
      for (const definition of NOTE_DETAIL_FIXTURES) {
        const fixture: NoteDetailBenchmarkFixture = createNoteDetailBenchmarkFixture(
          definition.id, '概念', 'long')
        expect(fixture.formulaCount).assertEqual(expectedFormulaCount(definition.id))
        expect(countNoteDetailFormulaPairs(fixture.bodyText)).assertEqual(expectedFormulaCount(definition.id))
        expect(countNoteDetailFormulaPairs(fixture.bodyText + fixture.unit.summary))
          .assertEqual(expectedFormulaCount(definition.id))
        expect(fixture.bodyText.length).assertEqual(NOTE_DETAIL_LONG_CODE_UNITS)
      }
    })

    it('short_and_long_profiles_have_frozen_UTF16_lengths', 0, () => {
      const shortFixture: NoteDetailBenchmarkFixture = createNoteDetailBenchmarkFixture('C', '公式', 'short')
      const longFixture: NoteDetailBenchmarkFixture = createNoteDetailBenchmarkFixture('C', '公式', 'long')
      expect(shortFixture.bodyText.length).assertEqual(NOTE_DETAIL_SHORT_CODE_UNITS)
      expect(longFixture.bodyText.length).assertEqual(NOTE_DETAIL_LONG_CODE_UNITS)
      expect(countNoteDetailFormulaPairs(shortFixture.bodyText)).assertEqual(6)
      expect(countNoteDetailFormulaPairs(longFixture.bodyText)).assertEqual(6)
    })

    it('C_prime_keeps_three_consecutive_formula_pairs', 0, () => {
      const fixture: NoteDetailBenchmarkFixture = createNoteDetailBenchmarkFixture('C_P', '证明题', 'long')
      const gaps: number[] = noteDetailFormulaGaps(fixture.bodyText)
      expect(gaps.length).assertEqual(5)
      expect(gaps[0]).assertEqual(1)
      expect(gaps[2]).assertEqual(1)
      expect(gaps[4]).assertEqual(1)
    })

    it('factory_covers_all_six_renderer_inputs', 0, () => {
      expect(NOTE_DETAIL_RENDERER_FAMILIES.length).assertEqual(6)
      for (const rendererFamily of NOTE_DETAIL_RENDERER_FAMILIES) {
        const fixture: NoteDetailBenchmarkFixture = createNoteDetailBenchmarkFixture(
          'A', rendererFamily, 'short')
        expect(fixture.rendererFamily).assertEqual(rendererFamily)
        expect(fixture.note.rawId).assertEqual(fixture.unit.id)
        expect(fixture.units.length).assertEqual(1)
      }
    })
  })

  describe('NoteDetailRenderBaseline.issue185_metrics', () => {
    it('snapshot_reports_timing_Web_height_frame_exit_memory_and_state_metrics', 0, () => {
      const config: NoteDetailBenchmarkRunConfig = {
        fixtureId: 'C_P',
        runIndex: 0,
        coldWarmTag: 'cold',
        rendererFamily: '证明题',
        lengthProfile: 'long',
        aiHelperVisible: true,
        webKeepAliveEnabled: false,
        cacheTag: 'cold',
      }
      NoteDetailRenderMetrics.resetForTest()
      NoteDetailRenderMetrics.enableForRun(config, 1000)
      NoteDetailRenderMetrics.recordViewportHeight(400, 1100)
      NoteDetailRenderMetrics.recordWebCreate(1150)
      NoteDetailRenderMetrics.recordWebCreate(1170)
      NoteDetailRenderMetrics.recordWebWorkStart(1160)
      NoteDetailRenderMetrics.recordHeightUpdate(1180)
      NoteDetailRenderMetrics.recordHeightApplied(1210)
      NoteDetailRenderMetrics.recordFormulaVisible(1210)
      recordNoteDetailBenchmarkFrame(33, 1300)
      recordNoteDetailBenchmarkFrame(40, 1350)
      NoteDetailRenderMetrics.recordRenderExit(7)
      recordNoteDetailBenchmarkMemory(4096, 8192)
      NoteDetailRenderMetrics.recordHeaderMount()
      NoteDetailRenderMetrics.recordBodyMount()
      NoteDetailRenderMetrics.recordBodyInputChange()
      NoteDetailRenderMetrics.recordEditState()
      NoteDetailRenderMetrics.recordDeleteConfirm()
      NoteDetailRenderMetrics.recordDraftState()
      expect(NoteDetailRenderMetrics.markStable(1600)).assertFalse()
      expect(NoteDetailRenderMetrics.markStable(1710)).assertTrue()

      const snapshot: NoteDetailRenderMetricsSnapshot = snapshotNoteDetailBenchmark()
      expect(snapshot.surface).assertEqual('noteDetail')
      expect(snapshot.openToFirstVisibleMs).assertEqual(100)
      expect(snapshot.formulaVisibleMs).assertEqual(210)
      expect(snapshot.openToStableMs).assertEqual(710)
      expect(snapshot.webCreateCount).assertEqual(2)
      expect(snapshot.webCreatesPerFrame[0]).assertEqual(2)
      expect(snapshot.maxWebCreatesPerFrame).assertEqual(2)
      expect(snapshot.webWorkStartCount).assertEqual(1)
      expect(snapshot.webWorkDurationSamplesMs.length).assertEqual(1)
      expect(snapshot.webWorkDurationSamplesMs[0]).assertEqual(50)
      expect(snapshot.heightUpdateCount).assertEqual(1)
      expect(snapshot.heightAppliedCount).assertEqual(1)
      expect(snapshot.longFrameCount).assertEqual(2)
      expect(snapshot.consecutiveLongFramePairCount).assertEqual(1)
      expect(snapshot.renderExitReasons[0]).assertEqual(7)
      expect(snapshot.heapUsedKb).assertEqual(4096)
      expect(snapshot.totalHeapKb).assertEqual(8192)
      expect(snapshot.headerMountCount).assertEqual(1)
      expect(snapshot.bodyMountCount).assertEqual(1)
      expect(snapshot.bodyInputChangeCount).assertEqual(1)
      expect(snapshot.editStateCount).assertEqual(1)
      expect(snapshot.deleteConfirmCount).assertEqual(1)
      expect(snapshot.draftStateCount).assertEqual(1)
      NoteDetailRenderMetrics.resetForTest()
    })

    it('disable_freezes_the_completed_run', 0, () => {
      const config: NoteDetailBenchmarkRunConfig = {
        fixtureId: 'A',
        runIndex: 1,
        coldWarmTag: 'warm',
        rendererFamily: '概念',
        lengthProfile: 'short',
        aiHelperVisible: false,
        webKeepAliveEnabled: true,
        cacheTag: 'hit',
      }
      NoteDetailRenderMetrics.resetForTest()
      NoteDetailRenderMetrics.enableForRun(config, 2000)
      NoteDetailRenderMetrics.recordViewportHeight(200, 2050)
      NoteDetailRenderMetrics.disable()
      NoteDetailRenderMetrics.recordViewportHeight(300, 2100)
      const snapshot: NoteDetailRenderMetricsSnapshot = NoteDetailRenderMetrics.snapshot()
      expect(snapshot.lastViewportHeight).assertEqual(200)
      expect(snapshot.coldWarmTag).assertEqual('warm')
      expect(snapshot.cacheTag).assertEqual('hit')
      NoteDetailRenderMetrics.resetForTest()
    })

    it('WebKeepAlive_recovery_is_bounded', 0, () => {
      const budget: WebKeepAliveRecoveryBudget = new WebKeepAliveRecoveryBudget()
      let accepted: number = 0
      let index: number = 0
      while (index < KEEP_ALIVE_MAX_RECOVERY + 2) {
        if (budget.claimRecovery()) { accepted += 1 }
        index += 1
      }
      expect(accepted).assertEqual(KEEP_ALIVE_MAX_RECOVERY)
      expect(budget.count()).assertEqual(KEEP_ALIVE_MAX_RECOVERY)
    })
  })
}
