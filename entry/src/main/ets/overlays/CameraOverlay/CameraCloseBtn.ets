import { SCREEN_W } from "common"
import { AppIcon } from "../../shared/atoms/AppIcon"

@Component
export struct CameraCloseBtn {
  onTap: () => void = (): void => {}

  build() {
    Stack() {
      AppIcon({ name: "close", iconSize: SCREEN_W / 20, color: "rgba(255,255,255,0.82)", strokeWidth: 2 })
    }
    .width(SCREEN_W / 8)
    .height(SCREEN_W / 8)
    .borderRadius(SCREEN_W / 16)
    .backgroundColor("rgba(255,255,255,0.08)")
    .border({ width: 1, color: "rgba(255,255,255,0.1)" })
    .alignContent(Alignment.Center)
    .onClick((): void => { this.onTap() })
  }
}