// ============================================================================
//  overlays/AgentFloatWindow/chat/ChatBubble.ets - message bubble
// ============================================================================

import {
  MINT,
  TEXT, TEXT_3, TEXT_4,
  S_1, S_2, S_3, R_MD, F_SM, W_SEMIBOLD, DUR_FAST,
  ContentProtocol,
} from 'common'
import { ChatMsg, chatMessageReasoning } from './ChatModels'
import { FormulaSplitRenderer } from '../../../shared/molecules/FormulaSplitRenderer'
import { MarkdownRenderer } from '../../../shared/molecules/MarkdownRenderer'

@Component
export struct ChatBubble {
  @Prop msg: ChatMsg = { id: 0, role: 'ai', content: '', ts: 0, streaming: false, reasoning: '' }
  // 展开态由组件内部持有: LazyForEach 语义下 key 不变则行不更新 (spec 019 §8),
  // 翻转仅本地驱动 UI;onToggleReasoning 回写父数组用于同步与持久化,不触发行重建。
  @State reasoningOpen: boolean = true
  onToggleReasoning: (msg: ChatMsg) => void = (_msg: ChatMsg): void => {}
  private contentProtocol: ContentProtocol = new ContentProtocol()

  aboutToAppear(): void {
    this.reasoningOpen = this.msg.reasoningExpanded !== undefined ? this.msg.reasoningExpanded : true
  }

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
            .borderRadius(R_MD + 4)
            .backgroundColor('rgba(91,227,176,0.12)')
            .border({ width: 0.5, color: 'rgba(91,227,176,0.28)' })
            .constraintSize({ maxWidth: '82%' })
          }
          .alignItems(HorizontalAlign.End)
        }
        .width('100%')
        .margin({ top: S_2 })
      } else {
        Row() {
          Column() {
            Row() {
              Text('MindTrace AI')
                .fontSize(10)
                .fontColor(MINT)
                .fontWeight(W_SEMIBOLD)
              if (this.msg.streaming) {
                Text('正在生成')
                  .fontSize(9)
                  .fontColor(TEXT_4)
                  .margin({ left: S_1 })
              }
            }
            .margin({ bottom: S_1, left: S_1 })

            // 思考过程折叠面板
            if (chatMessageReasoning(this.msg).length > 0) {
              Column() {
                Row() {
                  Row()
                    .width(3)
                    .height(14)
                    .borderRadius(2)
                    .backgroundColor(MINT)
                    .margin({ right: S_1 })
                  Button('深度思考')
                    .fontSize(11)
                    .fontColor(MINT)
                    .fontWeight(W_SEMIBOLD)
                    .backgroundColor('rgba(91,227,176,0.08)')
                    .borderRadius(S_1)
                    .padding({ left: S_1, right: S_1, top: 1, bottom: 1 })
                    .onClick((): void => { this.toggleReasoning(); })
                  Text(this.msg.streaming ? '生成中' : '已完成')
                    .fontSize(9)
                    .fontColor(TEXT_4)
                    .margin({ left: S_1 })
                }
                .width('100%')

                if (!this.reasoningVisible() && this.reasoningSummary().length > 0) {
                  Text(this.reasoningSummary())
                    .fontSize(11)
                    .fontColor(TEXT_4)
                    .lineHeight(16)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                    .margin({ top: S_1 })
                }

                if (this.reasoningVisible()) {
                  Text(chatMessageReasoning(this.msg))
                    .fontSize(11)
                    .fontColor(TEXT_3)
                    .fontStyle(FontStyle.Italic)
                    .lineHeight(17)
                    .width('100%')
                    .textAlign(TextAlign.Start)
                    .margin({ top: S_1 })
                }
              }
              .width('100%')
              .padding({ left: S_2, right: S_2, top: S_2, bottom: S_2 })
              .borderRadius(R_MD)
              .backgroundColor('rgba(255,255,255,0.035)')
              .border({ width: 0.5, color: 'rgba(91,227,176,0.18)' })
              .constraintSize({ maxWidth: '94%' })
              .margin({ bottom: S_2 })
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
            .borderRadius(R_MD + 4)
            .backgroundColor('rgba(255,255,255,0.045)')
            .border({ width: 0.5, color: 'rgba(255,255,255,0.08)' })
            .constraintSize({ maxWidth: '94%' })
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

  private reasoningVisible = (): boolean => {
    return this.reasoningOpen
  }

  private toggleReasoning = (): void => {
    this.getUIContext().animateTo(
      { duration: DUR_FAST, curve: Curve.FastOutSlowIn },
      (): void => {
        this.reasoningOpen = !this.reasoningOpen;
        this.onToggleReasoning(this.msg);
      },
    )
  }

  private reasoningSummary = (): string => {
    const normalized: string = chatMessageReasoning(this.msg).split('\n').join(' ').trim()
    if (normalized.length <= 36) {
      return normalized
    }
    return this.msg.streaming ? '…' + normalized.substring(normalized.length - 35) : normalized.substring(0, 36) + '…'
  }
}
