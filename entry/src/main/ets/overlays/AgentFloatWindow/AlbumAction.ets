/**
 * AlbumAction.ets — AI 浮窗 + 按钮弹出菜单中的「相册」动作胶囊
 *
 * 路径: entry/src/main/ets/overlays/AgentFloatWindow/AlbumAction.ets
 * 职责: 圆角矩形按钮, 内含相册图标 (ic_album.svg), 点击触发回调
 * 依赖: common (TEXT, GLASS_10, R_LG)
 * 资源: app.media.ic_album
 *
 * 视觉:
 *   ┌────┐
 *   │ 🖼 │   56×56 R_LG 圆角, GLASS_10 底, 居中 28×28 图标
 *   └────┘
 *
 * Props:
 *   onTap?: 点击回调 (TODO 接入相册选择业务)
 */

import {
  TEXT, GLASS_10,
  R_LG,
} from 'common';

@Component
export struct AlbumAction {
  onTap?: () => void = (): void => {};

  build() {
    Column() {
      Image($r('app.media.ic_album'))
        .width(22)
        .height(22)
        .fillColor(TEXT)
    }
    .width(44)
    .height(44)
    .borderRadius(R_LG)
    .backgroundColor(GLASS_10)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .onClick((): void => {
      if (this.onTap) {
        this.onTap();
      }
    });
  }
}
