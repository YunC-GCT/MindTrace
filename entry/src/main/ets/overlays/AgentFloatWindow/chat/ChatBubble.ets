/**
 * ChatBubble.ets - 聊天消息角色路由
 *
 * 路径: overlays/AgentFloatWindow/chat/ChatBubble.ets
 * 职责: 按消息角色选择用户或 AI 展示模块
 * 依赖: ChatModels, UserMessageBubble, AiMessageBubble
 *
 * 数据流:
 *   AgentMessageList -> ChatBubble -> UserMessageBubble/AiMessageBubble
 */

import { ChatMsg, chatMessageRunParts } from './ChatModels'
import { UserMessageBubble } from './UserMessageBubble'
import { AiMessageBubble } from './AiMessageBubble'

@Component
export struct ChatBubble {
  @Prop msg: ChatMsg = { id: 0, role: 'ai', content: '', ts: 0, streaming: false, reasoning: '' }

  build() {
    if (this.msg.role === 'user') {
      UserMessageBubble({ content: this.msg.content })
    } else {
      AiMessageBubble({
        parts: chatMessageRunParts(this.msg),
        streaming: this.msg.streaming,
      })
    }
  }
}
