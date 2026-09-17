/**
 * PlusButton.ets — AI 浮窗输入栏 "+" 按钮
 *
 * 路径: entry/src/main/ets/overlays/AgentFloatWindow/PlusButton.ets
 * 职责: 圆心带 "+" 的圆形按钮 (替代原附件/相机位, 后续告知具体用途)
 * 依赖: common (TEXT_2, GLASS_10, F_LG, W_MEDIUM)
 *
 * Props:
 *   onTap?: 点击回调 (TODO 占位)
 */

import {
  TEXT_2, GLASS_10,
  F_LG, W_MEDIUM,
} from 'common';

@Component
export struct PlusButton {
  onTap?: () => void = (): void => {};

  build() {
    Stack() {
      Text('+')
        .fontSize(F_LG)
        .fontWeight(W_MEDIUM)
        .fontColor(TEXT_2)
    }
    .width(36).height(36)
    .borderRadius(18)
    .backgroundColor(GLASS_10)
    .alignContent(Alignment.Center)
    .onClick((): void => {
      if (this.onTap) {
        this.onTap();
      }
    });
  }
}
