// ============================================================================
//  pages/Profile/ProfilePage.ets — 我的页 (5 Tab 之一)
//  ----------------------------------------------------------------------------
//  组件层: Page (D3 spec 012)
//  允许依赖: common 令牌/模型 · viewmodels · services · shared/* · 本目录组件
//  禁止依赖: database/dao 实现 · agents 内部实现 · 网络层直调
//  依赖: ProfileViewModel · ProfileAuthViewModel · ProfileHeader ·
//        ProfileStatsRow · ProfileMenuList · ProfileLoginPanel
// ============================================================================

import {
  BG_DARK,
  S_1, S_4, S_6,
  R_FULL,
  F_SM,
  GLASS_8,
  DANGER,
} from "common"
import { promptAction } from "@kit.ArkUI"
import { ProfileHeader } from "./ProfileHeader"
import { ProfileStatsRow } from "./ProfileStatsRow"
import { ProfileMenuList } from "./ProfileMenuList"
import { ProfileLoginPanel } from "./ProfileLoginPanel"
import { ProfileViewModel } from "../../viewmodels/ProfileViewModel"
import { ProfileAuthViewModel } from "../../viewmodels/ProfileAuthViewModel"

@Component
export struct ProfilePage {
  @StorageProp("statusBarHeight") sbh: number = 0
  @State vm: ProfileViewModel = new ProfileViewModel()
  @State auth: ProfileAuthViewModel = new ProfileAuthViewModel()

  aboutToAppear(): void {
    this.vm.loadStats(getContext(this)).then((ok: boolean): void => {
      if (!ok) {
        this.toast("统计加载失败")
      }
    })
    this.auth.load(getContext(this)).then((ok: boolean): void => {
      if (!ok) {
        this.toast("登录状态加载失败")
      }
    })
  }

  private toast(msg: string): void {
    try {
      promptAction.showToast({ message: msg, duration: 1000, bottom: "50%" })
    } catch (_e) {}
  }

  private loginWithHuawei(): void {
    this.auth.loginWithHuaweiMock(getContext(this)).then((ok: boolean): void => {
      this.toast(ok ? "华为账号登录成功" : "登录失败")
    })
  }

  private doLogout(successMessage: string): void {
    if (this.auth.loading) {
      return
    }
    this.auth.logout(getContext(this)).then((ok: boolean): void => {
      this.toast(ok ? successMessage : "退出登录失败")
    })
  }

  private confirmLogout(): void {
    AlertDialog.show({
      title: "退出登录",
      message: "退出后可再次使用华为账号登录。",
      autoCancel: true,
      primaryButton: {
        value: "取消",
        action: (): void => {}
      },
      secondaryButton: {
        value: "退出",
        fontColor: DANGER,
        action: (): void => this.doLogout("已退出")
      }
    })
  }

  private confirmSwitchAccount(): void {
    AlertDialog.show({
      title: "切换账号",
      message: "将返回登录页，随后可选择其他账号。",
      autoCancel: true,
      primaryButton: {
        value: "取消",
        action: (): void => {}
      },
      secondaryButton: {
        value: "切换",
        fontColor: DANGER,
        action: (): void => this.doLogout("请重新登录")
      }
    })
  }

  build() {
    Scroll() {
      Column() {
        Row()
          .width("100%")
          .height(this.sbh)
          .backgroundColor(BG_DARK)

        ProfileHeader({
          name: this.auth.displayName,
          subtitle: this.auth.subtitle(),
          initial: this.auth.initial(),
        })

        if (this.auth.loggedIn) {
          ProfileStatsRow({ notes: this.vm.notes, avg: this.vm.avg, today: this.vm.today })
          ProfileMenuList({
            onToast: (message: string): void => this.toast(message),
            onSwitchAccount: (): void => this.confirmSwitchAccount(),
          })

          Button("退出登录")
            .fontSize(F_SM)
            .fontColor(DANGER)
            .width("100%")
            .height(S_6 * 2 - S_1)
            .backgroundColor(GLASS_8)
            .borderRadius(R_FULL)
            .margin({ left: S_4, right: S_4, top: S_6, bottom: S_6 * 2 - S_1 })
            .onClick((): void => this.confirmLogout())
        } else {
          ProfileLoginPanel({
            loading: this.auth.loading,
            onLogin: (): void => this.loginWithHuawei(),
          })
        }

        Blank().height(80)
      }
      .width("100%")
    }
    .width("100%")
    .height("100%")
    .backgroundColor(BG_DARK)
    .scrollBar(BarState.Off)
  }
}
