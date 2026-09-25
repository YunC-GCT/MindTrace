/**
 * AiMessageBubble.ets - AI 消息展示入口
 *
 * 路径: overlays/AgentFloatWindow/chat/AiMessageBubble.ets
 * 职责: 渲染 AI 标识并把有序运行步骤交给独立步骤路由
 * 依赖: common UI tokens, AgentRunModels, AgentRunPanel
 *
 * 数据流:
 *   ChatBubble props -> AiMessageBubble -> AgentRunPanel
 */

import { MINT, S_1, S_2, TEXT_4, W_SEMIBOLD } from 'common'
import { AgentRunPart } from './AgentRunModels'
import { AgentRunPanel } from './AgentRunPanel'
import { ChatMessageOutcome } from './ChatModels'

@Component
export struct AiMessageBubble {
  @Prop parts: AgentRunPart[] = []
  @Prop streaming: boolean = false
  @Prop outcome: ChatMessageOutcome = 'completed'

  build() {
    Row() {
      Column() {
        Row() {
          Text('MindTrace AI')
            .fontSize(10)
            .fontColor(MINT)
            .fontWeight(W_SEMIBOLD)
          if (this.streaming) {
            Text('正在处理')
              .fontSize(9)
              .fontColor(TEXT_4)
              .margin({ left: S_1 })
          } else if (this.outcome !== 'completed') {
            Text(this.outcomeLabel())
              .fontSize(9)
              .fontColor(TEXT_4)
              .margin({ left: S_1 })
          }
        }
        .margin({ bottom: S_1, left: S_1 })

        AgentRunPanel({
          parts: this.parts,
          streaming: this.streaming,
        })
      }
      .alignItems(HorizontalAlign.Start)
      Blank()
    }
    .width('100%')
    .margin({ top: S_2 })
  }

  private outcomeLabel = (): string => {
    if (this.outcome === 'cancelled') { return '已取消' }
    if (this.outcome === 'interrupted') { return '已中断' }
    if (this.outcome === 'failed') { return '失败' }
    return ''
  }
}
