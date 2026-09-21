/**
 * AgentRunPanel.ets - AI 单次运行的有序步骤路由
 *
 * 路径: overlays/AgentFloatWindow/chat/AgentRunPanel.ets
 * 职责: 将过程 Part 放入无总开关的视觉容器,并把每个 Part 交给独立展示模块
 * 依赖: AgentRunModels, AgentThinkingStep, AgentToolStep, AgentStatusStep, AgentAnswerStep
 *
 * 数据流:
 *   AgentRunPart[] -> AgentRunPanel -> independent step renderers
 */

import { BORDER, R_MD, S_1, S_2 } from 'common'
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
        Column({ space: S_1 }) {
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
        .width('100%')
        .padding({ left: S_1, right: S_1, top: S_2, bottom: S_2 })
        .borderRadius(R_MD)
        .backgroundColor('rgba(255,255,255,0.025)')
        .border({ width: 0.5, color: BORDER })
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
