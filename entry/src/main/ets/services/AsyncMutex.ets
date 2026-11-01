/**
 * AsyncMutex.ets — 单进程异步互斥（写区串行化）
 *
 * 路径: entry/src/main/ets/services/AsyncMutex.ets
 * 职责: 把「写入后的索引同步 + post-commit 副作用」串行执行。S0 并发实验表明：
 *       两条 ingest 并发时笔记都能落库，但 post-commit 阶段会卡死（native 副作用不可重入）。
 *       调度器 S1 的 write lane=1 即复用同一语义。
 * 依赖: 无（纯逻辑，Node 单测可加载）。
 */
export class AsyncMutex {
  private tail: Promise<void> = Promise.resolve();

  /** 串行执行：先到先得，异常不会破坏锁（finally 释放）。 */
  async runExclusive<T>(task: () => Promise<T>): Promise<T> {
    const previous: Promise<void> = this.tail;
    let release: () => void = (): void => {};
    const current: Promise<void> = new Promise<void>((resolve: () => void): void => {
      release = resolve;
    });
    this.tail = previous.then((): Promise<void> => current);
    await previous;
    try {
      return await task();
    } finally {
      release();
    }
  }

  /** 当前是否有人在写区（调试/观测用）。 */
  isBusy(): boolean {
    return this.tail !== Promise.resolve();
  }
}
