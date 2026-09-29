/**
 * NewChatPlusButton.ets — 浮窗头部右侧"新建对话+"快速新建按钮
 *
 * 路径: entry/src/main/ets/overlays/AgentFloatWindow/chat/NewChatPlusButton.ets
 * 职责: 与 HistoryChip 区分 — 点击后直接 newSession, 不打开面板
 *       视觉: 清晰 + 图标 + "新建对话" 文字, 与 HistoryChip 共用中性色板
 * 依赖: common tokens
 *
 * 视觉:
 *   ┌──────────────────┐
 *   │  +  新建对话       │   Row (图标 + 文字) + R_FULL 胶囊
 *   └──────────────────┘
 *
 * Props:
 *   onTap?: () => void
 */

import {
  TEXT_2, BG_CARD, BORDER,
  S_2, S_3, R_FULL, F_SM, W_SEMIBOLD,
} from 'common';

const NEW_CHAT_BUTTON_HEIGHT: number = 32;

@Component
export struct NewChatPlusButton {
  onTap?: () => void = (): void => {};

  build() {
    Row({ space: S_2 }) {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(18)
        .fontColor([TEXT_2])
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)

      Text('新建对话')
        .fontSize(F_SM)
        .fontColor(TEXT_2)
        .fontWeight(W_SEMIBOLD)
    }
    .height(NEW_CHAT_BUTTON_HEIGHT)
    .padding({ left: S_2, right: S_3 })
    .alignItems(VerticalAlign.Center)
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
