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
import { NoteEvidenceCitation } from '../../../models/NoteEvidenceModels'
import { NoteReviewFeedback } from '../../../models/NoteReviewModels'

@Component
export struct ChatBubble {
  @Prop msg: ChatMsg = { id: 0, role: 'ai', content: '', ts: 0, streaming: false, reasoning: '' }
  onSourceTap: (citation: NoteEvidenceCitation) => void = (_citation: NoteEvidenceCitation): void => {}
  onFeedback: (messageId: number, feedback: NoteReviewFeedback) => void =
    (_messageId: number, _feedback: NoteReviewFeedback): void => {}
  onTopicSelect: (messageId: number, runId: string, topicId: string) => void =
    (_messageId: number, _runId: string, _topicId: string): void => {}

  build() {
    if (this.msg.role === 'user') {
      UserMessageBubble({ content: this.msg.content })
    } else {
      AiMessageBubble({
        parts: chatMessageRunParts(this.msg),
        streaming: this.msg.streaming,
        outcome: this.msg.outcome ?? 'completed',
        noteReview: this.msg.noteReview === undefined ? null : this.msg.noteReview,
        noteContextClarification: this.msg.noteContextClarification === undefined
          ? null : this.msg.noteContextClarification,
        onSourceTap: this.onSourceTap,
        onFeedback: (feedback: NoteReviewFeedback): void => { this.onFeedback(this.msg.id, feedback) },
        onTopicSelect: (runId: string, topicId: string): void => {
          this.onTopicSelect(this.msg.id, runId, topicId)
        },
      })
    }
  }
}
