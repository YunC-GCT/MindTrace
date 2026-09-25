/**
 * ChatModels.ets — AI 浮窗共享消息模型与纯函数
 *
 * 路径: entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatModels.ets
 * 职责: 定义 ChatMsg/ChatSession，并提供消息 key、明确的内存/持久化复制契约和流事件 reducer。
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
import {
  AgentRunPart,
  agentRunRevision,
  applyStreamEventToAgentRun,
  copyAgentRunParts,
  finishAgentRun,
  projectLegacyAgentRun,
} from './AgentRunModels'

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

  // 旧思考面板展开态;保留用于历史会话兼容
  reasoningExpanded?: boolean

  // AI 单次运行的有序步骤;旧会话缺失时由 reasoning/content 即时投影
  runParts?: AgentRunPart[]

}

export function chatItemKey(message: ChatMsg): string {
  const idPart: string = message.id.toString()
  const contentLengthPart: string = '_contentLength' + message.content.length.toString()
  const reasoningLengthPart: string = '_reasoningLength' + chatMessageReasoning(message).length.toString()
  const streamingPart: string = message.streaming ? '_streaming1' : '_streaming0'
  const runPart: string = '_run' + agentRunRevision(chatMessageRunParts(message))
  return idPart + contentLengthPart + reasoningLengthPart + streamingPart + runPart
}

export function chatMessageReasoning(message: ChatMsg): string {
  return message.reasoning ?? ''
}

/**
 * Copy contract for an active conversation. This is the full in-memory working
 * copy and therefore retains UI interaction state such as reasoningExpanded.
 */
export function copyChatMsgForMemory(message: ChatMsg): ChatMsg {
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
  if (message.runParts !== undefined) {
    next.runParts = copyAgentRunParts(message.runParts)
  }
  return next
}

export function chatMessageRunParts(message: ChatMsg): AgentRunPart[] {
  if (message.runParts !== undefined) {
    return message.runParts
  }
  return projectLegacyAgentRun(message.id, chatMessageReasoning(message), message.content, message.streaming)
}

/**
 * Copy contract for file/Worker transfer. The result is pure history data and
 * deliberately excludes reasoningExpanded, which is UI-only state.
 */
export function copyChatMsgForPersistence(message: ChatMsg): ChatMsg {
  const next: ChatMsg = {
    id: message.id,
    role: message.role,
    content: message.content,
    ts: message.ts,
    streaming: message.streaming,
  }
  if (message.reasoning !== undefined) {
    next.reasoning = message.reasoning
  }
  return next
}

export function copyChatMsg(message: ChatMsg): ChatMsg {
  return copyChatMsgForMemory(message)
}

export function applyStreamEventToChatMsg(message: ChatMsg, event: StreamEvent): ChatMsg {
  const next: ChatMsg = copyChatMsgForMemory(message)
  next.runParts = applyStreamEventToAgentRun(chatMessageRunParts(message), event, message.id)
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

export function replaceChatMsgContent(message: ChatMsg, content: string): ChatMsg {
  const next: ChatMsg = copyChatMsgForMemory(message)
  next.content = content

  const sourceParts: AgentRunPart[] = copyAgentRunParts(chatMessageRunParts(message))
  const answerIndexes: number[] = []
  let sourceIndex: number = 0
  while (sourceIndex < sourceParts.length) {
    if (sourceParts[sourceIndex].kind === 'answer') {
      answerIndexes.push(sourceIndex)
    }
    sourceIndex += 1
  }

  if (answerIndexes.length === 0) {
    next.runParts = content.length > 0
      ? applyStreamEventToAgentRun(sourceParts, { type: 'text', delta: content }, message.id)
      : sourceParts
    return next
  }

  const lastAnswerIndex: number = answerIndexes[answerIndexes.length - 1]
  const nextParts: AgentRunPart[] = []
  sourceIndex = 0
  while (sourceIndex < sourceParts.length) {
    if (sourceParts[sourceIndex].kind !== 'answer' || sourceIndex === lastAnswerIndex) {
      if (sourceIndex === lastAnswerIndex) {
        sourceParts[sourceIndex].content = content
      }
      nextParts.push(sourceParts[sourceIndex])
    }
    sourceIndex += 1
  }
  next.runParts = nextParts
  return next
}

export function finishChatMsg(message: ChatMsg): ChatMsg {
  const next: ChatMsg = copyChatMsg(message)
  next.streaming = false
  next.runParts = finishAgentRun(chatMessageRunParts(message))
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

export function copyChatSessionForMemory(session: ChatSession): ChatSession {
  const messages: ChatMsg[] = []
  for (const message of session.messages) {
    messages.push(copyChatMsgForMemory(message))
  }
  return {
    id: session.id,
    name: session.name,
    messages: messages,
  }
}

export function copyChatSessionForPersistence(session: ChatSession): ChatSession {
  const messages: ChatMsg[] = []
  for (const message of session.messages) {
    messages.push(copyChatMsgForPersistence(message))
  }
  return {
    id: session.id,
    name: session.name,
    messages: messages,
  }
}

export function copyChatSessionsForMemory(sessions: ChatSession[]): ChatSession[] {
  const copied: ChatSession[] = []
  for (const session of sessions) {
    copied.push(copyChatSessionForMemory(session))
  }
  return copied
}

export function copyChatSessionsForPersistence(sessions: ChatSession[]): ChatSession[] {
  const copied: ChatSession[] = []
  for (const session of sessions) {
    copied.push(copyChatSessionForPersistence(session))
  }
  return copied
}
