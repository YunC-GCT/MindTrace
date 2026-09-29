/**
 * DetailRenderSession.ets — 实例级笔记详情渲染会话
 *
 * 路径: entry/src/main/ets/overlays/NoteDetailOverlay/components/DetailRenderSession.ets
 * 职责: 按详情实例隔离任务队列、优先级、帧预算、generation、取消与已释放任务。
 * 依赖: common NoteItem/KnowledgeUnit, NoteDetailRenderMetrics, MathRenderBudget, ArkTS setTimeout
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
import type {
  MathRenderBudget,
  MathRenderCreateWork,
  MathRenderWork,
  MathRenderWorkComplete,
} from '../../../services/MathRenderBudget'

export const DETAIL_RENDER_PRIORITY_VISIBLE_TEXT: number = 0
export const DETAIL_RENDER_PRIORITY_VISIBLE_FORMULA: number = 5
export const DETAIL_RENDER_PRIORITY_NEAR_VIEWPORT: number = 10
export const DETAIL_RENDER_PRIORITY_OFFSCREEN_TEXT: number = 20
export const DETAIL_RENDER_PRIORITY_OFFSCREEN_FORMULA: number = 25
export const DETAIL_RENDER_PRIORITY_META: number = 30
export const DETAIL_RENDER_MAX_WEB_CREATES_IN_FLIGHT: number = 5
export const DETAIL_RENDER_MAX_WEB_CREATES_PER_ADMISSION: number = 3
export const DETAIL_RENDER_WEB_CREATE_ADMISSION_MS: number = 16
export const DETAIL_RENDER_MAX_WEB_WORK_MS_PER_FRAME: number = 16

const DETAIL_RENDER_FRAME_DELAY_MS: number = 16
const DETAIL_RENDER_MAX_PENDING: number = 80

export interface DetailRenderTimer {
  schedule(run: () => void, delayMs: number): void
}

export class DetailContentRenderGuard {
  private renderKey: string = ''
  private pending: boolean = false

  shouldEnqueue(key: string, contentReady: boolean): boolean {
    if (key === this.renderKey && (contentReady || this.pending)) {
      return false
    }
    this.renderKey = key
    this.pending = true
    return true
  }

  settle(): void {
    this.pending = false
  }

  interrupt(): void {
    this.pending = false
  }
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

class DetailWebRenderJob {
  key: string = ''
  kind: 'create' | 'work' = 'create'
  priority: number = DETAIL_RENDER_PRIORITY_NEAR_VIEWPORT
  sequence: number = 0
  generation: number = 0
  run: MathRenderWork = (_complete: MathRenderWorkComplete): void => {}

  constructor(key: string, kind: 'create' | 'work', priority: number,
    sequence: number, generation: number, run: MathRenderWork) {
    this.key = key
    this.kind = kind
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

export class DetailRenderSession implements MathRenderBudget {
  private jobs: DetailRenderJob[] = []
  private webJobs: DetailWebRenderJob[] = []
  private completedKeys: string[] = []
  private sequence: number = 0
  private sessionGeneration: number = 0
  private activeKey: string = ''
  private timerActive: boolean = false
  private webTimerActive: boolean = false
  private webFlushActive: boolean = false
  private webWorkInFlight: boolean = false
  private webCreatesInFlight: number = 0
  private webWorkToken: number = 0
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

  enqueueWebCreate(key: string, priority: number, run: MathRenderCreateWork): void {
    this.enqueueWeb(key, 'create', priority, (complete: MathRenderWorkComplete): void => {
      run((): void => complete(0))
    })
  }

  enqueueWebWork(key: string, priority: number, run: MathRenderWork): void {
    this.enqueueWeb(key, 'work', priority, run)
  }

  enqueueContent(key: string, priority: number, run: () => void): void {
    this.enqueue('content|' + key, priority, run)
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

  private invalidatePending(): void {
    this.sessionGeneration += 1
    this.jobs.splice(0, this.jobs.length)
    this.webJobs.splice(0, this.webJobs.length)
    this.completedKeys.splice(0, this.completedKeys.length)
    this.timerActive = false
    this.webTimerActive = false
    this.webFlushActive = false
    this.webWorkInFlight = false
    this.webCreatesInFlight = 0
    this.webWorkToken += 1
  }

  private enqueueWeb = (key: string, kind: 'create' | 'work', priority: number, run: MathRenderWork): void => {
    if (this.cancelled) {
      return
    }
    if (this.activeKey.length === 0) {
      run((_workDurationMs: number): void => {})
      return
    }
    this.sequence += 1
    this.webJobs.push(new DetailWebRenderJob(
      kind + '|' + key, kind, priority, this.sequence, this.sessionGeneration, run))
    this.scheduleWebNext()
  }

  private scheduleWebNext = (delayMs: number = DETAIL_RENDER_WEB_CREATE_ADMISSION_MS): void => {
    if (this.webTimerActive || this.webFlushActive || this.webWorkInFlight
      || this.cancelled || !this.hasAdmissibleWebJob()) {
      return
    }
    const generation: number = this.sessionGeneration
    this.webTimerActive = true
    this.timer.schedule((): void => {
      if (generation !== this.sessionGeneration || this.cancelled) {
        return
      }
      this.webTimerActive = false
      this.flushWebJobs(generation, 0, 0)
    }, delayMs)
  }

  private flushWebJobs = (generation: number, initialCreateCount: number, initialWorkMs: number): void => {
    let createCount: number = initialCreateCount
    this.webFlushActive = true
    let job: DetailWebRenderJob | null = this.takeNextAdmissibleWebJob(initialWorkMs)
    while (job !== null) {
      if (job.generation === generation && generation === this.sessionGeneration) {
        if (job.kind === 'create') {
          this.runWebCreate(job, generation)
          createCount += 1
          if (createCount >= DETAIL_RENDER_MAX_WEB_CREATES_PER_ADMISSION) {
            this.webFlushActive = false
            this.scheduleWebNext()
            return
          }
        } else {
          this.webFlushActive = false
          this.runWebWork(job, generation, createCount, initialWorkMs)
          return
        }
      }
      job = this.takeNextAdmissibleWebJob(initialWorkMs)
    }
    this.webFlushActive = false
    this.scheduleWebNext()
  }

  private runWebCreate = (job: DetailWebRenderJob, generation: number): void => {
    this.webCreatesInFlight += 1
    let completionHandled: boolean = false
    const complete: MathRenderWorkComplete = (_workDurationMs: number): void => {
      if (completionHandled) {
        return
      }
      completionHandled = true
      if (generation !== this.sessionGeneration || this.cancelled) {
        return
      }
      if (this.webCreatesInFlight > 0) {
        this.webCreatesInFlight -= 1
      }
      this.scheduleWebNext(DETAIL_RENDER_WEB_CREATE_ADMISSION_MS)
    }
    try {
      job.run(complete)
    } catch (_error) {
      complete(0)
    }
  }

  private runWebWork = (job: DetailWebRenderJob, generation: number,
    createCount: number, workMs: number): void => {
    this.webWorkInFlight = true
    this.webWorkToken += 1
    const token: number = this.webWorkToken
    let completionHandled: boolean = false
    const complete: MathRenderWorkComplete = (workDurationMs: number): void => {
      if (completionHandled) {
        return
      }
      completionHandled = true
      if (token !== this.webWorkToken || generation !== this.sessionGeneration || this.cancelled) {
        return
      }
      this.webWorkInFlight = false
      const safeDurationMs: number = workDurationMs > 0 ? workDurationMs : 0
      const accumulatedWorkMs: number = workMs + safeDurationMs
      if (accumulatedWorkMs >= DETAIL_RENDER_MAX_WEB_WORK_MS_PER_FRAME) {
        this.scheduleWebNext()
        return
      }
      this.flushWebJobs(generation, createCount, accumulatedWorkMs)
    }
    try {
      job.run(complete)
    } catch (_error) {
      complete(DETAIL_RENDER_MAX_WEB_WORK_MS_PER_FRAME)
    }
  }

  private takeNextAdmissibleWebJob = (workMs: number): DetailWebRenderJob | null => {
    let bestIndex: number = -1
    let index: number = 0
    while (index < this.webJobs.length) {
      const current: DetailWebRenderJob = this.webJobs[index]
      const createAllowed: boolean = current.kind !== 'create'
        || this.webCreatesInFlight < DETAIL_RENDER_MAX_WEB_CREATES_IN_FLIGHT
      const workAllowed: boolean = current.kind !== 'work'
        || workMs < DETAIL_RENDER_MAX_WEB_WORK_MS_PER_FRAME
      if (createAllowed && workAllowed) {
        if (bestIndex < 0) {
          bestIndex = index
        } else {
          const best: DetailWebRenderJob = this.webJobs[bestIndex]
          const readyWorkBeforeCreate: boolean = current.priority === best.priority
            && current.kind === 'work' && best.kind === 'create'
          const sameKindEarlier: boolean = current.priority === best.priority
            && current.kind === best.kind && current.sequence < best.sequence
          if (current.priority < best.priority
            || readyWorkBeforeCreate || sameKindEarlier) {
            bestIndex = index
          }
        }
      }
      index += 1
    }
    if (bestIndex < 0) {
      return null
    }
    const job: DetailWebRenderJob = this.webJobs[bestIndex]
    this.webJobs.splice(bestIndex, 1)
    return job
  }

  private hasAdmissibleWebJob(): boolean {
    let index: number = 0
    while (index < this.webJobs.length) {
      const job: DetailWebRenderJob = this.webJobs[index]
      if (job.kind === 'work' || this.webCreatesInFlight < DETAIL_RENDER_MAX_WEB_CREATES_IN_FLIGHT) {
        return true
      }
      index += 1
    }
    return false
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
    }, DETAIL_RENDER_FRAME_DELAY_MS)
  }

  private flushJobs(generation: number): void {
    const job: DetailRenderJob | null = this.takeNextJob()
    if (job !== null && job.generation === generation && generation === this.sessionGeneration) {
      job.run()
      if (generation === this.sessionGeneration && this.completedKeys.indexOf(job.key) < 0) {
        this.completedKeys.push(job.key)
      }
    }
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
