/**
 * ChatSourcePanel.ets - 回答来源卡片
 *
 * 路径: overlays/AgentFloatWindow/chat/ChatSourcePanel.ets
 * 职责: 把本轮命中的笔记来源渲染成可折叠卡片列表：标题 + 角色 + 纯文本摘要，
 *       点击交给只读来源浮层；不再把摘录拼进回答正文。
 * 依赖: common UI tokens / NoteEvidenceCitation / citationSnippet
 */

import {
  BORDER,
  F_XS,
  MINT,
  R_MD,
  S_1,
  S_2,
  S_3,
  TEXT,
  TEXT_2,
  TEXT_3,
  TEXT_4,
  W_MEDIUM,
  W_SEMIBOLD,
} from 'common'
import { NoteEvidenceCitation, citationSnippet } from 'common'

@Component
export struct ChatSourcePanel {
  @Prop citations: NoteEvidenceCitation[] = []
  onSourceTap: (citation: NoteEvidenceCitation) => void = (_citation: NoteEvidenceCitation): void => {}
  @State expanded: boolean = false

  build() {
    if (this.citations.length > 0) {
      Column() {
        Row() {
          Text('参考来源')
            .fontSize(F_XS)
            .fontColor(TEXT_3)
            .fontWeight(W_SEMIBOLD)
          Text(this.citations.length.toString() + ' 条')
            .fontSize(9)
            .fontColor(MINT)
            .margin({ left: S_1 })
          Blank()
          Text(this.expanded ? '收起' : '展开')
            .fontSize(10)
            .fontColor(TEXT_4)
        }
        .width('100%')
        .padding({ left: S_3, right: S_3, top: S_2, bottom: S_2 })
        .onClick((): void => { this.expanded = !this.expanded })

        if (this.expanded) {
          ForEach(this.citations, (citation: NoteEvidenceCitation): void => {
            this.SourceRow(citation)
          }, (citation: NoteEvidenceCitation): string => citation.noteId + ':' + citation.version.toString())
        }
      }
      .width('100%')
      .borderRadius(R_MD + 4)
      .border({ width: 0.5, color: BORDER })
      .backgroundColor('rgba(255,255,255,0.02)')
      .margin({ top: S_2 })
    }
  }

  @Builder
  SourceRow(citation: NoteEvidenceCitation) {
    Row() {
      Text(this.roleLabel(citation.role))
        .fontSize(9)
        .fontColor(this.roleColor(citation.role))
        .fontWeight(W_SEMIBOLD)
        .width(56)

      Column() {
        Text(citation.title.length > 0 ? citation.title : '未命名笔记')
          .fontSize(12)
          .fontColor(TEXT)
          .fontWeight(W_MEDIUM)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        if (citationSnippet(citation.excerpt).length > 0) {
          Text(citationSnippet(citation.excerpt))
            .fontSize(10)
            .fontColor(TEXT_2)
            .lineHeight(15)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: S_3, right: S_3, top: S_2, bottom: S_2 })
    .onClick((): void => { this.onSourceTap(citation) })
  }

  private roleLabel(role: string): string {
    if (role === 'hit') { return '[关键词命中]' }
    if (role === 'prerequisite') { return '[前置知识]' }
    return '[关联知识]'
  }

  private roleColor(role: string): string {
    return role === 'hit' ? MINT : TEXT_4
  }
}
