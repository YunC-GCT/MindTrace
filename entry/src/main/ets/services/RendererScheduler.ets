/**
 * RendererScheduler.ets — 通用块级 Web 渲染任务调度器
 *
 * 路径: entry/src/main/ets/services/RendererScheduler.ets
 * 职责: 接收纯数据渲染任务，按视口优先级和冻结预算派发 Web 工作。
 * 依赖: 无外部模块；实际 Web 工作由 RenderTaskRunner 注入。
 *
 * 数据流:
 *   RenderTask → RendererScheduler → RenderTaskRunner → BlockHeightChangedHandler
 *
 * ArkTS 1.1 strict 适配:
 *   - 使用显式接口和任务快照，避免结构化推断与异步回调持有可变输入。
 */

export interface RenderTask {
  blockId: string;
  rawFormulaText: string;
  slotHint: string;
  estimateHeight: number;
  distanceToViewportScreens: number;
}

export interface RenderTaskCompletion {
  blockId: string;
  height: number;
  workDurationMs: number;
}

export type RenderTaskCompletionHandler = (completion: RenderTaskCompletion) => void;

export interface RenderTaskRunner {
  render(task: RenderTask, complete: RenderTaskCompletionHandler): void;
}

export type BlockHeightChangedHandler = (blockId: string, height: number) => void;

export type RenderPendingHandler = () => void;

export const DEFAULT_MAX_WEB_CREATES_PER_FRAME: number = 1;
export const DEFAULT_MAX_WEB_WORK_MS_PER_FRAME: number = 16;
export const MAX_NEARBY_VIEWPORT_DISTANCE_SCREENS: number = 1;

class QueuedRenderTask {
  task: RenderTask;
  sequence: number;

  constructor(task: RenderTask, sequence: number) {
    this.task = task;
    this.sequence = sequence;
  }
}

export class RendererScheduler {
  private readonly runner: RenderTaskRunner;
  private readonly onBlockHeightChanged: BlockHeightChangedHandler;
  private readonly onPendingWork: RenderPendingHandler;
  private readonly maxWebCreatesPerFrame: number;
  private readonly maxWebWorkMsPerFrame: number;
  private readonly pendingTasks: QueuedRenderTask[] = [];
  private readonly inFlightTokens: Map<string, number> = new Map<string, number>();
  private nextSequence: number = 0;
  private nextToken: number = 0;
  private disposed: boolean = false;

  constructor(runner: RenderTaskRunner, onBlockHeightChanged: BlockHeightChangedHandler,
    maxWebCreatesPerFrame: number = DEFAULT_MAX_WEB_CREATES_PER_FRAME,
    maxWebWorkMsPerFrame: number = DEFAULT_MAX_WEB_WORK_MS_PER_FRAME,
    onPendingWork: RenderPendingHandler = (): void => {}) {
    this.runner = runner;
    this.onBlockHeightChanged = onBlockHeightChanged;
    this.onPendingWork = onPendingWork;
    this.maxWebCreatesPerFrame = RendererScheduler.normalizeBudget(
      maxWebCreatesPerFrame, DEFAULT_MAX_WEB_CREATES_PER_FRAME);
    this.maxWebWorkMsPerFrame = RendererScheduler.normalizeBudget(
      maxWebWorkMsPerFrame, DEFAULT_MAX_WEB_WORK_MS_PER_FRAME);
  }

  enqueue(task: RenderTask): void {
    if (this.disposed) {
      return;
    }
    this.removePendingTask(task.blockId);
    this.inFlightTokens.delete(task.blockId);
    this.nextSequence += 1;
    this.pendingTasks.push(new QueuedRenderTask(RendererScheduler.copyTask(task), this.nextSequence));
  }

  updateViewportDistance(blockId: string, distanceToViewportScreens: number): void {
    if (this.disposed) {
      return;
    }
    for (const queuedTask of this.pendingTasks) {
      if (queuedTask.task.blockId === blockId) {
        queuedTask.task.distanceToViewportScreens = distanceToViewportScreens;
      }
    }
  }

  dispatchPending(): boolean {
    if (this.disposed) {
      return false;
    }
    if (this.inFlightTokens.size > 0) {
      return true;
    }
    let webCreates: number = 0;
    let webWorkMs: number = 0;
    let stopFrame: boolean = false;
    while (!stopFrame && webCreates < this.maxWebCreatesPerFrame) {
      const queuedTask: QueuedRenderTask | undefined = this.takeNextEligibleTask();
      if (queuedTask === undefined) {
        break;
      }
      const token: number = this.nextToken + 1;
      this.nextToken = token;
      this.inFlightTokens.set(queuedTask.task.blockId, token);
      webCreates += 1;
      let completionHandled: boolean = false;
      const complete: RenderTaskCompletionHandler = (completion: RenderTaskCompletion): void => {
        if (completionHandled) {
          return;
        }
        completionHandled = true;
        const currentToken: number | undefined = this.inFlightTokens.get(queuedTask.task.blockId);
        if (currentToken === undefined || currentToken !== token) {
          return;
        }
        this.inFlightTokens.delete(queuedTask.task.blockId);
        if (completion.blockId !== queuedTask.task.blockId) {
          return;
        }
        this.onBlockHeightChanged(completion.blockId, completion.height);
        const safeWorkDurationMs: number = completion.workDurationMs > 0 ? completion.workDurationMs : 0;
        webWorkMs += safeWorkDurationMs;
        if (webWorkMs >= this.maxWebWorkMsPerFrame) {
          stopFrame = true;
        }
        if (!this.disposed && this.hasEligiblePending()) {
          this.onPendingWork();
        }
      };
      this.runner.render(queuedTask.task, complete);
      if (this.inFlightTokens.size > 0) {
        break;
      }
    }
    return this.inFlightTokens.size > 0 || this.hasEligiblePending();
  }

  hasPending(): boolean {
    return this.pendingTasks.length > 0 || this.inFlightTokens.size > 0;
  }

  hasEligiblePending(): boolean {
    if (this.disposed) {
      return false;
    }
    for (const queuedTask of this.pendingTasks) {
      if (RendererScheduler.taskTier(queuedTask.task) < 2) {
        return true;
      }
    }
    return false;
  }

  pendingCount(): number {
    return this.pendingTasks.length;
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.pendingTasks.splice(0, this.pendingTasks.length);
    this.inFlightTokens.clear();
  }

  isDisposed(): boolean {
    return this.disposed;
  }

  private static normalizeBudget(value: number, fallback: number): number {
    const normalized: number = Math.floor(value);
    return normalized > 0 ? normalized : fallback;
  }

  private static copyTask(task: RenderTask): RenderTask {
    return {
      blockId: task.blockId,
      rawFormulaText: task.rawFormulaText,
      slotHint: task.slotHint,
      estimateHeight: task.estimateHeight,
      distanceToViewportScreens: task.distanceToViewportScreens,
    };
  }

  private removePendingTask(blockId: string): void {
    let index: number = this.pendingTasks.length - 1;
    while (index >= 0) {
      if (this.pendingTasks[index].task.blockId === blockId) {
        this.pendingTasks.splice(index, 1);
      }
      index -= 1;
    }
  }

  private takeNextEligibleTask(): QueuedRenderTask | undefined {
    let bestIndex: number = -1;
    let index: number = 0;
    while (index < this.pendingTasks.length) {
      const candidate: QueuedRenderTask = this.pendingTasks[index];
      if (RendererScheduler.taskTier(candidate.task) < 2
        && (bestIndex < 0 || this.isHigherPriority(candidate, this.pendingTasks[bestIndex]))) {
        bestIndex = index;
      }
      index += 1;
    }
    if (bestIndex < 0) {
      return undefined;
    }
    const selected: QueuedRenderTask = this.pendingTasks[bestIndex];
    this.pendingTasks.splice(bestIndex, 1);
    return selected;
  }

  private isHigherPriority(candidate: QueuedRenderTask, current: QueuedRenderTask): boolean {
    const candidateTier: number = RendererScheduler.taskTier(candidate.task);
    const currentTier: number = RendererScheduler.taskTier(current.task);
    if (candidateTier !== currentTier) {
      return candidateTier < currentTier;
    }
    if (candidate.task.distanceToViewportScreens !== current.task.distanceToViewportScreens) {
      return candidate.task.distanceToViewportScreens < current.task.distanceToViewportScreens;
    }
    return candidate.sequence < current.sequence;
  }

  private static taskTier(task: RenderTask): number {
    if (task.distanceToViewportScreens <= 0) {
      return 0;
    }
    if (task.distanceToViewportScreens <= MAX_NEARBY_VIEWPORT_DISTANCE_SCREENS) {
      return 1;
    }
    return 2;
  }
}
