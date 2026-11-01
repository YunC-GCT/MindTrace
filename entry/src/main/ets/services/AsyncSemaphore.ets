/**
 * AsyncSemaphore.ets — 异步信号量（调度 lane 并发上限，纯逻辑）
 *
 * 路径: entry/src/main/ets/services/AsyncSemaphore.ets
 * 职责: acquire/release 控制并发；等待者 FIFO 唤醒（spec 038 T2）。
 */
export class AsyncSemaphore {
  private readonly capacity: number;
  private active: number = 0;
  private waiters: Array<() => void> = [];

  constructor(capacity: number) {
    this.capacity = capacity > 0 ? capacity : 1;
  }

  available(): number {
    return this.capacity - this.active;
  }

  acquire(): Promise<void> {
    if (this.active < this.capacity) {
      this.active += 1;
      return Promise.resolve();
    }
    return new Promise<void>((resolve: () => void): void => {
      this.waiters.push((): void => {
        this.active += 1;
        resolve();
      });
    });
  }

  release(): void {
    if (this.active > 0) {
      this.active -= 1;
    }
    const next: (() => void) | undefined = this.waiters.shift();
    if (next !== undefined) {
      next();
    }
  }
}
