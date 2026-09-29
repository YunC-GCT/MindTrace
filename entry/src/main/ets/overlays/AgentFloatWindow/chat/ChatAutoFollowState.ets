/**
 * ChatAutoFollowState.ets — 对话列表流式自动跟随状态
 *
 * 路径: entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatAutoFollowState.ets
 * 职责: 根据用户滚动意图决定流式消息是否可以继续贴底。
 * 依赖: 无。
 *
 * 数据流:
 *   列表滚动开始/停止 → ChatAutoFollowState → 流式进度滚动许可
 */

export class ChatAutoFollowState {
  private followStreamProgress: boolean = true

  onUserScrollStart(): void {
    this.followStreamProgress = false
  }

  onScrollStop(isAtBottom: boolean): void {
    this.followStreamProgress = isAtBottom
  }

  shouldFollowStreamProgress(): boolean {
    return this.followStreamProgress
  }
}
