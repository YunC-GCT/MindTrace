// ============================================================================
//  pages/Profile/ProfileMenuItemRow.ets — 菜单行原子组件
//  ----------------------------------------------------------------------------
//  职责: 图标 + 标签 + 右箭头 的通用菜单行。纯展示,交互通过 onClick 回调。
//
//  布局:
//    [图标]  [标签]  [ › ]
//
//  依赖:
//    shared: AppIcon
//    common 令牌: TEXT_2 / TEXT_4 / BORDER / S_4 / F_SM / F_MD
//
//  Props:
//    icon:  AppIcon 名称(对应 lucide 图标)
//    label: 标签文字
//    onTap: 点击回调
//
//  来源: 从 ProfilePage.ets MenuItem @Builder 抽取(2026-07-17 refactor)
//  ============================================================================

import { TEXT_2, TEXT_4, BORDER, S_4, F_SM, F_MD } from "common"
import { AppIcon } from "../../shared/atoms/AppIcon"

@Component
export struct ProfileMenuItemRow {
  // AppIcon 名称(对应 lucide 图标)
  @Prop icon: string = "notes"

  // 标签文字
  @Prop label: string = ""

  // 点击回调
  onTap?: () => void = (): void => {}

  build() {
    Row() {
      // 左侧图标
      AppIcon({ name: this.icon, iconSize: 18, color: TEXT_4, strokeWidth: 1.8 })
        .width(22)
        .flexShrink(0)

      // 标签
      Text(this.label)
        .fontSize(F_SM)
        .fontColor(TEXT_2)
        .layoutWeight(1)
        .margin({ left: 12 })

      // 右箭头
      AppIcon({ name: "chevron-right", iconSize: F_MD + 1, color: TEXT_4, strokeWidth: 1.8 })
    }
    .width("100%")
    .padding({ left: 16, right: 16, top: S_4, bottom: S_4 })
    // 底部分隔线
    .border({ width: { bottom: 1 }, color: BORDER })
    .onClick((): void => {
      if (this.onTap) { this.onTap() }
    })
  }
}
