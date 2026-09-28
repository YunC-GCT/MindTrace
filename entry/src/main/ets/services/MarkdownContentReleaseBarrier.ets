/**
 * MarkdownContentReleaseBarrier.ets — Markdown 异步内容单元完成屏障
 *
 * 路径: entry/src/main/ets/services/MarkdownContentReleaseBarrier.ets
 * 职责: 允许同组公式并行准备，并阻止后续 Markdown 块越过尚未就绪的内容。
 * 依赖: 无
 *
 * 数据流:
 *   Markdown 单元放行 → waitFor → 公式完成 → complete → 下一块放行
 *
 * ArkTS 1.1 strict 适配:
 *   - 使用显式 string/boolean 类型，不使用 any/unknown。
 */

export class MarkdownContentReleaseBarrier {
  private pendingKeys: string[] = []
  private deferred: boolean = false

  waitFor(key: string): void {
    if (this.pendingKeys.indexOf(key) < 0) {
      this.pendingKeys.push(key)
    }
  }

  deferNextBlock(): boolean {
    if (this.pendingKeys.length === 0) {
      return false
    }
    this.deferred = true
    return true
  }

  complete(key: string): boolean {
    const index: number = this.pendingKeys.indexOf(key)
    if (index >= 0) {
      this.pendingKeys.splice(index, 1)
    }
    const shouldContinue: boolean = this.deferred && this.pendingKeys.length === 0
    if (shouldContinue) {
      this.deferred = false
    }
    return shouldContinue
  }

  reset(): void {
    this.pendingKeys.splice(0, this.pendingKeys.length)
    this.deferred = false
  }
}
