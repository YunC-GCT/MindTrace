/**
 * ChatModels.ets — AI 浮窗共享消息模型与纯函数
 *
 * 路径: entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatModels.ets
 * 职责: 定义 ChatMsg/ChatSession，并提供消息 key、复制和流事件 reducer。
 * 依赖: common StreamEvent; conversation ConversationProgressStep
 *
 * 数据流:
 *   StreamEvent → applyStreamEventToChatMsg → ChatMsg → AgentMessageList/ChatBubble
 *
 * ArkTS 1.1 strict 适配:
 *   - 旧会话缺失 reasoning 时统一通过 chatMessageReasoning 提供空字符串
 */

import { ConversationProgressStep } from '../../../workflows/conversation/ConversationState'
import type { StreamEvent } from 'common'

export interface ChatMsg {
  // 消息唯一 id(用 Date.now * 1000 + random)
  id: number

  // 角色: "user" | "ai"
  role: 'user' | 'ai'

  // 消息内容
  content: string

  // 时间戳
  ts: number

  // 是否正在流式生成中 (仅 ai 消息)
  streaming: boolean

  // 思考链内容 (DeepSeek 思考模式, 仅 ai 消息; 旧会话可能缺失)
  reasoning?: string

  // 思考面板是否展开 (仅 ai 消息, 默认收起)
  reasoningExpanded?: boolean
}

export function chatItemKey(message: ChatMsg): string {
  const idPart: string = message.id.toString()
  const contentLengthPart: string = '_contentLength' + message.content.length.toString()
  const reasoningLengthPart: string = '_reasoningLength' + chatMessageReasoning(message).length.toString()
  const streamingPart: string = message.streaming ? '_streaming1' : '_streaming0'
  return idPart + contentLengthPart + reasoningLengthPart + streamingPart
}

export function chatMessageReasoning(message: ChatMsg): string {
  return message.reasoning ?? ''
}

export function copyChatMsg(message: ChatMsg): ChatMsg {
  const next: ChatMsg = {
    id: message.id,
    role: message.role,
    content: message.content,
    ts: message.ts,
    streaming: message.streaming,
    reasoning: chatMessageReasoning(message),
  }
  if (message.reasoningExpanded !== undefined) {
    next.reasoningExpanded = message.reasoningExpanded
  }
  return next
}

export function applyStreamEventToChatMsg(message: ChatMsg, event: StreamEvent): ChatMsg {
  const next: ChatMsg = copyChatMsg(message)
  if (event.type === 'thinking') {
    next.reasoning = chatMessageReasoning(message) + event.delta
    return next
  }
  if (event.type === 'text') {
    next.content = message.content + event.delta
    return next
  }
  return next
}

export type ChatStatusStep = ConversationProgressStep

export interface ChatStatusMeta {
  step: ChatStatusStep
  title: string
  detail: string
}

export interface ChatSession {
  // 会话唯一 id(36 进制时间戳)
  id: string

  // 会话名称
  name: string

  // 该会话下的消息列表
  messages: ChatMsg[]
}
