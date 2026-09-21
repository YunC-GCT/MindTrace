/**
 * AgentThinkingStep.ets - 独立的 Agent 思考展示模块
 *
 * 路径: overlays/AgentFloatWindow/chat/AgentThinkingStep.ets
 * 职责: 默认折叠思考;进行中滚动最新小字,结束后显示开头摘要,并仅展开自身详情
 * 依赖: common UI tokens, AgentRunModels
 *
 * 数据流:
 *   AgentRunPart(thinking) -> AgentThinkingStep -> collapsed summary/full detail
 */

import { DUR_FAST, F_XS, MINT, S_1, TEXT_3, TEXT_4, W_SEMIBOLD } from 'common'
import { AgentRunPartStatus } from './AgentRunModels'

const THINKING_SUMMARY_LIMIT: number = 42
const THINKING_RUNNING_WINDOW: number = 88

@Component
export struct AgentThinkingStep {
  @Prop content: string = ''
  @Prop status: AgentRunPartStatus = 'success'
  @State detailOpen: boolean = false

  build() {
    Column() {
      Row() {
        Text(this.status === 'running' ? '思考中' : '已深度思考')
          .fontSize(F_XS)
          .fontColor(this.status === 'running' ? MINT : TEXT_3)
          .fontWeight(W_SEMIBOLD)
          .margin({ right: S_1 })
        if (!this.detailOpen) {
          if (this.status === 'running') {
            Marquee({
              start: true,
              step: 2,
              loop: -1,
              fromStart: true,
              src: this.runningLine(),
            })
              .fontSize(10)
              .fontColor(TEXT_4)
              .layoutWeight(1)
              .height(18)
              .marqueeUpdateStrategy(MarqueeUpdateStrategy.PRESERVE_POSITION)
          } else {
            Text(this.completedSummary())
              .fontSize(10)
              .fontColor(TEXT_4)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
      }
      .width('100%')
      .height(20)
      .padding({ left: S_1, right: S_1 })
      .onClick((): void => { this.toggleDetail() })

      if (this.detailOpen) {
        Text(this.content)
          .fontSize(F_XS)
          .fontColor(TEXT_3)
          .fontStyle(FontStyle.Italic)
          .lineHeight(17)
          .width('100%')
          .textAlign(TextAlign.Start)
          .margin({ top: S_1 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: S_1, right: S_1, bottom: S_1 })
  }

  private toggleDetail = (): void => {
    this.getUIContext().animateTo(
      { duration: DUR_FAST, curve: Curve.FastOutSlowIn },
      (): void => { this.detailOpen = !this.detailOpen },
    )
  }

  private runningLine = (): string => {
    const normalized: string = this.normalizedContent()
    if (normalized.length <= THINKING_RUNNING_WINDOW) {
      return normalized
    }
    return '…' + normalized.substring(normalized.length - THINKING_RUNNING_WINDOW + 1)
  }

  private completedSummary = (): string => {
    const normalized: string = this.normalizedContent()
    if (normalized.length <= THINKING_SUMMARY_LIMIT) {
      return normalized
    }
    return normalized.substring(0, THINKING_SUMMARY_LIMIT) + '…'
  }

  private normalizedContent = (): string => {
    return this.content.split('\n').join(' ').trim()
  }
}
