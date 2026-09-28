// ============================================================================
//  shared/atoms/MathTextRenderer.ets - KaTeX Web renderer wrapper
// ============================================================================

import {
  TEXT, TEXT_2, GLASS_10, BORDER,
  F_BASE,
  LatexRiskNormalizer,
  ContentProtocol,
} from 'common'
import type { ContentValidationResult, LatexRiskResult } from 'common'
import webview from '@ohos.web.webview'
import { uiCacheLog } from '../../utils/UiCacheDebug'
import { ChatRenderBenchmarkStats } from '../../services/ChatRenderBenchmarkStats'
import {
  NoteDetailMetricSurface,
  NoteDetailRenderMetrics,
} from '../../services/NoteDetailRenderMetrics'
import { MathRenderFailureState } from '../../utils/MathRenderFailureState'
import {
  DEFAULT_MATH_RENDER_PRIORITY,
  MathRenderInput,
  MathRenderPreparationMemo,
  PreparedMathRender,
  buildMathRenderPreparationKey,
  buildNormalizedMathRenderScript,
} from '../../services/MathRenderBudget'
import type {
  MathRenderBudget,
  MathRenderWork,
  MathRenderWorkComplete,
} from '../../services/MathRenderBudget'

class MathRenderCacheEntry {
  key: string = ''
  encodedHtml: string = ''
  height: number = 0
  touched: number = 0
  touchedAt: number = 0
  size: number = 0

  constructor(key: string, encodedHtml: string, height: number, touched: number, touchedAt: number) {
    this.key = key
    this.encodedHtml = encodedHtml
    this.height = height
    this.touched = touched
    this.touchedAt = touchedAt
    this.size = encodedHtml.length
  }
}

class MathRenderPayload {
  height: number = 0
  encodedHtml: string = ''
}

const MATH_RENDER_CACHE: MathRenderCacheEntry[] = []
const MATH_RENDER_CACHE_LIMIT: number = 64
const MATH_RENDER_CACHE_MAX_CHARS: number = 600000
const MATH_RENDER_CACHE_KEY_VERSION: string = 'v2'
const MATH_RENDER_PROTOCOL_VERSION: string = 'MM-MD-v1'
const MATH_RENDER_CACHE_TTL_MS: number = 10 * 60 * 1000
const MATH_RENDER_CACHE_PASSIVE_TRIM_TICKS: number = 12
const TEXT_HEIGHT_BUFFER_RATIO: number = 1.2
const DISPLAY_FORMULA_HEIGHT_CHAT: number = 58
const DISPLAY_FORMULA_HEIGHT_NOTE: number = 66
let mathRenderCacheClock: number = 0

function nextCacheTick(): number {
  mathRenderCacheClock += 1
  return mathRenderCacheClock
}

function cacheGet(key: string, metricSurface: NoteDetailMetricSurface): MathRenderCacheEntry | null {
  const now: number = Date.now()
  trimCacheIfNeeded(now)
  for (const entry of MATH_RENDER_CACHE) {
    if (entry.key === key) {
      entry.touched = nextCacheTick()
      entry.touchedAt = now
      uiCacheLog('[UiDataCache] math hit key=' + key)
      ChatRenderBenchmarkStats.recordCacheHit()
      if (metricSurface === 'noteDetail') {
        NoteDetailRenderMetrics.recordCacheHit()
      }
      return entry
    }
  }
  uiCacheLog('[UiDataCache] math miss key=' + key)
  ChatRenderBenchmarkStats.recordCacheMiss()
  if (metricSurface === 'noteDetail') {
    NoteDetailRenderMetrics.recordCacheMiss()
  }
  return null
}

function cacheSet(key: string, encodedHtml: string, height: number): void {
  const now: number = Date.now()
  const touched: number = nextCacheTick()
  if (encodedHtml.length > MATH_RENDER_CACHE_MAX_CHARS) {
    cacheRemove(key)
    trimCache(now)
    return
  }
  for (const entry of MATH_RENDER_CACHE) {
    if (entry.key === key) {
      entry.encodedHtml = encodedHtml
      entry.height = height
      entry.touched = touched
      entry.touchedAt = now
      entry.size = encodedHtml.length
      trimCacheIfNeeded(now)
      return
    }
  }
  MATH_RENDER_CACHE.push(new MathRenderCacheEntry(key, encodedHtml, height, touched, now))
  trimCache(now)
}

function cacheRemove(key: string): void {
  let index: number = MATH_RENDER_CACHE.length - 1
  while (index >= 0) {
    if (MATH_RENDER_CACHE[index].key === key) {
      MATH_RENDER_CACHE.splice(index, 1)
    }
    index -= 1
  }
}

function trimCacheIfNeeded(now: number): void {
  if (MATH_RENDER_CACHE.length > MATH_RENDER_CACHE_LIMIT
    || mathRenderCacheClock % MATH_RENDER_CACHE_PASSIVE_TRIM_TICKS === 0) {
    trimCache(now)
  }
}

function trimCache(now: number): void {
  dropExpiredCacheEntries(now)
  while (MATH_RENDER_CACHE.length > MATH_RENDER_CACHE_LIMIT) {
    removeOldestCacheEntry()
  }
  while (cacheTotalSize() > MATH_RENDER_CACHE_MAX_CHARS && MATH_RENDER_CACHE.length > 0) {
    removeOldestCacheEntry()
  }
}

function dropExpiredCacheEntries(now: number): void {
  let index: number = MATH_RENDER_CACHE.length - 1
  while (index >= 0) {
    if (now - MATH_RENDER_CACHE[index].touchedAt > MATH_RENDER_CACHE_TTL_MS) {
      MATH_RENDER_CACHE.splice(index, 1)
    }
    index -= 1
  }
}

function removeOldestCacheEntry(): void {
  if (MATH_RENDER_CACHE.length === 0) {
    return
  }
  let oldestIndex: number = 0
  let oldestTick: number = MATH_RENDER_CACHE[0].touched
  let index: number = 1
  while (index < MATH_RENDER_CACHE.length) {
    if (MATH_RENDER_CACHE[index].touched < oldestTick) {
      oldestTick = MATH_RENDER_CACHE[index].touched
      oldestIndex = index
    }
    index += 1
  }
  MATH_RENDER_CACHE.splice(oldestIndex, 1)
}

function cacheTotalSize(): number {
  let total: number = 0
  for (const entry of MATH_RENDER_CACHE) {
    total += entry.size
  }
  return total
}

function contentHash(text: string): string {
  let hash: number = 5381
  let index: number = 0
  while (index < text.length) {
    hash = ((hash << 5) + hash + text.charCodeAt(index)) | 0
    index += 1
  }
  const positive: number = hash < 0 ? -hash : hash
  return text.length.toString() + '_' + positive.toString()
}

@Component
export struct MathTextRenderer {
  @Prop @Watch('onTextChanged') text: string = ''
  @Prop textColor: ResourceColor = TEXT_2
  @Prop formulaColor: ResourceColor = TEXT
  @Prop formulaBackground: ResourceColor = GLASS_10
  @Prop formulaBorder: ResourceColor = BORDER
  @Prop fontSize: number = F_BASE
  @Prop lineHeight: number = 24
  @Prop formulaFontSize: number = F_BASE
  @Prop formulaLineHeight: number = 24
  @Prop profile: 'chat' | 'chatUser' | 'note' | 'preview' = 'chat'
  @Prop metricSurface: NoteDetailMetricSurface = 'none'
  @Prop renderBudget: MathRenderBudget | null = null
  @Prop renderPriority: number = DEFAULT_MATH_RENDER_PRIORITY
  @Prop forceDisplay: boolean = false
  @Prop minHeight: number = 42

  private controller: webview.WebviewController = new webview.WebviewController()
  private lastAppliedKey: string = ''
  private riskNormalizer: LatexRiskNormalizer = new LatexRiskNormalizer()
  private contentProtocol: ContentProtocol = new ContentProtocol()
  @State private pageReady: boolean = false
  @State private renderReady: boolean = true
  @State private webFailed: boolean = false
  @State private webHeight: number = 42
  private renderSeq: number = 0
  private heightApplied: boolean = false
  private visibleInViewport: boolean = false
  private formulaVisibleReported: boolean = false
  private failureState: MathRenderFailureState = new MathRenderFailureState()
  private preparationMemo: MathRenderPreparationMemo = new MathRenderPreparationMemo()

  aboutToAppear(): void {
    this.renderSeq += 1
    const seq: number = this.renderSeq
    this.resetWebFailure()
    const prepared: PreparedMathRender = this.preparedRender()
    if (prepared.input.renderMode === 'plainFallback') {
      this.renderReady = true
      this.setWebHeight(this.clampHeight(this.estimateHeight(prepared.input.normalizedText)), false)
      return
    }
    const cached: MathRenderCacheEntry | null = cacheGet(prepared.cacheKey, this.metricSurface)
    if (cached !== null) {
      this.setWebHeight(this.clampHeight(cached.height), true)
    } else {
      this.setWebHeight(this.estimateHeight(prepared.markdown), false)
    }
    this.admitWebCreate(seq, prepared.cacheKey)
  }

  aboutToDisappear(): void {
    this.renderSeq += 1
  }

  onTextChanged(): void {
    this.renderSeq += 1
    this.heightApplied = false
    this.formulaVisibleReported = false
    const seq: number = this.renderSeq
    this.resetWebFailure()
    const prepared: PreparedMathRender = this.preparedRender()
    if (prepared.input.renderMode === 'plainFallback') {
      this.lastAppliedKey = ''
      this.renderReady = true
      this.setWebHeight(this.clampHeight(this.estimateHeight(prepared.input.normalizedText)), false)
      return
    }
    const cached: MathRenderCacheEntry | null = cacheGet(prepared.cacheKey, this.metricSurface)
    if (cached !== null) {
      this.setWebHeight(this.clampHeight(cached.height), true)
      if (this.pageReady) {
        this.renderReady = true
        this.applyCachedRender(prepared, cached)
      } else {
        this.admitWebCreate(seq, prepared.cacheKey)
      }
      return
    }
    this.setWebHeight(this.estimateHeight(prepared.markdown), false)
    if (this.pageReady) {
      this.renderReady = true
      this.renderContent()
    } else {
      this.admitWebCreate(seq, prepared.cacheKey)
    }
  }

  private renderContent = (): void => {
    const prepared: PreparedMathRender = this.preparedRender()
    if (prepared.input.renderMode === 'plainFallback') {
      return
    }
    if (prepared.cacheKey === this.lastAppliedKey) {
      return
    }
    const cached: MathRenderCacheEntry | null = cacheGet(prepared.cacheKey, this.metricSurface)
    if (cached !== null) {
      this.setWebHeight(this.clampHeight(cached.height), true)
      this.applyCachedRender(prepared, cached)
      return
    }
    this.enqueueWebWork('cold|' + prepared.cacheKey,
      (complete: MathRenderWorkComplete): void => this.runPreparedRender(prepared, complete))
  }

  private runPreparedRender = (prepared: PreparedMathRender, complete: MathRenderWorkComplete): void => {
    const markdown: string = prepared.markdown
    const cacheKey: string = prepared.cacheKey
    const script: string = buildNormalizedMathRenderScript(prepared, this.profile, this.forceDisplay)
    this.setWebHeight(this.estimateHeight(markdown), false)
    ChatRenderBenchmarkStats.recordWebCreate()
    ChatRenderBenchmarkStats.recordWebWorkStart()
    this.recordNoteDetailWebWorkStart()
    const startedAt: number = Date.now()
    this.controller.runJavaScript(script)
      .then((heightText: string): void => {
        if (this.isCurrentWebWork(cacheKey)) {
          const payload: MathRenderPayload = this.parseRenderPayload(heightText)
          if (this.acceptRenderedHeight(payload.height)) {
            const height: number = this.clampHeight(payload.height + 2)
            this.setWebHeight(height, true)
            this.lastAppliedKey = cacheKey
            if (payload.encodedHtml.length > 0) {
              cacheSet(cacheKey, payload.encodedHtml, height)
            }
          }
        }
        complete(Date.now() - startedAt)
      })
      .catch((): void => {
        // renderForCache 因 bridge 返回值超限被 reject (公式多时 encodeURIComponent(innerHTML) 过大)
        // → 降级为 render() 只返高度数字, 自适应设备实际 bridge 上限, 无需硬编码阈值
        if (this.isCurrentWebWork(cacheKey)) {
          ChatRenderBenchmarkStats.recordDegradation()
          this.recordNoteDetailDegradation()
          this.enqueueWebWork('height-fallback|' + cacheKey,
            (fallbackComplete: MathRenderWorkComplete): void => this.runHeightFallback(prepared, fallbackComplete))
        }
        complete(Date.now() - startedAt)
      })
  }

  private runHeightFallback = (prepared: PreparedMathRender, complete: MathRenderWorkComplete): void => {
    const fallbackFn: string = this.forceDisplay ? 'renderFormula' : 'render'
    const fallbackScript: string = fallbackFn + '(' + JSON.stringify(prepared.markdown)
      + ',' + JSON.stringify(this.profile) + ')'
    ChatRenderBenchmarkStats.recordWebWorkStart()
    this.recordNoteDetailWebWorkStart()
    const startedAt: number = Date.now()
    this.controller.runJavaScript(fallbackScript)
      .then((heightText: string): void => {
        if (this.isCurrentWebWork(prepared.cacheKey)) {
          const parsedHeight: number = this.parseRenderedHeight(heightText)
          if (this.acceptRenderedHeight(parsedHeight)) {
            const height: number = this.clampHeight(parsedHeight + 2)
            this.setWebHeight(height, true)
            this.lastAppliedKey = prepared.cacheKey
          }
        }
        complete(Date.now() - startedAt)
      })
      .catch((): void => {
        if (this.isCurrentWebWork(prepared.cacheKey)) {
          ChatRenderBenchmarkStats.recordDegradation()
          this.recordNoteDetailDegradation()
          this.activateBridgeFallback()
        }
        complete(Date.now() - startedAt)
      })
  }

  private applyCachedRender = (prepared: PreparedMathRender, cached: MathRenderCacheEntry): void => {
    this.enqueueWebWork('cache|' + prepared.cacheKey,
      (complete: MathRenderWorkComplete): void => this.runCachedRender(prepared, cached, complete))
  }

  private runCachedRender = (prepared: PreparedMathRender, cached: MathRenderCacheEntry,
    complete: MathRenderWorkComplete): void => {
    const cacheKey: string = prepared.cacheKey
    const script: string = 'applyCached(' + JSON.stringify(cached.encodedHtml) + ',' + JSON.stringify(this.profile) + ')'
    this.recordNoteDetailWebWorkStart()
    const startedAt: number = Date.now()
    this.controller.runJavaScript(script)
      .then((heightText: string): void => {
        if (this.isCurrentWebWork(cacheKey)) {
          const parsed: number = this.parseRenderedHeight(heightText)
          if (this.acceptRenderedHeight(parsed)) {
            const height: number = this.clampHeight(parsed + 2)
            this.setWebHeight(height, true)
            cached.height = height
            this.lastAppliedKey = cacheKey
          }
        }
        complete(Date.now() - startedAt)
      })
      .catch((): void => {
        // 缓存 HTML 作为 bridge 输入也可能超限 → 降级为 renderForCache 重新渲染
        if (this.isCurrentWebWork(cacheKey)) {
          ChatRenderBenchmarkStats.recordDegradation()
          this.recordNoteDetailDegradation()
          this.enqueueWebWork('cache-retry|' + cacheKey,
            (retryComplete: MathRenderWorkComplete): void => this.runCacheRetry(prepared, retryComplete))
        }
        complete(Date.now() - startedAt)
      })
  }

  private runCacheRetry = (prepared: PreparedMathRender, complete: MathRenderWorkComplete): void => {
    // Retry exactly the normalized MM-MD-v1 input that produced the cache key.
    const retryScript: string = buildNormalizedMathRenderScript(prepared, this.profile, this.forceDisplay)
    ChatRenderBenchmarkStats.recordWebWorkStart()
    this.recordNoteDetailWebWorkStart()
    const startedAt: number = Date.now()
    this.controller.runJavaScript(retryScript)
      .then((heightText: string): void => {
        if (this.isCurrentWebWork(prepared.cacheKey)) {
          const payload: MathRenderPayload = this.parseRenderPayload(heightText)
          if (this.acceptRenderedHeight(payload.height)) {
            this.setWebHeight(this.clampHeight(payload.height + 2), true)
            this.lastAppliedKey = prepared.cacheKey
          }
        }
        complete(Date.now() - startedAt)
      })
      .catch((): void => {
        if (this.isCurrentWebWork(prepared.cacheKey)) {
          ChatRenderBenchmarkStats.recordDegradation()
          this.recordNoteDetailDegradation()
          this.activateBridgeFallback()
        }
        complete(Date.now() - startedAt)
      })
  }

  private parseRenderedHeight = (heightText: string): number => {
    let raw: string = heightText.trim()
    if (raw.startsWith('"') && raw.endsWith('"') && raw.length >= 2) {
      raw = raw.substring(1, raw.length - 1)
    }
    return Number(raw)
  }

  private parseRenderPayload = (payloadText: string): MathRenderPayload => {
    const payload: MathRenderPayload = new MathRenderPayload()
    const raw: string = this.unwrapJavaScriptString(payloadText)
    const splitIndex: number = raw.indexOf('\n')
    if (splitIndex < 0) {
      payload.height = Number(raw.trim())
      return payload
    }
    payload.height = Number(raw.substring(0, splitIndex).trim())
    payload.encodedHtml = raw.substring(splitIndex + 1)
    return payload
  }

  private unwrapJavaScriptString = (value: string): string => {
    let raw: string = value.trim()
    if (raw.startsWith('"') && raw.endsWith('"') && raw.length >= 2) {
      raw = raw.substring(1, raw.length - 1)
      raw = raw.replace(/\\n/g, '\n')
      raw = raw.replace(/\\"/g, '"')
      raw = raw.replace(/\\\\/g, '\\')
    }
    return raw
  }

  private cacheKey = (markdown: string): string => {
    return this.profile + '|' + MATH_RENDER_PROTOCOL_VERSION + '|' + MATH_RENDER_CACHE_KEY_VERSION
      + '|' + (this.forceDisplay ? '1' : '0') + '|' + contentHash(markdown)
  }

  private currentCacheKey = (): string => {
    const prepared: PreparedMathRender = this.preparedRender()
    if (prepared.input.renderMode === 'plainFallback') {
      return ''
    }
    return prepared.cacheKey
  }

  private isCurrentWebWork = (cacheKey: string): boolean => {
    return !this.failureState.shouldUsePlainFallback() && cacheKey === this.currentCacheKey()
  }

  private clampHeight = (height: number): number => {
    if (this.forceDisplay) {
      // 公式块: 仅保下限, 不设上限 (单个 display 公式不会超过 1800vp)
      return Math.max(this.minHeight, height)
    }
    // 文本块: 上限 1800vp, 超过时通过 overflow-y:auto 内部滚动
    return Math.min(1800, Math.max(this.minHeight, height))
  }

  private setWebHeight = (height: number, applied: boolean): void => {
    ChatRenderBenchmarkStats.recordHeightUpdate()
    if (this.metricSurface === 'noteDetail') {
      NoteDetailRenderMetrics.recordHeightUpdate()
    }
    this.webHeight = height
    this.heightApplied = applied
    if (applied) {
      ChatRenderBenchmarkStats.recordHeightApplied()
      if (this.metricSurface === 'noteDetail') {
        NoteDetailRenderMetrics.recordHeightApplied()
        this.reportFormulaVisibleIfReady()
      }
    }
  }

  private onVisibleAreaChanged = (isVisible: boolean, currentRatio: number): void => {
    this.visibleInViewport = isVisible && currentRatio > 0
    this.reportFormulaVisibleIfReady()
  }

  private reportFormulaVisibleIfReady = (): void => {
    if (this.metricSurface !== 'noteDetail' || !this.forceDisplay || this.formulaVisibleReported
      || !this.heightApplied || !this.visibleInViewport) {
      return
    }
    this.formulaVisibleReported = true
    NoteDetailRenderMetrics.recordFormulaVisible()
  }

  private recordNoteDetailWebCreate = (): void => {
    if (this.metricSurface === 'noteDetail') {
      NoteDetailRenderMetrics.recordWebCreate()
    }
  }

  private recordNoteDetailWebWorkStart = (): void => {
    if (this.metricSurface === 'noteDetail') {
      NoteDetailRenderMetrics.recordWebWorkStart()
    }
  }

  private recordNoteDetailDegradation = (): void => {
    if (this.metricSurface === 'noteDetail') {
      NoteDetailRenderMetrics.recordDegradation()
    }
  }

  private recordNoteDetailRenderExit = (event: OnRenderExitedEvent): void => {
    if (this.metricSurface === 'noteDetail') {
      NoteDetailRenderMetrics.recordRenderExit(event ? event.renderExitReason : -1)
    }
    this.failureState.recordFailure()
    this.webFailed = this.failureState.shouldUsePlainFallback()
    this.lastAppliedKey = ''
    this.pageReady = false
  }

  private resetWebFailure = (): void => {
    this.failureState.reset()
    this.webFailed = false
  }

  private acceptRenderedHeight = (height: number): boolean => {
    const accepted: boolean = this.failureState.acceptHeight(height)
    this.webFailed = this.failureState.shouldUsePlainFallback()
    if (!accepted) {
      this.lastAppliedKey = ''
    }
    return accepted
  }

  private activateBridgeFallback = (): void => {
    this.failureState.recordFailure()
    this.webFailed = this.failureState.shouldUsePlainFallback()
    this.lastAppliedKey = ''
  }

  private normalizeForRender = (raw: string): MathRenderInput => {
    const normalized: string = raw.replace(/\r\n/g, '\n').replace(/\r/g, '\n').trim()
    const input: MathRenderInput = new MathRenderInput()
    const protocolResult: ContentValidationResult = this.forceDisplay
      ? this.contentProtocol.normalizeDisplayFormula(normalized)
      : this.contentProtocol.normalizeNoteMarkdown(normalized)
    input.fallbackText = protocolResult.normalizedText.length > 0
      ? protocolResult.normalizedText
      : normalized
    if (protocolResult.fallbackRequired) {
      input.normalizedText = input.fallbackText
      input.renderMode = 'plainFallback'
      return input
    }
    const riskResult: LatexRiskResult = this.riskNormalizer.normalize(protocolResult.normalizedText)
    input.normalizedText = riskResult.normalizedText
    input.renderMode = riskResult.renderMode
    if (riskResult.renderMode === 'plainFallback') {
      input.fallbackText = riskResult.normalizedText.length > 0
        ? riskResult.normalizedText
        : input.fallbackText
    }
    return input
  }

  private prepareMarkdownFromResult = (renderInput: MathRenderInput): string => {
    const normalized: string = renderInput.normalizedText.trim()
    if (normalized.length === 0) {
      return ''
    }
    return normalized
  }

  private plainFallbackText = (): string => {
    const prepared: PreparedMathRender = this.preparedRender()
    const fallback: string = prepared.input.fallbackText.trim()
    return fallback.length > 0 ? fallback : this.text.trim()
  }

  private preparedRender = (): PreparedMathRender => {
    const key: string = buildMathRenderPreparationKey(this.text, this.profile, this.forceDisplay,
      MATH_RENDER_PROTOCOL_VERSION, MATH_RENDER_CACHE_KEY_VERSION)
    return this.preparationMemo.resolve(key, (): PreparedMathRender => {
      const input: MathRenderInput = this.normalizeForRender(this.text)
      const prepared: PreparedMathRender = new PreparedMathRender()
      prepared.input = input
      prepared.markdown = this.prepareMarkdownFromResult(input)
      if (input.renderMode !== 'plainFallback') {
        prepared.cacheKey = this.cacheKey(prepared.markdown)
      }
      return prepared
    })
  }

  private admitWebCreate = (seq: number, cacheKey: string): void => {
    if (this.renderBudget === null) {
      this.renderReady = true
      return
    }
    this.renderReady = false
    this.pageReady = false
    this.renderBudget.enqueueWebCreate('web|' + cacheKey + '|' + seq.toString(), this.renderPriority, (): void => {
      if (seq !== this.renderSeq) {
        return
      }
      this.renderReady = true
    })
  }

  private enqueueWebWork = (key: string, run: MathRenderWork): void => {
    if (this.renderBudget === null) {
      run((_workDurationMs: number): void => {})
      return
    }
    const seq: number = this.renderSeq
    this.renderBudget.enqueueWebWork(key + '|' + seq.toString(), this.renderPriority,
      (complete: MathRenderWorkComplete): void => {
        if (seq === this.renderSeq) {
          run(complete)
        } else {
          complete(0)
        }
      })
  }

  private estimateHeight = (preparedMarkdown: string): number => {
    const normalized: string = preparedMarkdown.replace(/\r\n/g, '\n').trim()
    if (normalized.length === 0) {
      return 1
    }
    const charsPerLine: number = this.profile === 'note' ? 24 : 20
    const baseLineHeight: number = this.profile === 'note' ? 28 : 22
    let lineCount: number = 0
    for (const line of normalized.split('\n')) {
      const visualLines: number = Math.max(1, Math.ceil(line.length / charsPerLine))
      lineCount += visualLines
    }
    const displayFormulaCount: number = Math.floor((normalized.split('$$').length - 1) / 2)
      + Math.floor((normalized.split('\\[').length - 1))
    const formulaExtra: number = displayFormulaCount * (this.profile === 'note' ? DISPLAY_FORMULA_HEIGHT_NOTE : DISPLAY_FORMULA_HEIGHT_CHAT)
    // 文本部分 ×1.2 缓冲 (markdown 块级边距/padding),
    // 公式部分用精确值估算 (chat 58vp, note 66vp, 对应 KaTeX display 实际 50-80vp 中位),
    // 分离后文本不会过度估算,公式不会低估,整体跳变幅度更小
    const textEstimated: number = (lineCount * baseLineHeight + 18) * TEXT_HEIGHT_BUFFER_RATIO
    const estimated: number = textEstimated + formulaExtra
    return this.clampHeight(estimated)
  }

  build() {
    if (this.preparedRender().input.renderMode === 'plainFallback' || this.webFailed) {
      Text(this.plainFallbackText())
        .fontSize(this.fontSize)
        .fontColor(this.textColor)
        .lineHeight(this.lineHeight)
        .width('100%')
        .textAlign(TextAlign.Start)
    } else if (!this.renderReady) {
      Text(this.plainFallbackText())
        .fontSize(this.fontSize)
        .fontColor(this.textColor)
        .lineHeight(this.lineHeight)
        .width('100%')
        .textAlign(TextAlign.Start)
    } else {
      Web({ src: $rawfile('render.html'), controller: this.controller })
        .javaScriptAccess(true)
        .domStorageAccess(false)
        .fileAccess(false)
        .horizontalScrollBarAccess(true)
        .verticalScrollBarAccess(true)
        .backgroundColor('rgba(0,0,0,0)')
        .width('100%')
        .height(this.webHeight)
        .onVisibleAreaChange([0.0, 1.0], (isVisible: boolean, currentRatio: number): void => {
          this.onVisibleAreaChanged(isVisible, currentRatio)
        })
        .onAppear((): void => this.recordNoteDetailWebCreate())
        .onPageEnd((): void => {
          this.pageReady = true
          this.renderContent()
        })
        .onRenderExited((event: OnRenderExitedEvent): void => this.recordNoteDetailRenderExit(event))
    }
  }
}
