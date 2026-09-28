/**
 * MathRenderBudget.ets — 公式准备缓存与 Web 生命周期准入边界
 *
 * 路径: entry/src/main/ets/services/MathRenderBudget.ets
 * 职责: 提供稳定的公式准备 memo seam，并让共享 renderer 消费宿主 Web 创建与工作预算。
 * 依赖: 无
 *
 * 数据流:
 *   公式输入 → MathRenderPreparationMemo → MathTextRenderer → MathRenderBudget → 宿主实例调度器
 */

export const DEFAULT_MATH_RENDER_PRIORITY: number = 10

export class MathRenderInput {
  normalizedText: string = ''
  fallbackText: string = ''
  renderMode: 'native' | 'katex' | 'plainFallback' = 'native'
}

export class PreparedMathRender {
  input: MathRenderInput = new MathRenderInput()
  markdown: string = ''
  cacheKey: string = ''
}

export type MathRenderPreparationFactory = () => PreparedMathRender

export class MathRenderPreparationMemo {
  private key: string = ''
  private value: PreparedMathRender | null = null

  resolve(key: string, factory: MathRenderPreparationFactory): PreparedMathRender {
    if (key === this.key && this.value !== null) {
      return this.value
    }
    const prepared: PreparedMathRender = factory()
    this.key = key
    this.value = prepared
    return prepared
  }
}

export function buildMathRenderPreparationKey(rawText: string, profile: string,
  forceDisplay: boolean, protocolVersion: string, cacheKeyVersion: string): string {
  const normalizedInput: string = rawText.replace(/\r\n/g, '\n').replace(/\r/g, '\n').trim()
  return normalizedInput + '|' + profile + '|' + (forceDisplay ? '1' : '0')
    + '|' + protocolVersion + '|' + cacheKeyVersion
}

export function buildNormalizedMathRenderScript(prepared: PreparedMathRender,
  profile: string, forceDisplay: boolean): string {
  const renderFn: string = forceDisplay ? 'renderFormulaForCache' : 'renderForCache'
  return renderFn + '(' + JSON.stringify(prepared.markdown) + ',' + JSON.stringify(profile) + ')'
}

export type MathRenderWorkComplete = (workDurationMs: number) => void
export type MathRenderWork = (complete: MathRenderWorkComplete) => void
export type MathRenderCreateComplete = () => void
export type MathRenderCreateWork = (complete: MathRenderCreateComplete) => void

export interface MathRenderBudget {
  enqueueContent(key: string, priority: number, run: () => void): void
  enqueueWebCreate(key: string, priority: number, run: MathRenderCreateWork): void
  enqueueWebWork(key: string, priority: number, run: MathRenderWork): void
}
