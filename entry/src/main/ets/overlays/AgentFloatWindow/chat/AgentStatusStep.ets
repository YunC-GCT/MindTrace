/**
 * AgentStatusStep.ets - Agent 运行时间线中的状态或错误步骤
 *
 * 路径: overlays/AgentFloatWindow/chat/AgentStatusStep.ets
 * 职责: 为后续 workflow 生命周期和结构化错误提供统一展示位
 * 依赖: common UI tokens, AgentRunModels
 *
 * 数据流:
 *   AgentRunPart(status/error) -> AgentStatusStep -> timeline row
 */

import { DANGER, F_XS, MINT, S_1, S_2, TEXT_3, W_SEMIBOLD } from 'common'
import { AgentRunPartKind, AgentRunPartStatus } from './AgentRunModels'

@Component
export struct AgentStatusStep {
  @Prop kind: AgentRunPartKind = 'status'
  @Prop status: AgentRunPartStatus = 'success'
  @Prop content: string = ''

  build() {
    Row() {
      Circle({ width: 6, height: 6 })
        .fill(this.stepColor())
        .margin({ right: S_2 })
      Text(this.content)
        .fontSize(F_XS)
        .fontColor(this.kind === 'error' || this.status === 'failed' ? DANGER : TEXT_3)
        .fontWeight(W_SEMIBOLD)
        .lineHeight(17)
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: S_1, right: S_2, top: S_1, bottom: S_2 })
  }

  private stepColor = (): string => {
    if (this.kind === 'error' || this.status === 'failed') { return DANGER }
    return this.status === 'running' || this.status === 'pending' ? MINT : TEXT_3
  }
}
