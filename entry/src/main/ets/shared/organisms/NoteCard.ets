// ============================================================================
//  shared/organisms/NoteCard.ets — 笔记卡片共享组件 · 对齐 v2-ui .note-card
//  ----------------------------------------------------------------------------
//  布局: [渐变 icon 36×36] [meta: 类型(粗) · 日期  ··· 置信度]
//                          [标题 (15px semibold)]
//                          [正文预览 (1 行协议安全截断)]
//  ============================================================================

import {
  S_1, S_3, BORDER, GLASS_8, TEXT, TEXT_3, TEXT_4,
  R_MD, F_XS, F_MD,
  W_SEMIBOLD, W_BOLD,
  NOTE_ICON_SIZE, NoteItem, recentDate, typeChar, typeColor, typeGlassColor,
  borderToneColor, glassHighlightColor, glassShadowColor,
} from "common"
import { MathPreviewText } from "../atoms/MathPreviewText"

@Component
export struct NoteCard {
  @Prop note: NoteItem = new NoteItem(0, "", "", "", "", 0, "", [], "")
  @Prop isLast: boolean = false
  onTap?: () => void

  build() {
    Row() {
      // 左侧渐变图标 (v2-ui .note-icon)
      Stack() {
        Stack()
          .width(NOTE_ICON_SIZE).height(NOTE_ICON_SIZE).borderRadius(R_MD + 1)
          .backgroundColor(typeGlassColor(this.note.type))
          .linearGradient({
            angle: 145,
            colors: [
              [glassHighlightColor(typeColor(this.note.type)), 0],
              [typeGlassColor(this.note.type), 0.62],
              [GLASS_8, 1],
            ],
          })
          .border({ width: 0.5, color: borderToneColor(typeColor(this.note.type)) })
          .shadow({ radius: 8, color: glassShadowColor(typeColor(this.note.type)), offsetX: 0, offsetY: 3 })
        Text(typeChar(this.note.type))
          .fontSize(F_MD + 2).fontWeight(W_BOLD).fontColor(typeColor(this.note.type))
      }
      .width(NOTE_ICON_SIZE).height(NOTE_ICON_SIZE).alignContent(Alignment.Center)

      // 右侧内容 (v2-ui .note-info)
      Column() {
        // Meta 行 (v2-ui .note-meta: type bold · date ··· conf)
        Row() {
          Text(this.note.type)
            .fontSize(F_XS).fontColor(typeColor(this.note.type)).fontWeight(W_BOLD)
          Text(' · ').fontSize(F_XS).fontColor(TEXT_4)
          Text(recentDate(this.note.date)).fontSize(F_XS).fontColor(TEXT_3)

          Blank()

          Text(Math.round(this.note.conf * 100).toString() + '%')
            .fontSize(F_XS).fontWeight(W_SEMIBOLD).fontColor(typeColor(this.note.type))
        }.width('100%')

        // 标题 (v2-ui .note-title: 15px semibold)
        Text(this.note.title)
          .fontSize(F_MD).fontWeight(W_SEMIBOLD).fontColor(TEXT)
          .margin({ top: S_1 }).maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')

        // 正文预览: 一行扫描信息；短公式完整渲染，长公式留在详情页。
        MathPreviewText({
          text: this.note.body,
          textColor: TEXT_3,
          fontSize: F_XS,
          lineHeightValue: 17,
          maxLines: 1,
          minHeight: 18,
          maxChars: 46,
        })
          .margin({ top: 2 })
          .width('100%')
      }
      .layoutWeight(1).margin({ left: S_3 })
    }
    .width('100%').alignItems(VerticalAlign.Top)
    .padding({ top: S_3, bottom: S_3 })
    .border({ width: { bottom: this.isLast ? 0 : 1 }, color: BORDER })
    .onClick((): void => { if (this.onTap) { this.onTap() } })
  }
}
