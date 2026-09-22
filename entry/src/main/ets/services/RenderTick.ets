/**
 * RenderTick.ets — 按需驱动浮窗渲染阶段的实例级 50ms 节拍器
 *
 * 路径: entry/src/main/ets/services/RenderTick.ets
 * 职责: 管理 pending 节拍、显示状态、订阅者有效性和销毁生命周期。
 * 依赖: HarmonyOS setInterval/clearInterval；阶段回调由浮窗实例注入。
 *
 * 数据流:
 *   pending → delayed RenderTick → data → geometry → scroll
 *
 * ArkTS 1.1 strict 适配:
 *   - 通过 RenderTickTimer 注入可重复测试的定时器，不创建第二个全局节拍器。
 */

export interface RenderTickTimer {
  start(callback: () => void, intervalMs: number): number;
  stop(timerId: number): void;
}

export interface RenderTickPhaseHandlers {
  isSubscriberActive(): boolean;
  updatePendingState(): void;
  notifyData(): void;
  notifyGeometry(): void;
  handleScroll(): void;
  disconnectSubscriber(): void;
}

export interface RenderTickOptions {
  developmentGuard: boolean;
}

export const TICK_MS: number = 50;
export const RELEASE_RENDER_TICK_OPTIONS: RenderTickOptions = { developmentGuard: false };

class PlatformRenderTickTimer implements RenderTickTimer {
  start(callback: () => void, intervalMs: number): number {
    return setInterval(callback, intervalMs);
  }

  stop(timerId: number): void {
    clearInterval(timerId);
  }
}

export class RenderTick {
  private static activeInstanceCount: number = 0;
  private readonly timer: RenderTickTimer;
  private readonly handlers: RenderTickPhaseHandlers;
  private timerId: number = -1;
  private pending: boolean = false;
  private shown: boolean = true;
  private disposed: boolean = false;
  constructor(handlers: RenderTickPhaseHandlers, timer: RenderTickTimer = new PlatformRenderTickTimer(),
    options: RenderTickOptions = RELEASE_RENDER_TICK_OPTIONS) {
    this.handlers = handlers;
    this.timer = timer;
    if (RenderTick.activeInstanceCount > 0) {
      throw new Error('Only one RenderTick instance is supported');
    }
    RenderTick.activeInstanceCount += 1;
  }

  requestTick(): void {
    if (this.disposed) {
      return;
    }
    this.pending = true;
    this.ensureStarted();
  }

  setShow(show: boolean): void {
    if (this.disposed || this.shown === show) {
      return;
    }
    if (!show) {
      this.flushPendingForSubscriber();
      this.shown = false;
      this.stopTimer();
      return;
    }
    this.shown = true;
    this.ensureStarted();
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.pending = false;
    this.stopTimer();
    this.handlers.disconnectSubscriber();
    RenderTick.activeInstanceCount -= 1;
  }

  isRunning(): boolean {
    return this.timerId >= 0;
  }

  isDisposed(): boolean {
    return this.disposed;
  }

  hasPending(): boolean {
    return this.pending;
  }

  private ensureStarted(): void {
    if (this.disposed || !this.shown || !this.pending || this.timerId >= 0) {
      return;
    }
    this.timerId = this.timer.start((): void => { this.onTimer(); }, TICK_MS);
  }

  private stopTimer(): void {
    if (this.timerId < 0) {
      return;
    }
    const timerId: number = this.timerId;
    this.timerId = -1;
    this.timer.stop(timerId);
  }

  private onTimer(): void {
    if (this.disposed || !this.shown) {
      this.stopTimer();
      return;
    }
    if (!this.pending) {
      this.stopTimer();
      return;
    }
    this.processPending();
    if (!this.pending) {
      this.stopTimer();
    }
  }

  private flushPendingForSubscriber(): void {
    if (this.pending) {
      this.processPending();
    }
  }

  private processPending(): void {
    this.pending = false;
    if (!this.handlers.isSubscriberActive()) {
      this.handlers.updatePendingState();
      return;
    }
    this.handlers.updatePendingState();
    this.handlers.notifyData();
    this.handlers.notifyGeometry();
    this.handlers.handleScroll();
  }
}
