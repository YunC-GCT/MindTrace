/**
 * UserMessageBubble.ets - 用户消息展示
 *
 * 路径: overlays/AgentFloatWindow/chat/UserMessageBubble.ets
 * 职责: 渲染右对齐的用户文本与公式消息
 * 依赖: common ContentProtocol, FormulaSplitRenderer
 *
 * 数据流:
 *   ChatBubble.content -> UserMessageBubble -> Text/FormulaSplitRenderer
 */

import { ContentProtocol, F_SM, R_MD, S_2, S_3, TEXT } from 'common'
import { FormulaSplitRenderer } from '../../../shared/molecules/FormulaSplitRenderer'

@Component
export struct UserMessageBubble {
  @Prop content: string = ''
  private contentProtocol: ContentProtocol = new ContentProtocol()

  build() {
    Row() {
      Blank()
      Column() {
        Column() {
          if (this.containsFormulaSyntax(this.content)) {
            FormulaSplitRenderer({
              text: this.content,
              profile: 'chatUser',
            })
            .width('100%')
          } else {
            Text(this.content)
              .fontSize(F_SM)
              .fontColor(TEXT)
              .lineHeight(20)
              .width('100%')
              .textAlign(TextAlign.Start)
          }
        }
        .width('100%')
        .padding({ left: S_3, right: S_3, top: S_2, bottom: S_2 })
        .borderRadius(R_MD + 4)
        .backgroundColor('rgba(91,227,176,0.12)')
        .border({ width: 0.5, color: 'rgba(91,227,176,0.28)' })
        .constraintSize({ maxWidth: '82%' })
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .margin({ top: S_2 })
  }

  private containsFormulaSyntax = (text: string): boolean => {
    return this.contentProtocol.hasFormulaSyntax(text)
  }
}
