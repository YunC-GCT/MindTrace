// ============================================================================
//  overlays/AgentFloatWindow/chat/ChatBubble.ets - message bubble
// ============================================================================

import {
  MINT, PURPLE_LIGHT,
  TEXT, TEXT_3, TEXT_4,
  S_1, S_2, S_3, R_MD, F_SM, W_SEMIBOLD,
  ContentProtocol,
} from 'common'
import { ChatMsg } from './ChatModels'
import { FormulaSplitRenderer } from '../../../shared/molecules/FormulaSplitRenderer'
import { MarkdownRenderer } from '../../../shared/molecules/MarkdownRenderer'

@Component
export struct ChatBubble {
  @Prop msg: ChatMsg = { id: 0, role: 'ai', content: '', ts: 0, streaming: false, reasoning: '' }
  onToggleReasoning: (msg: ChatMsg) => void = (_msg: ChatMsg): void => {}
  private contentProtocol: ContentProtocol = new ContentProtocol()

  build() {
    Column() {
      if (this.msg.role === 'user') {
        Row() {
          Blank()
          Column() {
            Column() {
              if (this.containsFormulaSyntax(this.msg.content)) {
                FormulaSplitRenderer({
                  text: this.msg.content,
                  profile: 'chatUser',
                })
                .width('100%')
              } else {
                Text(this.msg.content)
                  .fontSize(F_SM)
                  .fontColor(TEXT)
                  .lineHeight(20)
                  .width('100%')
                  .textAlign(TextAlign.Start)
              }
            }
            .width('100%')
            .padding({ left: S_3, right: S_3, top: S_2, bottom: S_2 })
            .borderRadius({ topLeft: R_MD + 4, topRight: R_MD + 4, bottomLeft: R_MD + 4, bottomRight: S_1 })
            .backgroundColor('rgba(31,143,101,0.82)')
            .border({ width: 0.5, color: MINT })
            .constraintSize({ maxWidth: '78%' })
          }
          .alignItems(HorizontalAlign.End)
        }
        .width('100%')
        .margin({ top: S_2 })
      } else {
        Row() {
          Column() {
            Text('AI')
              .fontSize(9)
              .fontColor(TEXT_4)
              .fontWeight(W_SEMIBOLD)
              .margin({ bottom: S_1, left: S_1 })

            // 思考过程折叠面板
            if ((this.msg.reasoning ?? '').length > 0) {
              Row() {
                Text((this.msg.reasoningExpanded ?? false) ? '▾' : '▸')
                  .fontSize(10)
                  .fontColor(MINT)
                  .fontWeight(W_SEMIBOLD)
                  .margin({ right: S_1 })
                Text('思考过程')
                  .fontSize(10)
                  .fontColor(TEXT_4)
                  .fontWeight(W_SEMIBOLD)
              }
              .padding({ left: S_2, right: S_2, top: S_1, bottom: S_1 })
              .borderRadius(S_1)
              .backgroundColor('rgba(91,227,176,0.06)')
              .margin({ bottom: S_1 })
              .onClick((): void => { this.onToggleReasoning(this.msg) })

              if ((this.msg.reasoningExpanded ?? false)) {
                Text(this.msg.reasoning)
                  .fontSize(F_SM)
                  .fontColor(TEXT_3)
                  .fontStyle(FontStyle.Italic)
                  .lineHeight(18)
                  .width('100%')
                  .padding({ left: S_2, right: S_2, top: S_1, bottom: S_1 })
                  .margin({ bottom: S_1 })
              }
            }

            Column() {
              if (this.msg.content.trim().length > 0) {
                if (this.msg.streaming) {
                  // 流式模式: 轻量 Text 直接渲染,避免每 token 做 Markdown 重解析
                  Text(this.msg.content)
                    .fontSize(F_SM)
                    .fontColor(TEXT)
                    .lineHeight(20)
                    .width('100%')
                    .textAlign(TextAlign.Start)
                } else if (this.containsFormulaSyntax(this.msg.content)) {
                  FormulaSplitRenderer({
                    text: this.msg.content,
                    profile: 'chat',
                  })
                  .width('100%')
                } else {
                  MarkdownRenderer({
                    text: this.msg.content,
                    progressive: false,
                    profile: 'chat',
                  })
                  .width('100%')
                }
              }

            }
            .width('100%')
            .padding({ left: S_3, right: S_3, top: S_2, bottom: S_2 })
            .borderRadius({ topLeft: R_MD + 4, topRight: R_MD + 4, bottomLeft: S_1, bottomRight: R_MD + 4 })
            .backgroundColor(this.msg.content.length > 240 ? 'rgba(255,255,255,0.035)' : PURPLE_LIGHT)
            .constraintSize({ maxWidth: this.msg.content.length > 240 ? '94%' : '88%' })
          }
          .alignItems(HorizontalAlign.Start)
          Blank()
        }
        .width('100%')
        .margin({ top: S_2 })
      }
    }
  }

  private containsFormulaSyntax = (text: string): boolean => {
    return this.contentProtocol.hasFormulaSyntax(text)
  }
}
