/**
 * AgentToolStep.ets - Agent 运行时间线中的工具步骤
 *
 * 路径: overlays/AgentFloatWindow/chat/AgentToolStep.ets
 * 职责: 合并展示一次工具调用及其结果,原始详情按需展开
 * 依赖: common UI tokens, AgentRunModels
 *
 * 数据流:
 *   AgentRunPart(tool) -> AgentToolStep -> status/detail row
 */

import { DANGER, F_XS, MINT, R_MD, S_1, S_2, TEXT_2, TEXT_3, TEXT_4, W_SEMIBOLD } from 'common'
import { AgentRunPartStatus } from './AgentRunModels'

@Component
export struct AgentToolStep {
  @Prop toolName: string = ''
  @Prop status: AgentRunPartStatus = 'pending'
  @Prop result: string = ''
  @Prop detail: string = ''
  @State detailOpen: boolean = false

  build() {
    Row() {
      Column() {
        Circle({ width: 6, height: 6 })
          .fill(this.statusColor())
        Row()
          .width(1)
          .layoutWeight(1)
          .backgroundColor('rgba(255,255,255,0.10)')
      }
      .width(S_2)
      .alignItems(HorizontalAlign.Center)
      .margin({ right: S_2 })

      Column() {
        Row() {
          Text(this.displayName())
            .fontSize(F_XS)
            .fontColor(TEXT_2)
            .fontWeight(W_SEMIBOLD)
          Blank()
          Text(this.statusLabel())
            .fontSize(9)
            .fontColor(this.statusColor())
        }
        .width('100%')

        if (this.resultSummary().length > 0) {
          Text(this.resultSummary())
            .fontSize(F_XS)
            .fontColor(TEXT_3)
            .lineHeight(17)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: S_1 })
        }

        if (this.detail.length > 0 || this.result.length > 0) {
          Button(this.detailOpen ? '收起详情' : '查看详情')
            .fontSize(10)
            .fontColor(TEXT_3)
            .backgroundColor(Color.Transparent)
            .padding({ left: 0, right: S_1, top: S_1, bottom: S_1 })
            .onClick((): void => { this.detailOpen = !this.detailOpen })
        }

        if (this.detailOpen) {
          Text(this.detailText())
            .fontSize(10)
            .fontColor(TEXT_4)
            .fontFamily('monospace')
            .lineHeight(15)
            .width('100%')
            .padding({ left: S_2, right: S_2, top: S_2, bottom: S_2 })
            .borderRadius(R_MD)
            .backgroundColor('rgba(255,255,255,0.025)')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: S_1, right: S_2, top: S_1, bottom: S_2 })
  }

  private displayName = (): string => {
    if (this.toolName === 'note_query') { return '查询相关笔记' }
    if (this.toolName === 'note_get') { return '读取笔记详情' }
    if (this.toolName === 'review_due_query') { return '检查待复习内容' }
    return '调用工具'
  }

  private statusLabel = (): string => {
    if (this.status === 'running' || this.status === 'pending') { return '运行中' }
    return this.status === 'success' ? '已完成' : '失败'
  }

  private statusColor = (): string => {
    if (this.status === 'failed') { return DANGER }
    if (this.status === 'running' || this.status === 'pending') { return MINT }
    return TEXT_4
  }

  private resultSummary = (): string => {
    const normalized: string = this.result.split('\n').join(' ').trim()
    if (normalized.length <= 88) { return normalized }
    return normalized.substring(0, 88) + '…'
  }

  private detailText = (): string => {
    const values: string[] = []
    if (this.detail.length > 0) { values.push('输入\n' + this.detail) }
    if (this.result.length > 0) { values.push('结果\n' + this.result) }
    return values.join('\n\n')
  }
}
