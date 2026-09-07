// ============================================================================
//  shared/atoms/StatsBox.ets — 统计方块共享组件
//  W3: 边框减细 + 间距令牌化
// ============================================================================

import { TEXT, TEXT_3, BORDER, GLASS_8, S_2, S_3, F_XS, F_MD, W_BOLD } from "common"

@Component
export struct StatsBox {
  @Prop value: string = ""
  @Prop label: string = ""

  build() {
    Column() {
      Text(this.value)
        .fontSize(F_MD + 2)
        .fontWeight(W_BOLD)
        .fontColor(TEXT)
        .fontFamily("HarmonyOS Sans Condensed")
      Text(this.label)
        .fontSize(F_XS)
        .fontColor(TEXT_3)
        .margin({ top: S_2 })
    }
    .layoutWeight(1)
    .padding({ top: S_3, bottom: S_3 })
    .borderRadius(12)
    .backgroundColor(GLASS_8)
    .border({ width: 0.5, color: BORDER })
    .alignItems(HorizontalAlign.Center)
  }
}
