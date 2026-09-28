/**
 * DetailStepList.ets — 详情页步骤/过程列表
 *
 * 路径: entry/src/main/ets/overlays/NoteDetailOverlay/components/DetailStepList.ets
 * 职责: 将证明过程、计算步骤等内容渲染为编号阅读路径。
 * 依赖: common tokens, MarkdownRenderer
 *
 * 数据流:
 *   renderer splitReadableLines(content) → DetailStepList → MarkdownRenderer
 *
 * ArkTS 1.1 strict 适配:
 *   - ForEach 使用稳定 key
 *   - struct 内无普通方法
 */

import {
  MINT, BORDER,
  S_2, S_3,
  R_FULL,
  F_SM,
  W_BOLD,
} from 'common'
import { MarkdownRenderer } from '../../../shared/molecules/MarkdownRenderer'
import { DEFAULT_MATH_RENDER_PRIORITY } from '../../../services/MathRenderBudget'
import { DetailRenderSession } from './DetailRenderSession'

@Component
export struct DetailStepList {
  @Prop renderSession: DetailRenderSession = new DetailRenderSession()
  @Prop renderPriority: number = DEFAULT_MATH_RENDER_PRIORITY
  @Prop items: string[] = []
  @Prop accentColor: ResourceColor = MINT

  build() {
    Column() {
      ForEach(this.items,
        (item: string, index: number): void => {
          Row() {
            Text((index + 1).toString())
              .fontSize(F_SM)
              .fontWeight(W_BOLD)
              .fontColor(this.accentColor)
              .width(24)
              .height(24)
              .textAlign(TextAlign.Center)
              .borderRadius(R_FULL)
              .backgroundColor('#0DFFFFFF')
              .border({ width: 0.5, color: BORDER })
              .margin({ right: S_2 })

            Column() {
              MarkdownRenderer({
                text: item,
                progressive: false,
                profile: 'note',
                renderBudget: this.renderSession,
                renderPriority: this.renderPriority,
              })
            }
            .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          .margin({ bottom: S_3 })
        },
        (item: string, index: number): string => index.toString() + '_' + item
      )
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
