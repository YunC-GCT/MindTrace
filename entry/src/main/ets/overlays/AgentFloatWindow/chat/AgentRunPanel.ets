/**
 * AgentRunPanel.ets - AI 单次运行的有序步骤路由
 *
 * 路径: overlays/AgentFloatWindow/chat/AgentRunPanel.ets
 * 职责: 按事件顺序把每个 Part 交给独立展示卡片,不持有共享过程容器或总开关
 * 依赖: AgentRunModels, AgentThinkingStep, AgentToolStep, AgentStatusStep, AgentAnswerStep
 *
 * 数据流:
 *   AgentRunPart[] -> AgentRunPanel -> independent step renderers
 */

import { S_2 } from 'common'
import { AgentRunPart, agentRunPartKey } from './AgentRunModels'
import { AgentThinkingStep } from './AgentThinkingStep'
import { AgentToolStep } from './AgentToolStep'
import { AgentStatusStep } from './AgentStatusStep'
import { AgentAnswerStep } from './AgentAnswerStep'

@Component
export struct AgentRunPanel {
  @Prop parts: AgentRunPart[] = []
  @Prop streaming: boolean = false

  build() {
    Column({ space: S_2 }) {
      if (this.hasProcessParts()) {
        ForEach(this.parts,
          (part: AgentRunPart): void => {
            if (part.kind === 'thinking') {
              AgentThinkingStep({ content: part.content, status: part.status })
            } else if (part.kind === 'tool') {
              AgentToolStep({
                toolName: part.toolName === undefined ? '' : part.toolName,
                status: part.status,
                result: part.content,
                detail: part.detail === undefined ? '' : part.detail,
              })
            } else if (part.kind !== 'answer') {
              AgentStatusStep({ kind: part.kind, status: part.status, content: part.content })
            }
          },
          (part: AgentRunPart): string => agentRunPartKey(part)
        )
      }

      ForEach(this.parts,
        (part: AgentRunPart): void => {
          if (part.kind === 'answer') {
            AgentAnswerStep({
              content: part.content,
              streaming: this.streaming && part.status === 'running',
            })
          }
        },
        (part: AgentRunPart): string => agentRunPartKey(part)
      )
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private hasProcessParts = (): boolean => {
    return this.parts.some((part: AgentRunPart): boolean => part.kind !== 'answer')
  }
}
