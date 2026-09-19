/**
 * ModeChip.ets — AI 浮窗输入栏模式文字胶囊
 *
 * 路径: entry/src/main/ets/overlays/AgentFloatWindow/ModeChip.ets
 * 职责: 可复用的文字胶囊 (圆角矩形 + 浅玻璃背景 + 边框)
 * 依赖: common (TEXT_2, BORDER, GLASS_10, S_1, S_3, R_FULL, F_XS, W_MEDIUM)
 *
 * Props:
 *   label:  胶囊文字
 *   onTap?: 点击回调 (TODO 占位)
 */

import {
  TEXT_2, BORDER, GLASS_10,
  S_2, S_3, R_FULL,
  F_XS, W_MEDIUM,
} from 'common';

@Component
export struct ModeChip {
  label: string = '';
  onTap?: () => void = (): void => {};

  build() {
    Text(this.label)
      .fontSize(F_XS)
      .fontColor(TEXT_2)
      .fontWeight(W_MEDIUM)
      .padding({ left: S_3, right: S_3, top: S_2, bottom: S_2 })
      .borderRadius(R_FULL)
      .backgroundColor(GLASS_10)
      .border({ width: 1, color: BORDER })
      .onClick((): void => {
        if (this.onTap) {
          this.onTap();
        }
      });
  }
}
