// ============================================================================
//  pages/MainTabs/TabButton.ets — 普通 Tab 按钮原子组件
//  ----------------------------------------------------------------------------
//  职责: 渲染图标 + 文字的标准 Tab 按钮，高亮态 MINT 色。
//  来源: 从 Index.ets TabBtn @Builder 转换为 @Component。
//  接口:
//    @Prop  icon    — Tab 图标 Resource
//    @Prop  label   — Tab 文字
//    @Prop  active  — 是否当前选中
//    onTap           — 点击回调
//  ============================================================================

import {
  MINT, MINT_LIGHT, TEXT_3, GLASS_8,
  S_1, S_2, F_XS, W_MEDIUM, TAB_ICON_SIZE, TAB_BTN_RADIUS,
} from "common"

@Component
export struct TabButton {
  @Prop icon: Resource = $r("app.media.ic_home")
  @Prop label: string = ""
  @Prop active: boolean = false
  onTap: () => void = (): void => {}

  build() {
    Column() {
      Stack() {
        Circle({ width: TAB_ICON_SIZE + S_2, height: TAB_ICON_SIZE + S_2 })
          .fill(this.active ? MINT_LIGHT : GLASS_8)
          .opacity(this.active ? 1 : 0)

        Image(this.icon)
          .width(TAB_ICON_SIZE).height(TAB_ICON_SIZE)
          .fillColor(this.active ? MINT : TEXT_3)
      }
      .width(TAB_ICON_SIZE + S_2).height(TAB_ICON_SIZE + S_2)
      .shadow({
        radius: this.active ? 12 : 0,
        color: this.active ? MINT_LIGHT : GLASS_8,
        offsetX: 0,
        offsetY: 0,
      })

      Text(this.label)
        .fontSize(F_XS).fontWeight(W_MEDIUM)
        .fontColor(this.active ? MINT : TEXT_3)
        .margin({ top: S_1 })
    }
    .layoutWeight(1)
    .padding({ top: S_2, bottom: S_2 })
    .borderRadius(TAB_BTN_RADIUS)
    .alignItems(HorizontalAlign.Center)
    .onClick((): void => { this.onTap() })
  }
}
