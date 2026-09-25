/**
 * AgentAnswerStep.ets - Agent 运行时间线中的回答步骤
 *
 * 路径: overlays/AgentFloatWindow/chat/AgentAnswerStep.ets
 * 职责: 渲染流式文本以及完成后的 Markdown/公式回答
 * 依赖: common ContentProtocol, FormulaSplitRenderer, MarkdownRenderer
 *
 * 数据流:
 *   AgentRunPart(answer) -> AgentAnswerStep -> Text/Markdown/Formula
 */

import { ContentProtocol, F_SM, R_MD, S_2, S_3, TEXT } from 'common'
import { FormulaSplitRenderer } from '../../../shared/molecules/FormulaSplitRenderer'
import { MarkdownRenderer } from '../../../shared/molecules/MarkdownRenderer'

@Component
export struct AgentAnswerStep {
  @Prop content: string = ''
  @Prop streaming: boolean = false
  private contentProtocol: ContentProtocol = new ContentProtocol()

  build() {
    Column() {
      if (this.content.trim().length > 0) {
        if (this.streaming) {
          Text(this.content)
            .fontSize(F_SM)
            .fontColor(TEXT)
            .lineHeight(20)
            .width('100%')
            .textAlign(TextAlign.Start)
        } else if (this.containsFormulaSyntax(this.content)) {
          FormulaSplitRenderer({
            text: this.content,
            profile: 'chat',
          })
          .width('100%')
        } else {
          MarkdownRenderer({
            text: this.content,
            progressive: false,
            profile: 'chat',
          })
          .width('100%')
        }
      }
    }
    .width('100%')
    .padding({ left: S_3, right: S_3, top: S_2, bottom: S_2 })
    .borderRadius(R_MD + 4)
    .backgroundColor('rgba(255,255,255,0.045)')
    .border({ width: 0.5, color: 'rgba(255,255,255,0.08)' })
    .constraintSize({ maxWidth: '94%' })
  }

  private containsFormulaSyntax = (text: string): boolean => {
    return this.contentProtocol.hasFormulaSyntax(text)
  }
}
