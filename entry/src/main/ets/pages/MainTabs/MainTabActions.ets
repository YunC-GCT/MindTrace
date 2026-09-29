/**
 * MainTabActions.ets — 五入口相关的浮层动作适配器
 *
 * 路径: entry/src/main/ets/pages/MainTabs/MainTabActions.ets
 * 职责: 隔离底栏和页面入口对 OverlayService 的业务调用。
 * 依赖: OverlayService
 *
 * 数据流:
 *   Tab/Page intent → MainTabActions → OverlayService → 全局浮层
 *
 * 组件只发出动作回调，Index 只负责装配动作和浮层状态。
 *
 * ArkTS 1.1 strict 适配:
 *   - 使用普通 class 承载业务方法，避免在 @Component struct 中定义普通方法。
 */

import { OverlayService } from "../../services/OverlayService"

export class MainTabActions {
  private overlays: OverlayService = new OverlayService()

  openCamera(): void {
    this.overlays.open('camera')
  }

  openAssistant(): void {
    this.overlays.open('float')
  }

  closeOverlay(): void {
    this.overlays.close()
  }
}
