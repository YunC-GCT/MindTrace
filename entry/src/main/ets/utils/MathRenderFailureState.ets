/**
 * MathRenderFailureState.ets — 单个公式 Web 渲染失败状态
 *
 * 路径: entry/src/main/ets/utils/MathRenderFailureState.ets
 * 职责: 判定无效高度与 Web 生命周期失败，并把降级范围限制在当前 renderer 实例。
 * 依赖: 无
 *
 * 数据流:
 *   Web 高度/render-exit → MathRenderFailureState → 当前 MathTextRenderer 纯文本降级
 *
 * ArkTS 1.1 strict 适配:
 *   - 使用显式 number/boolean 类型，不使用 any/unknown。
 */

export class MathRenderFailureState {
  private failed: boolean = false

  reset(): void {
    this.failed = false
  }

  acceptHeight(height: number): boolean {
    if (!Number.isFinite(height) || height <= 0) {
      this.failed = true
      return false
    }
    this.failed = false
    return true
  }

  recordFailure(): void {
    this.failed = true
  }

  shouldUsePlainFallback(): boolean {
    return this.failed
  }
}
