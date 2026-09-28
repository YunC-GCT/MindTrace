/**
 * DetailRenderSession.ets — 实例级笔记详情渲染会话
 *
 * 路径: entry/src/main/ets/overlays/NoteDetailOverlay/components/DetailRenderSession.ets
 * 职责: 按详情实例隔离任务队列、优先级、帧预算、generation、取消与已释放任务。
 * 依赖: common NoteItem/KnowledgeUnit, NoteDetailRenderMetrics surface type, ArkTS setTimeout
 *
 * 数据流:
 *   overlay identity/revision → activate → enqueue → budgeted callback release
 *
 * ArkTS 1.1 strict 适配:
 *   - 队列、timer adapter 与回调均使用显式类型。
 *   - 无模块级 mutable 调度状态。
 */

import { NoteItem, KnowledgeUnit } from 'common'
import type { NoteDetailMetricSurface } from '../../../services/NoteDetailRenderMetrics'

export const DETAIL_RENDER_PRIORITY_VISIBLE_TEXT: number = 0
export const DETAIL_RENDER_PRIORITY_VISIBLE_FORMULA: number = 5
export const DETAIL_RENDER_PRIORITY_NEAR_VIEWPORT: number = 10
export const DETAIL_RENDER_PRIORITY_OFFSCREEN_TEXT: number = 20
export const DETAIL_RENDER_PRIORITY_OFFSCREEN_FORMULA: number = 25
export const DETAIL_RENDER_PRIORITY_META: number = 30

const DETAIL_RENDER_FRAME_DELAY_MS: number = 16
const DETAIL_RENDER_FAST_DELAY_MS: number = 0
const DETAIL_RENDER_FRAME_BUDGET_MS: number = 8
const DETAIL_RENDER_PRESSURE_COUNT: number = 6
const DETAIL_RENDER_MAX_PENDING: number = 80

export interface DetailRenderTimer {
  schedule(run: () => void, delayMs: number): void
}
class SystemDetailRenderTimer implements DetailRenderTimer {
  schedule(run: () => void, delayMs: number): void {
    setTimeout(run, delayMs)
  }
}

class DetailRenderJob {
  key: string = ''
  priority: number = DETAIL_RENDER_PRIORITY_NEAR_VIEWPORT
  sequence: number = 0
  generation: number = 0
  run: () => void = (): void => {}

  constructor(key: string, priority: number, sequence: number, generation: number, run: () => void) {
    this.key = key
    this.priority = priority
    this.sequence = sequence
    this.generation = generation
    this.run = run
  }
}

function textSignature(text: string): string {
  let hash: number = 5381
  let index: number = 0
  while (index < text.length) {
    hash = ((hash << 5) + hash + text.charCodeAt(index)) | 0
    index += 1
  }
  const positive: number = hash < 0 ? -hash : hash
  return text.length.toString() + ':' + positive.toString()
}

export function buildDetailRenderSessionKey(note: NoteItem, unit: KnowledgeUnit | null): string {
  const identity: string = note.rawId.length > 0 ? note.rawId : note.id.toString()
  if (unit !== null) {
    const content: string = unit.title + '\n' + unit.summary + '\n' + unit.content
      + '\n' + unit.category + '\n' + unit.tags.join('\n')
    return identity + '|' + unit.id + '|' + unit.version.toString() + '|' + unit.updatedAt.toString()
      + '|' + textSignature(content)
  }
  const content: string = note.title + '\n' + note.body + '\n' + note.type + '\n' + note.tags.join('\n')
  return identity + '|' + note.date + '|' + textSignature(content)
}

export class DetailRenderSession {
  private jobs: DetailRenderJob[] = []
  private completedKeys: string[] = []
  private sequence: number = 0
  private sessionGeneration: number = 0
  private activeKey: string = ''
  private timerActive: boolean = false
  private cancelled: boolean = false
  private surface: NoteDetailMetricSurface
  private timer: DetailRenderTimer

  constructor(surface: NoteDetailMetricSurface = 'noteDetail',
    timer: DetailRenderTimer = new SystemDetailRenderTimer()) {
    this.surface = surface
    this.timer = timer
  }

  activate(sessionKey: string): number {
    const normalizedKey: string = sessionKey.trim()
    if (normalizedKey.length === 0) {
      this.cancel()
      return this.sessionGeneration
    }
    if (!this.cancelled && normalizedKey === this.activeKey) {
      return this.sessionGeneration
    }
    this.invalidatePending()
    this.activeKey = normalizedKey
    this.cancelled = false
    return this.sessionGeneration
  }

  cancel(): void {
    if (this.cancelled && this.activeKey.length === 0) {
      return
    }
    this.invalidatePending()
    this.activeKey = ''
    this.cancelled = true
  }

  enqueue(key: string, priority: number, run: () => void): void {
    if (this.cancelled) {
      return
    }
    if (this.activeKey.length === 0) {
      run()
      return
    }
    if (this.completedKeys.indexOf(key) >= 0) {
      run()
      return
    }
    this.sequence += 1
    this.jobs.push(new DetailRenderJob(
      key, priority, this.sequence, this.sessionGeneration, run))
    this.trimPendingJobs()
    this.scheduleNext()
  }

  isCurrent(sessionKey: string, generation: number): boolean {
    return !this.cancelled && this.activeKey === sessionKey
      && this.sessionGeneration === generation
  }

  generation(): number {
    return this.sessionGeneration
  }

  sessionKey(): string {
    return this.activeKey
  }

  scopeKey(localKey: string): string {
    return this.activeKey + '|' + this.sessionGeneration.toString() + '|' + localKey
  }

  metricSurface(): NoteDetailMetricSurface {
    return this.surface
  }

  pendingCount(): number {
    return this.jobs.length
  }

  private invalidatePending(): void {
    this.sessionGeneration += 1
    this.jobs.splice(0, this.jobs.length)
    this.completedKeys.splice(0, this.completedKeys.length)
    this.timerActive = false
  }

  private trimPendingJobs(): void {
    while (this.jobs.length > DETAIL_RENDER_MAX_PENDING) {
      this.removeLowestPriorityJob()
    }
  }

  private removeLowestPriorityJob(): void {
    if (this.jobs.length === 0) {
      return
    }
    let removeIndex: number = 0
    let index: number = 1
    while (index < this.jobs.length) {
      const current: DetailRenderJob = this.jobs[index]
      const candidate: DetailRenderJob = this.jobs[removeIndex]
      if (current.priority > candidate.priority
        || (current.priority === candidate.priority && current.sequence > candidate.sequence)) {
        removeIndex = index
      }
      index += 1
    }
    this.jobs.splice(removeIndex, 1)
  }

  private scheduleNext(): void {
    if (this.timerActive || this.jobs.length === 0 || this.cancelled) {
      return
    }
    const generation: number = this.sessionGeneration
    this.timerActive = true
    this.timer.schedule((): void => {
      if (generation !== this.sessionGeneration || this.cancelled) {
        return
      }
      this.timerActive = false
      this.flushJobs(generation)
      this.scheduleNext()
    }, this.nextDelay())
  }

  private flushJobs(generation: number): void {
    const startedAt: number = Date.now()
    let renderedCount: number = 0
    while (this.jobs.length > 0 && this.shouldContinueFlush(startedAt, renderedCount)) {
      const job: DetailRenderJob | null = this.takeNextJob()
      if (job !== null && job.generation === generation && generation === this.sessionGeneration) {
        job.run()
        if (generation === this.sessionGeneration && this.completedKeys.indexOf(job.key) < 0) {
          this.completedKeys.push(job.key)
        }
        renderedCount += 1
      }
    }
  }

  private shouldContinueFlush(startedAt: number, renderedCount: number): boolean {
    if (renderedCount === 0) {
      return true
    }
    if (this.jobs.length >= DETAIL_RENDER_PRESSURE_COUNT) {
      return Date.now() - startedAt < DETAIL_RENDER_FRAME_BUDGET_MS
    }
    return false
  }

  private nextDelay(): number {
    if (this.hasVisibleJob()) {
      return DETAIL_RENDER_FAST_DELAY_MS
    }
    return this.jobs.length >= DETAIL_RENDER_PRESSURE_COUNT
      ? DETAIL_RENDER_FAST_DELAY_MS
      : DETAIL_RENDER_FRAME_DELAY_MS
  }

  private hasVisibleJob(): boolean {
    for (const job of this.jobs) {
      if (job.priority <= DETAIL_RENDER_PRIORITY_VISIBLE_FORMULA) {
        return true
      }
    }
    return false
  }

  private takeNextJob(): DetailRenderJob | null {
    if (this.jobs.length === 0) {
      return null
    }
    let bestIndex: number = 0
    let index: number = 1
    while (index < this.jobs.length) {
      const current: DetailRenderJob = this.jobs[index]
      const best: DetailRenderJob = this.jobs[bestIndex]
      if (current.priority < best.priority
        || (current.priority === best.priority && current.sequence < best.sequence)) {
        bestIndex = index
      }
      index += 1
    }
    const job: DetailRenderJob = this.jobs[bestIndex]
    this.jobs.splice(bestIndex, 1)
    return job
  }
}
