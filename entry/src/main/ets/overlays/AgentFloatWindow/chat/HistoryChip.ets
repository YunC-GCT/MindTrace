/**
 * HistoryChip.ets — 浮窗头部"对话历史"按钮
 *
 * 路径: entry/src/main/ets/overlays/AgentFloatWindow/chat/HistoryChip.ets
 * 职责: 点击后由父组件打开 SessionsPanel (toggle 模式)
 * 依赖: common ColorTokens + SymbolGlyph
 *
 * 视觉:
 *   ┌──────────────────┐
 *   │  📁+  对话历史     │   Row + R_FULL 胶囊 (与 NewChatPlusButton 镜像)
 *   └──────────────────┘
 *
 * Props:
 *   onTap?: 点击回调 (父组件触发 togglePanel)
 */

import {
  TEXT_2, BG_CARD, BORDER,
  S_2, S_3, R_FULL,
  F_XS, W_MEDIUM,
} from 'common';

@Component
export struct HistoryChip {
  onTap?: () => void = (): void => {};

  build() {
    Row({ space: S_2 }) {
      SymbolGlyph($r('sys.symbol.ohos_folder_badge_plus'))
        .fontSize(18)
        .fontColor([TEXT_2])
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      Text('对话历史')
        .fontSize(F_XS)
        .fontColor(TEXT_2)
        .fontWeight(W_MEDIUM)
    }
    .padding({ left: S_3, right: S_3, top: S_2, bottom: S_2 })
    .borderRadius(R_FULL)
    .backgroundColor(BG_CARD)
    .border({ width: 1, color: BORDER })
    .onClick((): void => {
      if (this.onTap) {
        this.onTap();
      }
    });
  }
}
