// ============================================================================
//  shared/molecules/MathPreviewText.ets — compact note preview with KaTeX fallback
//  ----------------------------------------------------------------------------
//  spec 016 PR-C (issue #67, audit C5): atom → molecule 迁移 (audit C5 atom→atom
//  违例: 本文件组合 MathTextRenderer, 是分子行为)。本文件 import MathTextRenderer
//  来自 sibling molecule (spec 012 §"Layering rules" PR-C 增补行允许 molecule→molecule)。
//  ============================================================================

import { ContentExcerptBuilder, ContentProtocol, TEXT_3, F_SM } from 'common'
import { MathTextRenderer } from './MathTextRenderer'

@Component
export struct MathPreviewText {
  @Prop text: string = ''
  @Prop textColor: ResourceColor = TEXT_3
  @Prop fontSize: number = F_SM
  @Prop lineHeightValue: number = 18
  @Prop maxLines: number = 2
  @Prop minHeight: number = 34
  @Prop maxChars: number = 46
  private contentProtocol: ContentProtocol = new ContentProtocol()
  private contentExcerptBuilder: ContentExcerptBuilder = new ContentExcerptBuilder()

  private containsFormulaSyntax = (text: string): boolean => {
    return this.contentProtocol.hasFormulaSyntax(text)
  }

  private previewText = (): string => {
    return this.contentExcerptBuilder.buildListPreview(this.text, this.maxChars)
  }

  build() {
    if (this.previewText().length > 0) {
      if (this.containsFormulaSyntax(this.previewText())) {
        MathTextRenderer({
          text: this.previewText(),
          profile: 'preview',
          textColor: this.textColor,
          formulaColor: this.textColor,
          fontSize: this.fontSize,
          lineHeight: this.lineHeightValue,
          formulaFontSize: this.fontSize,
          formulaLineHeight: this.lineHeightValue,
          minHeight: this.minHeight,
        })
      } else {
        Text(this.previewText())
          .fontSize(this.fontSize)
          .fontColor(this.textColor)
          .lineHeight(this.lineHeightValue)
          .maxLines(this.maxLines)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
  }
}
