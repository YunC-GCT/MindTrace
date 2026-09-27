/**
 * DeleteButton.ets — shared delete action button
 *
 * Layer: Atom
 * Path: entry/src/main/ets/shared/atoms/DeleteButton.ets
 * Responsibility: render the platform trash symbol and emit a tap intent
 * Dependencies: common design tokens and HarmonyOS SymbolGlyph
 * State: none
 *
 * Data flow:
 *   parent callback -> DeleteButton.onTap -> parent-owned delete workflow
 */

import { DANGER, GLASS_10, R_MD } from 'common'

@Component
export struct DeleteButton {
  @Prop boxSize: number = 36
  @Prop iconSize: number = 18
  onTap: () => void = (): void => {}

  build() {
    Stack() {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(this.iconSize)
        .fontColor([DANGER])
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
    }
    .width(this.boxSize)
    .height(this.boxSize)
    .borderRadius(R_MD + 2)
    .backgroundColor(GLASS_10)
    .alignContent(Alignment.Center)
    .accessibilityText('删除')
    .onClick((): void => this.onTap())
  }
}
