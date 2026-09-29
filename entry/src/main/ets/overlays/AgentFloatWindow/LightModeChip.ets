/**
 * LightModeChip.ets — 学习模式菜单中的「轻量模式」胶囊
 *
 * 路径: entry/src/main/ets/overlays/AgentFloatWindow/LightModeChip.ets
 * 职责: 纯渲染轻量模式选项及选中态, 点击时仅上抛回调
 * 依赖: common 设计 token
 *
 * Props:
 *   selected: 是否为当前选项
 *   onTap?:   点击回调
 */

import {
  TEXT_2, MINT, MINT_LIGHT, MINT_BORDER, GLASS_10, BORDER,
  R_FULL, F_XS, W_MEDIUM,
} from 'common';

export const LIGHT_MODE_LABEL: string = '轻量模式';

@Component
export struct LightModeChip {
  @Prop selected: boolean = false;
  onTap?: () => void = (): void => {};

  build() {
    Row() {
      Text(LIGHT_MODE_LABEL)
        .fontSize(F_XS)
        .fontColor(this.selected ? MINT : TEXT_2)
        .fontWeight(W_MEDIUM)
    }
    .width(112)
    .height(36)
    .justifyContent(FlexAlign.Center)
    .borderRadius(R_FULL)
    .backgroundColor(this.selected ? MINT_LIGHT : GLASS_10)
    .border({ width: 1, color: this.selected ? MINT_BORDER : BORDER })
    .onClick((): void => {
      if (this.onTap) {
        this.onTap();
      }
    });
  }
}
