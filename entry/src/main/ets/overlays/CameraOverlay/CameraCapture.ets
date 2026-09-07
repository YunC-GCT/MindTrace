import { F_BASE, F_XS, F_MD, S_2, S_3, S_4, S_6, SCREEN_W, TEXT, W_SEMIBOLD } from "common"
import { CameraCloseBtn } from "./CameraCloseBtn"
import { CameraAlbumBtn } from "./CameraAlbumBtn"
import { CameraShutterBtn } from "./CameraShutterBtn"
import { ViewfinderCorners } from "./ViewfinderCorners"
import { AppIcon } from "../../shared/atoms/AppIcon"

@Component
export struct CameraCapture {
  onClose: () => void = (): void => {}
  onShutter: () => void = (): void => {}
  onAlbum: () => void = (): void => {}

  build() {
    Column() {
      Row() {
        CameraCloseBtn({ onTap: (): void => { this.onClose() } })
        Blank()
        Text("\u62cd\u7167\u8bb0\u9898")
          .fontSize(F_MD)
          .fontColor(TEXT)
          .fontWeight(W_SEMIBOLD)
        Blank()
        Column().width(SCREEN_W / 8).height(SCREEN_W / 8)
      }
      .width("100%")
      .padding({ left: S_4, right: S_4, top: S_3, bottom: S_3 })
      .alignItems(VerticalAlign.Center)

      Stack() {
        Column() {
          AppIcon({ name: "camera", iconSize: SCREEN_W / 7, color: "rgba(255,255,255,0.34)", strokeWidth: 1.8 })
          Text("\u5c06\u9898\u76ee\u5bf9\u51c6\u6846\u5185")
            .fontSize(F_BASE)
            .fontColor("rgba(255,255,255,0.62)")
            .fontWeight(W_SEMIBOLD)
            .margin({ top: S_4 })
          Text("\u70b9\u51fb\u4e0b\u65b9\u5feb\u95e8\u62cd\u6444\uff0c\u6216\u4ece\u76f8\u518c\u9009\u62e9")
            .fontSize(F_XS)
            .fontColor("rgba(255,255,255,0.42)")
            .margin({ top: S_2 })
        }
        .alignItems(HorizontalAlign.Center)

        ViewfinderCorners()
      }
      .layoutWeight(1)
      .width("100%")
      .backgroundColor("#FF000000")

      Row() {
        CameraAlbumBtn({ onTap: (): void => { this.onAlbum() } })
        CameraShutterBtn({ onTap: (): void => { this.onShutter() } })
        Column().width(SCREEN_W / 7).height(SCREEN_W / 7)
      }
      .width("100%")
      .height(132)
      .padding({ left: S_4, right: S_4, top: S_3, bottom: S_6 + S_4 })
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)
    }
    .width("100%")
    .height("100%")
  }
}
