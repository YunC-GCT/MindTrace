// ============================================================================
//  pages/MainTabs/TabButton.ets — 普通 Tab 按钮原子组件
//  ----------------------------------------------------------------------------
//  职责: 复用 AppIcon 的草稿描边图标，装配底栏标签与选中态。
//  来源: 从 Index.ets TabBtn @Builder 转换为 @Component。
//  接口:
//    @Prop  iconName — AppIcon 图标名称
//    @Prop  label   — Tab 文字
//    @Prop  active  — 是否当前选中
//    onTap           — 点击回调
//  ============================================================================

import {
  TAB_NAV_ACTIVE, TAB_NAV_MUTED, TAB_LABEL_GAP, TAB_LABEL_HEIGHT,
  F_SM, W_NORMAL, W_MEDIUM, TAB_ICON_SIZE, TAB_BTN_RADIUS,
} from "common"
import { AppIcon } from "../../shared/atoms/AppIcon"

@Component
export struct TabButton {
  @Prop iconName: string = "home"
  @Prop label: string = ""
  @Prop active: boolean = false
  onTap: () => void = (): void => {}

  build() {
    Column({ space: TAB_LABEL_GAP }) {
      AppIcon({
        name: this.iconName,
        iconSize: TAB_ICON_SIZE,
        color: this.active ? TAB_NAV_ACTIVE : TAB_NAV_MUTED,
        strokeWidth: this.active ? 2 : 1.7,
      })

      Text(this.label)
        .fontSize(F_SM).fontWeight(this.active ? W_MEDIUM : W_NORMAL)
        .fontColor(this.active ? TAB_NAV_ACTIVE : TAB_NAV_MUTED)
        .height(TAB_LABEL_HEIGHT)
    }
    .layoutWeight(1)
    .height(54)
    .justifyContent(FlexAlign.End)
    .borderRadius(TAB_BTN_RADIUS)
    .alignItems(HorizontalAlign.Center)
    .accessibilityText(this.label)
    .onClick((): void => { this.onTap() })
  }
}
