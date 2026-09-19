/**
 * FileAction.ets — AI 浮窗 + 按钮弹出菜单中的「文件」动作胶囊
 *
 * 路径: entry/src/main/ets/overlays/AgentFloatWindow/FileAction.ets
 * 职责: 圆角矩形按钮, 内含文件图标 (ic_file.svg), 点击触发回调
 * 依赖: common (TEXT, GLASS_10, R_LG)
 * 资源: app.media.ic_file (24×24 stroke 风格, 与 ic_album 同系列)
 *
 * 视觉:
 *   ┌────┐
 *   │ 📄 │   56×56 R_LG 圆角, GLASS_10 底, 居中 28×28 图标
 *   └────┘
 *
 * Props:
 *   onTap?: 点击回调 (TODO 接入文件选择业务)
 */

import {
  TEXT, GLASS_10,
  R_LG,
} from 'common';

@Component
export struct FileAction {
  onTap?: () => void = (): void => {};

  build() {
    Column() {
      Image($r('app.media.ic_file'))
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
