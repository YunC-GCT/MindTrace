/**
 * ChatRenderFixturesBudget.test.ets — chat 渲染基准 fixtures/指标/预算推导/统计 seam 测试
 *
 * 路径: entry/src/test/ChatRenderFixturesBudget.test.ets
 * 职责: 执行 issue #124 公共测试 seam，覆盖确定性 fixtures(A/B/C/C′)、percentile、visible 判定、
 *       长帧规则、时序指标纯函数、RendererScheduler 预算推导公式、统计计数 N→N 语义。
 * 依赖: Hypium, ChatRenderFixtures, ChatRenderBenchmarkStats
 *
 * 数据流:
 *   fixture 常量/合成样本 → 纯函数 → 断言
 *
 * ArkTS 1.1 strict 适配:
 *   - 使用显式 interfaces/classes，避免无类型对象字面量。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  FIXTURE_TARGET_CODE_UNITS,
  FIXTURE_A,
  FIXTURE_B,
  FIXTURE_C,
  FIXTURE_C_P,
  ALL_FIXTURES,
  FixtureId,
  ChatRenderFixture,
  getFixtureById,
  countFormulaPairs,
  formulaPairCloseGaps,
  percentile,
  VisibleSampleInput,
  isVisibleSample,
  LONG_FRAME_MS,
  LongFrameAnalysis,
  classifyLongFrames,
  STABILITY_QUIET_MS,
  TimingSampleInput,
  TimingMetrics,
  computeTimingMetrics,
  BUDGET_FRAME_MS,
  RendererBudgets,
  deriveRendererBudgets,
} from '../main/ets/services/ChatRenderFixtures';
import {
  ChatRenderBenchmarkStats,
  BenchmarkStatsSnapshot,
} from '../main/ets/services/ChatRenderBenchmarkStats';

const assertFixtureLength = (fixture: ChatRenderFixture): void => {
  expect(fixture.bodyText.length).assertEqual(FIXTURE_TARGET_CODE_UNITS);
};

const assertFixtureFormulaCount = (fixture: ChatRenderFixture, expected: number): void => {
  expect(fixture.formulaCount).assertEqual(expected);
  expect(countFormulaPairs(fixture.bodyText)).assertEqual(expected);
};

export default function chatRenderFixturesBudgetTest(): void {
  describe('ChatRenderFixturesBudget.issue124_fixtures', () => {
    it('all_four_fixtures_have_exactly_2000_utf16_code_units', 0, () => {
      assertFixtureLength(FIXTURE_A);
      assertFixtureLength(FIXTURE_B);
      assertFixtureLength(FIXTURE_C);
      assertFixtureLength(FIXTURE_C_P);
      expect(ALL_FIXTURES.length).assertEqual(4);
    });

    it('formula_counts_are_exactly_0_2_6_6', 0, () => {
      assertFixtureFormulaCount(FIXTURE_A, 0);
      assertFixtureFormulaCount(FIXTURE_B, 2);
      assertFixtureFormulaCount(FIXTURE_C, 6);
      assertFixtureFormulaCount(FIXTURE_C_P, 6);
    });

    it('fixture_layouts_are_none_sparse_dense_consecutive_pairs', 0, () => {
      expect(FIXTURE_A.layout).assertEqual('none');
      expect(FIXTURE_B.layout).assertEqual('sparse');
      expect(FIXTURE_C.layout).assertEqual('dense');
      expect(FIXTURE_C_P.layout).assertEqual('consecutive_pairs');
    });

    it('fixture_A_contains_no_dollar_characters', 0, () => {
      expect(FIXTURE_A.bodyText.indexOf('$') < 0).assertTrue();
    });

    it('c_prime_arranges_6_formulas_as_3_consecutive_closed_pairs', 0, () => {
      // C′ 为 3 对连续闭合: 对内 gap=1,对间 gap=20,避免退化成 6 个公式平铺。
      const gaps: number[] = formulaPairCloseGaps(FIXTURE_C_P.bodyText);
      const expectedGaps: number[] = [1, 20, 1, 20, 1];
      expect(gaps.length).assertEqual(5);
      let gapIndex: number = 0;
      while (gapIndex < expectedGaps.length) {
        expect(gaps[gapIndex]).assertEqual(expectedGaps[gapIndex]);
        gapIndex += 1;
      }
      // C 的 6 个公式分散在正文中,对间间隔远大于 1。
      const scatteredGaps: number[] = formulaPairCloseGaps(FIXTURE_C.bodyText);
      expect(scatteredGaps.length).assertEqual(5);
      for (const gap of scatteredGaps) {
        expect(gap > 1).assertTrue();
      }
    });

    it('fixtures_are_character_identical_outside_formula_slots', 0, () => {
      const fixtures: ChatRenderFixture[] = [FIXTURE_B, FIXTURE_C, FIXTURE_C_P];
      for (const fixture of fixtures) {
        let index: number = 0;
        while (index < FIXTURE_TARGET_CODE_UNITS) {
          let insideSlot: boolean = false;
          for (const slot of fixture.formulaSlots) {
            if (index >= slot.start && index < slot.start + slot.length) {
              insideSlot = true;
              break;
            }
          }
          if (!insideSlot) {
            expect(fixture.bodyText.charAt(index)).assertEqual(FIXTURE_A.bodyText.charAt(index));
          }
          index += 1;
        }
      }
    });

    it('fixture_formula_content_is_frozen_and_deterministic', 0, () => {
      // B 的第一个公式槽内容冻结为固定字面量(确定性: 无随机/网络/LLM)。
      const slotStart: number = FIXTURE_B.formulaSlots[0].start;
      const slotContent: string = FIXTURE_B.bodyText.substring(slotStart, slotStart + FIXTURE_B.formulaSlots[0].length);
      expect(slotContent).assertEqual('$$x^2 + y^2 = z^2$$');
      // C′ 的唯一连续槽内容 = 6 个公式 + 3 个对内最小分隔 + 2 个较长组间分隔。
      expect(FIXTURE_C_P.formulaSlots.length).assertEqual(1);
      expect(FIXTURE_C_P.formulaSlots[0].length).assertEqual(157);
    });

    it('get_fixture_by_id_resolves_all_four_ids', 0, () => {
      const ids: FixtureId[] = ['A', 'B', 'C', 'C_P'];
      for (const id of ids) {
        const fixture: ChatRenderFixture = getFixtureById(id);
        expect(fixture.id).assertEqual(id);
        expect(fixture.bodyText.length).assertEqual(FIXTURE_TARGET_CODE_UNITS);
      }
    });
  });

  describe('ChatRenderFixturesBudget.issue124_metrics', () => {
    it('percentile_uses_nearest_rank_and_sorts_input', 0, () => {
      const values: number[] = [9, 3, 7, 1, 5, 10, 2, 8, 4, 6];
      expect(percentile(values, 50)).assertEqual(5);
      expect(percentile(values, 95)).assertEqual(10);
      expect(percentile(values, 25)).assertEqual(3);
      expect(percentile(values, 0)).assertEqual(1);
      expect(percentile(values, 100)).assertEqual(10);
      expect(percentile([], 50)).assertEqual(0);
    });

    it('visible_requires_rendered_in_viewport_and_height_applied', 0, () => {
      const visibleSample: VisibleSampleInput = {
        rendered: true,
        inViewport: true,
        renderedHeight: 58,
      };
      expect(isVisibleSample(visibleSample)).assertTrue();
      const notRendered: VisibleSampleInput = {
        rendered: false,
        inViewport: true,
        renderedHeight: 58,
      };
      expect(isVisibleSample(notRendered)).assertFalse();
      const notInViewport: VisibleSampleInput = {
        rendered: true,
        inViewport: false,
        renderedHeight: 58,
      };
      expect(isVisibleSample(notInViewport)).assertFalse();
      const zeroHeight: VisibleSampleInput = {
        rendered: true,
        inViewport: true,
        renderedHeight: 0,
      };
      expect(isVisibleSample(zeroHeight)).assertFalse();
    });

    it('long_frame_rule_is_strictly_above_32ms_and_detects_consecutive_violation', 0, () => {
      expect(LONG_FRAME_MS).assertEqual(32);
      const mixed: LongFrameAnalysis = classifyLongFrames([33.0, 20.0, 40.5, 45.0]);
      expect(mixed.longFrameCount).assertEqual(3);
      expect(mixed.hasConsecutiveLongFrames).assertTrue();
      expect(mixed.consecutiveLongFramePairCount).assertEqual(1);
      const quiet: LongFrameAnalysis = classifyLongFrames([16.7, 16.7, 16.7]);
      expect(quiet.longFrameCount).assertEqual(0);
      expect(quiet.hasConsecutiveLongFrames).assertFalse();
      const boundary: LongFrameAnalysis = classifyLongFrames([32.0, 32.1, 32.0]);
      expect(boundary.longFrameCount).assertEqual(1);
      expect(boundary.hasConsecutiveLongFrames).assertFalse();
    });

    it('timing_metrics_compute_first_delta_finish_and_stable_deltas', 0, () => {
      expect(STABILITY_QUIET_MS).assertEqual(500);
      const sample: TimingSampleInput = {
        deltaStartTs: 1000,
        firstVisibleTs: 1800,
        finishTs: 1500,
        lastHeightChangeTs: 2100,
        stableObserved: true,
      };
      const metrics: TimingMetrics = computeTimingMetrics(sample);
      expect(metrics.tFirstDeltaToVisibleMs).assertEqual(800);
      expect(metrics.finishToVisibleMs).assertEqual(300);
      expect(metrics.tFinishToStableMs).assertEqual(1100);
    });

    it('timing_metrics_return_minus_one_when_events_never_arrive', 0, () => {
      const noVisible: TimingSampleInput = {
        deltaStartTs: 1000,
        firstVisibleTs: -1,
        finishTs: 1500,
        lastHeightChangeTs: 2100,
        stableObserved: true,
      };
      const metricsNoVisible: TimingMetrics = computeTimingMetrics(noVisible);
      expect(metricsNoVisible.tFirstDeltaToVisibleMs).assertEqual(-1);
      expect(metricsNoVisible.finishToVisibleMs).assertEqual(-1);
      const noStable: TimingSampleInput = {
        deltaStartTs: 1000,
        firstVisibleTs: 1800,
        finishTs: 1500,
        lastHeightChangeTs: -1,
        stableObserved: false,
      };
      const metricsNoStable: TimingMetrics = computeTimingMetrics(noStable);
      expect(metricsNoStable.tFinishToStableMs).assertEqual(-1);
    });
  });

  describe('ChatRenderFixturesBudget.issue124_budgets', () => {
    it('derive_budgets_matches_manual_recompute_on_synthetic_evidence', 0, () => {
      expect(BUDGET_FRAME_MS).assertEqual(32);
      // perCreateWorkMs = [4,6,8,10]: median 7 → floor(32/7)=4; p75(nearest-rank)=8。
      const budgets: RendererBudgets = deriveRendererBudgets([4, 6, 8, 10]);
      expect(budgets.maxWebCreatesPerFrame).assertEqual(4);
      expect(budgets.maxWebWorkMsPerFrame).assertEqual(8);
    });

    it('derive_budgets_clamps_into_frozen_ranges', 0, () => {
      const tiny: RendererBudgets = deriveRendererBudgets([1]);
      expect(tiny.maxWebCreatesPerFrame).assertEqual(4);
      expect(tiny.maxWebWorkMsPerFrame).assertEqual(1);
      const huge: RendererBudgets = deriveRendererBudgets([100]);
      expect(huge.maxWebCreatesPerFrame).assertEqual(1);
      expect(huge.maxWebWorkMsPerFrame).assertEqual(16);
      const empty: RendererBudgets = deriveRendererBudgets([]);
      expect(empty.maxWebCreatesPerFrame).assertEqual(1);
      expect(empty.maxWebWorkMsPerFrame).assertEqual(1);
    });
  });

  describe('ChatRenderFixturesBudget.issue124_stats', () => {
    it('counters_report_N_calls_as_N_counts', 0, () => {
      ChatRenderBenchmarkStats.resetCountersForTest();
      ChatRenderBenchmarkStats.recordWebCreate();
      ChatRenderBenchmarkStats.recordWebCreate();
      ChatRenderBenchmarkStats.recordWebCreate();
      ChatRenderBenchmarkStats.recordHeightUpdate();
      ChatRenderBenchmarkStats.recordHeightUpdate();
      ChatRenderBenchmarkStats.recordHeightUpdate();
      ChatRenderBenchmarkStats.recordHeightUpdate();
      ChatRenderBenchmarkStats.recordHeightUpdate();
      ChatRenderBenchmarkStats.recordHeightApplied();
      ChatRenderBenchmarkStats.recordHeightApplied();
      ChatRenderBenchmarkStats.recordHeightApplied();
      ChatRenderBenchmarkStats.recordWebWorkStart();
      ChatRenderBenchmarkStats.recordWebWorkStart();
      ChatRenderBenchmarkStats.recordCacheHit();
      ChatRenderBenchmarkStats.recordCacheHit();
      ChatRenderBenchmarkStats.recordCacheHit();
      ChatRenderBenchmarkStats.recordCacheHit();
      ChatRenderBenchmarkStats.recordCacheHit();
      ChatRenderBenchmarkStats.recordCacheHit();
      ChatRenderBenchmarkStats.recordCacheHit();
      ChatRenderBenchmarkStats.recordCacheMiss();
      ChatRenderBenchmarkStats.recordCacheMiss();
      ChatRenderBenchmarkStats.recordCacheMiss();
      ChatRenderBenchmarkStats.recordCacheMiss();
      ChatRenderBenchmarkStats.recordCacheMiss();
      ChatRenderBenchmarkStats.recordCacheMiss();
      ChatRenderBenchmarkStats.recordCacheMiss();
      ChatRenderBenchmarkStats.recordCacheMiss();
      ChatRenderBenchmarkStats.recordCacheMiss();
      ChatRenderBenchmarkStats.recordCacheMiss();
      ChatRenderBenchmarkStats.recordCacheMiss();
      ChatRenderBenchmarkStats.recordDegradation();
      ChatRenderBenchmarkStats.recordDegradation();
      ChatRenderBenchmarkStats.recordDegradation();
      ChatRenderBenchmarkStats.recordDegradation();
      ChatRenderBenchmarkStats.recordDegradation();
      ChatRenderBenchmarkStats.recordDegradation();
      ChatRenderBenchmarkStats.recordDegradation();
      ChatRenderBenchmarkStats.recordDegradation();
      ChatRenderBenchmarkStats.recordDegradation();
      ChatRenderBenchmarkStats.recordDegradation();
      ChatRenderBenchmarkStats.recordDegradation();
      ChatRenderBenchmarkStats.recordDegradation();
      ChatRenderBenchmarkStats.recordDegradation();
      const snapshot: BenchmarkStatsSnapshot = ChatRenderBenchmarkStats.snapshot();
      expect(snapshot.webCreateCount).assertEqual(3);
      expect(snapshot.heightUpdateCount).assertEqual(5);
      expect(snapshot.heightAppliedCount).assertEqual(3);
      expect(snapshot.webWorkStartCount).assertEqual(2);
      expect(snapshot.cacheHitCount).assertEqual(7);
      expect(snapshot.cacheMissCount).assertEqual(11);
      expect(snapshot.degradationCount).assertEqual(13);
      ChatRenderBenchmarkStats.resetCountersForTest();
    });

    it('web_work_duration_samples_pair_starts_with_real_height_applications_and_freeze_on_disable', 0, () => {
      ChatRenderBenchmarkStats.resetCountersForTest();
      ChatRenderBenchmarkStats.enableForRun('B', 2);
      ChatRenderBenchmarkStats.recordWebWorkStart();
      ChatRenderBenchmarkStats.recordHeightApplied();
      const duringRun: BenchmarkStatsSnapshot = ChatRenderBenchmarkStats.snapshot();
      expect(duringRun.webWorkStartCount).assertEqual(1);
      expect(duringRun.webWorkDurationSamplesMs.length).assertEqual(1);
      expect(duringRun.webWorkDurationSamplesMs[0] >= 0).assertTrue();
      ChatRenderBenchmarkStats.disable();
      ChatRenderBenchmarkStats.recordWebWorkStart();
      ChatRenderBenchmarkStats.recordHeightApplied();
      const afterDisable: BenchmarkStatsSnapshot = ChatRenderBenchmarkStats.snapshot();
      expect(afterDisable.webWorkStartCount).assertEqual(1);
      expect(afterDisable.webWorkDurationSamplesMs.length).assertEqual(1);
      ChatRenderBenchmarkStats.resetCountersForTest();
    });

    it('timestamps_track_real_height_applications_only', 0, () => {
      ChatRenderBenchmarkStats.resetCountersForTest();
      ChatRenderBenchmarkStats.enableForRun('A', 0);
      ChatRenderBenchmarkStats.recordHeightUpdate();
      const beforeApply: BenchmarkStatsSnapshot = ChatRenderBenchmarkStats.snapshot();
      expect(beforeApply.firstHeightAppliedTs).assertEqual(-1);
      expect(beforeApply.lastHeightAppliedTs).assertEqual(-1);
      expect(beforeApply.heightAppliedCount).assertEqual(0);
      ChatRenderBenchmarkStats.recordHeightApplied();
      const afterApply: BenchmarkStatsSnapshot = ChatRenderBenchmarkStats.snapshot();
      expect(afterApply.heightAppliedCount).assertEqual(1);
      expect(afterApply.firstHeightAppliedTs >= 0).assertTrue();
      expect(afterApply.lastHeightAppliedTs).assertEqual(afterApply.firstHeightAppliedTs);
      ChatRenderBenchmarkStats.resetCountersForTest();
    });

    it('enable_for_run_takes_delta_snapshot_semantics', 0, () => {
      ChatRenderBenchmarkStats.resetCountersForTest();
      ChatRenderBenchmarkStats.recordWebCreate();
      ChatRenderBenchmarkStats.recordWebCreate();
      ChatRenderBenchmarkStats.enableForRun('A', 0);
      ChatRenderBenchmarkStats.recordWebCreate();
      ChatRenderBenchmarkStats.recordWebCreate();
      ChatRenderBenchmarkStats.recordWebCreate();
      const duringRun: BenchmarkStatsSnapshot = ChatRenderBenchmarkStats.snapshot();
      expect(duringRun.webCreateCount).assertEqual(3);
      expect(duringRun.fixtureId).assertEqual('A');
      expect(duringRun.runIndex).assertEqual(0);
      ChatRenderBenchmarkStats.disable();
      ChatRenderBenchmarkStats.recordWebCreate();
      const afterDisable: BenchmarkStatsSnapshot = ChatRenderBenchmarkStats.snapshot();
      expect(afterDisable.webCreateCount).assertEqual(3);
      ChatRenderBenchmarkStats.enableForRun('B', 1);
      const nextRun: BenchmarkStatsSnapshot = ChatRenderBenchmarkStats.snapshot();
      expect(nextRun.webCreateCount).assertEqual(0);
      expect(nextRun.fixtureId).assertEqual('B');
      expect(nextRun.runIndex).assertEqual(1);
      ChatRenderBenchmarkStats.resetCountersForTest();
    });
  });
}
