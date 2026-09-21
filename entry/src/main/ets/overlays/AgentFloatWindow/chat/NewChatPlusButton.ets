/**
 * NewChatPlusButton.ets — 浮窗头部右侧"新建对话+"快速新建按钮
 *
 * 路径: entry/src/main/ets/overlays/AgentFloatWindow/chat/NewChatPlusButton.ets
 * 职责: 与 HistoryChip 区分 — 点击后直接 newSession, 不打开面板
 *       视觉: + 图标 + "新建对话" 文字, R_FULL 胶囊, 与 HistoryChip 镜像
 * 依赖: common tokens
 *
 * 视觉:
 *   ┌──────────────────┐
 *   │  +  新建对话       │   Row (Path + icon + 文字) + R_FULL 胶囊
 *   └──────────────────┘
 *
 * Props:
 *   onTap?: () => void
 */

import { TEXT_2, BG_CARD, BORDER, S_2, S_3, R_FULL, F_XS, W_MEDIUM } from 'common';

@Component
export struct NewChatPlusButton {
  onTap?: () => void = (): void => {};

  build() {
    Row({ space: S_2 }) {
      Path()
        .width(14).height(14)
        .commands('M7 1 L7 13 M1 7 L13 7')
        .stroke(TEXT_2)
        .strokeWidth(2)
        .strokeLineCap(LineCapStyle.Round)
        .fill(Color.Transparent)
      Text('新建对话')
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
