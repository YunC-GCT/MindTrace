// ============================================================================
//  pages/Profile/ProfileMenuList.ets — 我的页菜单列表
//  ----------------------------------------------------------------------------
//  职责: 我的页菜单项容器。
//
//  布局: 卡片式列表,每项 1 行
//    [图标] [标签]                            [›]
//
//  依赖:
//    pages: ProfileMenuItemRow
//    common 令牌: BG_CARD / S_2 / S_4 / R_LG
//
//  Props:
//    onToast: 菜单点击回调(子菜单用 toast 提示"开发中","模型"项直接跳路由)
//  ============================================================================

import { BG_CARD, S_2, S_4, R_LG } from "common"
import { router } from "@kit.ArkUI"
import { ProfileMenuItemRow } from "./ProfileMenuItemRow"

@Component
export struct ProfileMenuList {
  // 菜单点击回调(子菜单传 toast,"模型" 项不走这里)
  onToast: (message: string) => void = (_message: string): void => {}
  onSwitchAccount: () => void = (): void => {}

  build() {
    Column() {
      // 1. 我的复习计划(W2 计划接入)
      ProfileMenuItemRow({
        icon: "review",
        label: "我的复习计划",
        onTap: (): void => this.onToast("复习计划开发中")
      })

      // 2. 错题本
      ProfileMenuItemRow({
        icon: "notes",
        label: "错题本",
        onTap: (): void => this.onToast("错题本开发中")
      })

      // 3. 我的收藏
      ProfileMenuItemRow({
        icon: "home",
        label: "我的收藏",
        onTap: (): void => this.onToast("收藏功能开发中")
      })

      // 4. 回收站
      ProfileMenuItemRow({
        icon: "recycle",
        label: "回收站",
        onTap: (): void => this.onToast("回收站开发中")
      })

      // 5. 模型配置(已实现,跳 AiSettingsPage)
      ProfileMenuItemRow({
        icon: "ai",
        label: "模型",
        onTap: (): void => { router.pushUrl({ url: "pages/AiSettings/AiSettingsPage" }) }
      })

      // 5.1 学科整理(把历史笔记重新归到更合适的学科)
      ProfileMenuItemRow({
        icon: "notes",
        label: "学科整理",
        onTap: (): void => { router.pushUrl({ url: "pages/Profile/SubjectMaintenancePage" }) }
      })

      // 6. 帮助反馈
      ProfileMenuItemRow({
        icon: "feedback",
        label: "帮助反馈",
        onTap: (): void => this.onToast("帮助反馈开发中")
      })

      // 7. 切换账号
      ProfileMenuItemRow({
        icon: "me",
        label: "切换账号",
        onTap: (): void => this.onSwitchAccount()
      })
    }
    .width("100%")
    .backgroundColor(BG_CARD)
    .borderRadius(R_LG)
    .margin({ left: S_4, right: S_4, top: S_2 })
  }
}
