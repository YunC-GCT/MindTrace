/**
 * SendButton.ets — AI 浮窗输入栏三态动作按钮
 *
 * 路径: entry/src/main/ets/overlays/AgentFloatWindow/SendButton.ets
 * 职责: idle / ready / busy 三态切换的发送/停止按钮
 * 依赖: common (MINT, PURPLE, BG_DARK, TEXT_3, GLASS_10, F_SM, F_LG, W_BOLD)
 *
 * 三态视觉:
 *   - idle  (无内容): GLASS_10 灰底 + 灰 ↑ + opacity 0.4 + 点击无反应
 *   - ready (可发送): MINT 绿底 + 黑 ↑ + opacity 1 + 点击 onSend
 *   - busy  (AI 响应): PURPLE 紫底 + 黑 ■ + opacity 1 + 点击 onStop
 *
 * Props:
 *   busy:    AI 是否正在响应
 *   canSend: 是否有可发送内容
 *   onSend?: 发送回调 (ready 态)
 *   onStop?: 停止回调 (busy 态)
 */

import {
  MINT, PURPLE, BG_DARK, TEXT_3, GLASS_10,
  F_SM, F_LG, W_BOLD,
} from 'common';

@Component
export struct SendButton {
  @Prop busy: boolean = false;
  @Prop canSend: boolean = false;

  onSend?: () => void = (): void => {};
  onStop?: () => void = (): void => {};

  build() {
    Stack() {
      if (this.busy) {
        Text('■')
          .fontSize(F_SM)
          .fontWeight(W_BOLD)
          .fontColor(BG_DARK)
      } else {
        Text('↑')
          .fontSize(F_LG)
          .fontWeight(W_BOLD)
          .fontColor(this.canSend ? BG_DARK : TEXT_3)
      }
    }
    .width(36).height(36)
    .borderRadius(18)
    .backgroundColor(this.busy ? PURPLE : (this.canSend ? MINT : GLASS_10))
    .opacity((this.canSend || this.busy) ? 1 : 0.4)
    .alignContent(Alignment.Center)
    .onClick((): void => {
      if (this.busy) {
        if (this.onStop) {
          this.onStop();
        }
      } else if (this.canSend) {
        if (this.onSend) {
          this.onSend();
        }
      }
    });
  }
}
