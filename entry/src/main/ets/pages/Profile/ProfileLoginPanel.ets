// ============================================================================
//  pages/Profile/ProfileLoginPanel.ets - Huawei account sign-in placeholder
// ============================================================================

import {
  BG_CARD, BG_DARK,
  GLASS_10,
  MINT, TEXT, TEXT_2, TEXT_3,
  S_1, S_2, S_3, S_4,
  R_MD, R_LG,
  F_XS, F_SM, F_LG,
  W_SEMIBOLD,
} from "common"
import { AppIcon } from "../../shared/atoms/AppIcon"

@Component
export struct ProfileLoginPanel {
  @Prop loading: boolean = false
  @State agreed: boolean = false

  onLogin?: () => void = (): void => {}

  private canSubmit(): boolean {
    return !this.loading && this.agreed
  }

  build() {
    Column() {
      Row() {
        Stack() {
          Circle({ width: 48, height: 48 })
            .fill(GLASS_10)
          AppIcon({ name: "me", iconSize: 24, color: MINT, strokeWidth: 2 })
        }
        .margin({ right: S_3 })

        Column() {
          Text("华为账号")
            .fontSize(F_LG)
            .fontColor(TEXT)
            .fontWeight(W_SEMIBOLD)
            .width("100%")
          Text("一键登录 MindTrace")
            .fontSize(F_XS)
            .fontColor(TEXT_3)
            .margin({ top: S_1 })
            .width("100%")
        }
        .layoutWeight(1)
      }
      .width("100%")
      .alignItems(VerticalAlign.Center)

      Row() {
        Checkbox()
          .select(this.agreed)
          .selectedColor(MINT)
          .onChange((checked: boolean): void => {
            this.agreed = checked
          })

        Text("我已阅读并同意《用户协议》《隐私声明》")
          .fontSize(F_XS)
          .fontColor(TEXT_2)
          .layoutWeight(1)
          .margin({ left: S_2 })
      }
      .width("100%")
      .padding({ left: S_1, right: S_1, top: S_3 })
      .alignItems(VerticalAlign.Center)

      Button() {
        Row({ space: S_2 }) {
          AppIcon({ name: "me", iconSize: 18, color: BG_DARK, strokeWidth: 2 })
          Text(this.loading ? "正在登录..." : "华为账号一键登录")
            .fontSize(F_SM)
            .fontColor(BG_DARK)
            .fontWeight(W_SEMIBOLD)
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
      }
        .width("100%")
        .height(46)
        .backgroundColor(MINT)
        .borderRadius(R_MD)
        .margin({ top: S_4 })
        .enabled(this.canSubmit())
        .onClick((): void => {
          if (this.onLogin) { this.onLogin() }
        })

      Text("使用华为账号继续")
        .fontSize(F_XS)
        .fontColor(TEXT_3)
        .margin({ top: S_2 })
    }
    .width("100%")
    .padding({ left: S_4, right: S_4, top: S_4, bottom: S_4 })
    .backgroundColor(BG_CARD)
    .borderRadius(R_LG)
    .margin({ left: S_4, right: S_4, top: S_2, bottom: S_4 })
  }
}
