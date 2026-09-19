/**
 * NewChatChip.ets — AI 浮窗头部"新建对话"胶囊 (替代 SessionBar 的 + 入口)
 *
 * 路径: entry/src/main/ets/overlays/AgentFloatWindow/chat/NewChatChip.ets
 * 职责: 圆角矩形按钮, 内含 SymbolGlyph 系统图标 + "新建对话" 文字
 * 依赖: common; 业务: services/SessionCreator
 * 图标: SymbolGlyph $r('sys.symbol.ohos_folder_badge_plus')
 *
 * 视觉:
 *   ┌──────────────────────┐
 *   │  📁+  新建对话        │   Row (系统图标 + 文字) + R_FULL 胶囊
 *   └──────────────────────┘
 *
 * Props:
 *   onTap?: 点击回调 (父组件触发 SessionCreator.newSession)
 */

import {
  TEXT_2, BG_CARD, BORDER,
  S_2, S_3, R_FULL,
  F_XS, W_MEDIUM,
} from 'common';

@Component
export struct NewChatChip {
  onTap?: () => void = (): void => {};

  build() {
    Row({ space: S_2 }) {
      SymbolGlyph($r('sys.symbol.ohos_folder_badge_plus'))
        .fontSize(18)
        .fontColor([TEXT_2])
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
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
