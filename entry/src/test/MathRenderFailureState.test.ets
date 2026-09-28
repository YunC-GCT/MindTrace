/**
 * MathRenderFailureState.test.ets — #184 单公式失败隔离测试
 *
 * 路径: entry/src/test/MathRenderFailureState.test.ets
 * 职责: 验证高度、bridge 与 render-exit 失败只影响当前公式实例。
 * 依赖: Hypium, MathRenderFailureState
 *
 * 数据流:
 *   合成失败事件 → MathRenderFailureState → 当前/后续公式可达性断言
 *
 * ArkTS 1.1 strict 适配:
 *   - fixture 使用显式实例与 number/boolean 类型。
 */

import { describe, it, expect } from '@ohos/hypium'
import { MathRenderFailureState } from '../main/ets/utils/MathRenderFailureState'

export default function mathRenderFailureStateTest(): void {
  describe('MathRenderFailureState.issue184_failure_isolation', () => {
    it('invalid_height_degrades_only_the_current_formula', 0, () => {
      const current: MathRenderFailureState = new MathRenderFailureState()
      const following: MathRenderFailureState = new MathRenderFailureState()
      expect(current.acceptHeight(Number.NaN)).assertFalse()
      expect(current.shouldUsePlainFallback()).assertTrue()
      current.reset()
      expect(current.acceptHeight(Number.POSITIVE_INFINITY)).assertFalse()
      expect(current.shouldUsePlainFallback()).assertTrue()
      expect(following.shouldUsePlainFallback()).assertFalse()
      expect(following.acceptHeight(72)).assertTrue()
    })

    it('render_exit_and_bridge_failure_keep_later_formula_reachable', 0, () => {
      const exited: MathRenderFailureState = new MathRenderFailureState()
      const bridgeFailed: MathRenderFailureState = new MathRenderFailureState()
      const laterFormula: MathRenderFailureState = new MathRenderFailureState()
      exited.recordFailure()
      bridgeFailed.recordFailure()
      expect(exited.shouldUsePlainFallback()).assertTrue()
      expect(bridgeFailed.shouldUsePlainFallback()).assertTrue()
      expect(laterFormula.acceptHeight(64)).assertTrue()
      expect(laterFormula.shouldUsePlainFallback()).assertFalse()
    })

    it('successful_retry_clears_the_local_failure', 0, () => {
      const state: MathRenderFailureState = new MathRenderFailureState()
      state.recordFailure()
      expect(state.shouldUsePlainFallback()).assertTrue()
      expect(state.acceptHeight(80)).assertTrue()
      expect(state.shouldUsePlainFallback()).assertFalse()
      state.recordFailure()
      state.reset()
      expect(state.shouldUsePlainFallback()).assertFalse()
    })
  })
}
