/**
 * ChatAutoFollowState.test.ets — 对话列表流式自动跟随行为测试
 *
 * 路径: entry/src/test/ChatAutoFollowState.test.ets
 * 职责: 验证用户上滑暂停自动跟随、留在底部继续跟随，以及回到底部后恢复跟随。
 * 依赖: @ohos/hypium; ChatAutoFollowState.
 *
 * 数据流:
 *   用户滚动事件 → ChatAutoFollowState → 流式进度是否允许贴底
 */

import { describe, expect, it } from '@ohos/hypium'
import {
  ChatAutoFollowState,
} from '../main/ets/overlays/AgentFloatWindow/chat/ChatAutoFollowState'

export default function chatAutoFollowStateTest(): void {
  describe('ChatAutoFollowState', (): void => {
    it('should follow streamed content while the user remains at the bottom', 0, (): void => {
      const state: ChatAutoFollowState = new ChatAutoFollowState()

      expect(state.shouldFollowStreamProgress()).assertTrue()
    })

    it('should pause streamed auto-follow as soon as the user starts scrolling', 0, (): void => {
      const state: ChatAutoFollowState = new ChatAutoFollowState()

      state.onUserScrollStart()

      expect(state.shouldFollowStreamProgress()).assertFalse()
    })

    it('should remain paused when the user stops away from the bottom', 0, (): void => {
      const state: ChatAutoFollowState = new ChatAutoFollowState()
      state.onUserScrollStart()

      state.onScrollStop(false)

      expect(state.shouldFollowStreamProgress()).assertFalse()
    })

    it('should resume streamed auto-follow after the user returns to the bottom', 0, (): void => {
      const state: ChatAutoFollowState = new ChatAutoFollowState()
      state.onUserScrollStart()
      state.onScrollStop(false)

      state.onUserScrollStart()
      state.onScrollStop(true)

      expect(state.shouldFollowStreamProgress()).assertTrue()
    })
  })
}
