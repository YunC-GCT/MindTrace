/**
 * AgentStatusStep.ets - Agent 运行过程中的状态或错误卡片
 *
 * 路径: overlays/AgentFloatWindow/chat/AgentStatusStep.ets
 * 职责: 用独立轻量卡片为 workflow 生命周期和结构化错误提供统一展示位
 * 依赖: common UI tokens, AgentRunModels
 *
 * 数据流:
 *   AgentRunPart(status/error) -> AgentStatusStep -> status card
 */

import { BORDER, DANGER, F_XS, MINT, R_MD, S_1, S_2, S_3, TEXT_3, TEXT_4, W_SEMIBOLD } from 'common'
import { AgentRunPartKind, AgentRunPartStatus } from './AgentRunModels'

@Component
export struct AgentStatusStep {
  @Prop kind: AgentRunPartKind = 'status'
  @Prop status: AgentRunPartStatus = 'success'
  @Prop content: string = ''

  build() {
    Row() {
      if (this.status === 'running') {
        LoadingProgress()
          .width(14)
          .height(14)
          .color(MINT)
          .margin({ right: S_1 })
        Marquee({
          start: true,
          step: 2,
          loop: -1,
          fromStart: true,
          src: this.content,
        })
          .fontSize(F_XS)
          .fontColor(TEXT_4)
          .fontWeight(W_SEMIBOLD)
          .height(18)
          .layoutWeight(1)
          .marqueeUpdateStrategy(MarqueeUpdateStrategy.PRESERVE_POSITION)
      } else {
        Text(this.content)
          .fontSize(F_XS)
          .fontColor(this.kind === 'error' || this.status === 'failed' ? DANGER : TEXT_3)
          .fontWeight(W_SEMIBOLD)
          .lineHeight(17)
          .layoutWeight(1)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: S_3, right: S_3, top: S_2, bottom: S_2 })
    .borderRadius(R_MD + 4)
    .backgroundColor('rgba(255,255,255,0.025)')
    .border({ width: 0.5, color: BORDER })
  }
}
