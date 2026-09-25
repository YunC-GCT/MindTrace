/**
 * AgentRunModels.ets - AI 单次运行的有序展示模型与纯 reducer
 *
 * 路径: overlays/AgentFloatWindow/chat/AgentRunModels.ets
 * 职责: 将 thinking/text/tool_call/tool_result 归并为可持久化的有序运行步骤
 * 依赖: common StreamEvent
 *
 * 数据流:
 *   StreamEvent -> applyStreamEventToAgentRun -> AgentRunPart[] -> AgentRunPanel
 *
 * 兼容策略: 旧会话没有 runParts 时由 reasoning/content 即时投影,不改写历史数据。
 */

import type { StreamEvent, StreamToolCallEvent, StreamToolResultEvent } from 'common'

export type AgentRunPartKind = 'thinking' | 'tool' | 'answer' | 'status' | 'error'
export type AgentRunPartStatus = 'pending' | 'running' | 'success' | 'failed'

export interface AgentRunPart {
  id: string
  sequence: number
  kind: AgentRunPartKind
  status: AgentRunPartStatus
  content: string
  toolCallId?: string
  toolName?: string
  detail?: string
}

function copyAgentRunPart(part: AgentRunPart): AgentRunPart {
  const next: AgentRunPart = {
    id: part.id,
    sequence: part.sequence,
    kind: part.kind,
    status: part.status,
    content: part.content,
  }
  if (part.toolCallId !== undefined) {
    next.toolCallId = part.toolCallId
  }
  if (part.toolName !== undefined) {
    next.toolName = part.toolName
  }
  if (part.detail !== undefined) {
    next.detail = part.detail
  }
  return next
}

export function copyAgentRunParts(parts: AgentRunPart[]): AgentRunPart[] {
  return parts.map((part: AgentRunPart): AgentRunPart => copyAgentRunPart(part))
}

export function projectLegacyAgentRun(
  messageId: number,
  reasoning: string,
  content: string,
  streaming: boolean,
): AgentRunPart[] {
  const parts: AgentRunPart[] = []
  if (reasoning.length > 0) {
    parts.push(createPart(messageId, parts.length, 'thinking', streaming ? 'running' : 'success', reasoning))
  }
  if (content.length > 0) {
    closeRunningParts(parts)
    parts.push(createPart(messageId, parts.length, 'answer', streaming ? 'running' : 'success', content))
  }
  return parts
}

export function applyStreamEventToAgentRun(
  current: AgentRunPart[],
  event: StreamEvent,
  messageId: number,
): AgentRunPart[] {
  const next: AgentRunPart[] = copyAgentRunParts(current)
  if (event.type === 'thinking') {
    appendTextPart(next, messageId, 'thinking', event.delta)
    return next
  }
  if (event.type === 'text') {
    appendTextPart(next, messageId, 'answer', event.delta)
    return next
  }
  if (event.type === 'tool_call') {
    applyToolCall(next, event, messageId)
    return next
  }
  applyToolResult(next, event, messageId)
  return next
}

export function finishAgentRun(parts: AgentRunPart[]): AgentRunPart[] {
  const next: AgentRunPart[] = copyAgentRunParts(parts)
  for (const part of next) {
    if (part.status !== 'running' && part.status !== 'pending') {
      continue
    }
    if (part.kind === 'tool') {
      part.status = 'failed'
      if (part.detail === undefined || part.detail.length === 0) {
        part.detail = '工具调用结束前未返回结果'
      }
    } else {
      part.status = 'success'
    }
  }
  return next
}

export function appendAgentRunStatus(
  current: AgentRunPart[],
  messageId: number,
  content: string,
  status: AgentRunPartStatus,
): AgentRunPart[] {
  const next: AgentRunPart[] = copyAgentRunParts(current)
  closeRunningParts(next)
  next.push(createPart(messageId, next.length, 'status', status, content))
  return next
}

export function appendAgentRunError(
  current: AgentRunPart[],
  messageId: number,
  content: string,
): AgentRunPart[] {
  const next: AgentRunPart[] = copyAgentRunParts(current)
  closeRunningParts(next)
  next.push(createPart(messageId, next.length, 'error', 'failed', content))
  return next
}

export function agentRunPartKey(part: AgentRunPart): string {
  return part.id + '_' + part.status + '_' + part.content.length.toString()
    + '_' + (part.detail === undefined ? '0' : part.detail.length.toString())
}

export function agentRunRevision(parts: AgentRunPart[]): string {
  const revisions: string[] = []
  for (const part of parts) {
    revisions.push(agentRunPartKey(part))
  }
  return revisions.join('|')
}

function createPart(
  messageId: number,
  sequence: number,
  kind: AgentRunPartKind,
  status: AgentRunPartStatus,
  content: string,
): AgentRunPart {
  const part: AgentRunPart = {
    id: messageId.toString() + '_part_' + sequence.toString(),
    sequence: sequence,
    kind: kind,
    status: status,
    content: content,
  }
  return part
}

function appendTextPart(
  parts: AgentRunPart[],
  messageId: number,
  kind: 'thinking' | 'answer',
  delta: string,
): void {
  const last: AgentRunPart | undefined = parts.length > 0 ? parts[parts.length - 1] : undefined
  if (last !== undefined && last.kind === kind && last.status === 'running') {
    last.content += delta
    return
  }
  closeRunningParts(parts)
  parts.push(createPart(messageId, parts.length, kind, 'running', delta))
}

function applyToolCall(
  parts: AgentRunPart[],
  event: StreamToolCallEvent,
  messageId: number,
): void {
  const callId: string = resolveToolCallId(parts, event.toolCallId, messageId)
  const existingIndex: number = findToolPartIndex(parts, callId)
  if (existingIndex >= 0) {
    const existing: AgentRunPart = parts[existingIndex]
    existing.status = 'running'
    if (event.toolName !== undefined && event.toolName.length > 0) {
      existing.toolName = event.toolName
    }
    if (event.argumentsJson !== undefined) {
      existing.detail = event.argumentsJson
    } else if (event.delta.length > 0) {
      existing.detail = (existing.detail === undefined ? '' : existing.detail) + event.delta
    }
    return
  }
  closeRunningParts(parts)
  const part: AgentRunPart = createPart(messageId, parts.length, 'tool', 'running', '')
  part.toolCallId = callId
  if (event.toolName !== undefined) {
    part.toolName = event.toolName
  }
  if (event.argumentsJson !== undefined) {
    part.detail = event.argumentsJson
  } else if (event.delta.length > 0) {
    part.detail = event.delta
  }
  parts.push(part)
}

function applyToolResult(
  parts: AgentRunPart[],
  event: StreamToolResultEvent,
  messageId: number,
): void {
  const callId: string = resolveToolCallId(parts, event.toolCallId, messageId)
  let partIndex: number = findToolPartIndex(parts, callId)
  if (partIndex < 0) {
    closeRunningParts(parts)
    const orphan: AgentRunPart = createPart(messageId, parts.length, 'tool', 'running', '')
    orphan.toolCallId = callId
    parts.push(orphan)
    partIndex = parts.length - 1
  }
  const part: AgentRunPart = parts[partIndex]
  if (event.toolName !== undefined && event.toolName.length > 0) {
    part.toolName = event.toolName
  }
  if (event.result !== undefined) {
    part.content = event.result
  } else if (event.delta.length > 0) {
    part.content += event.delta
  }
  part.status = event.ok === false ? 'failed' : 'success'
}

function resolveToolCallId(parts: AgentRunPart[], value: string | undefined, messageId: number): string {
  if (value !== undefined && value.length > 0) {
    return value
  }
  const last: AgentRunPart | undefined = parts.length > 0 ? parts[parts.length - 1] : undefined
  if (last !== undefined && last.kind === 'tool' && last.status === 'running' && last.toolCallId !== undefined) {
    return last.toolCallId
  }
  return messageId.toString() + '_tool_' + parts.length.toString()
}

function findToolPartIndex(parts: AgentRunPart[], toolCallId: string): number {
  let index: number = 0
  while (index < parts.length) {
    if (parts[index].kind === 'tool' && parts[index].toolCallId === toolCallId) {
      return index
    }
    index += 1
  }
  return -1
}

function closeRunningParts(parts: AgentRunPart[]): void {
  for (const part of parts) {
    if (part.status === 'running' && part.kind !== 'tool') {
      part.status = 'success'
    }
  }
}
