/**
 * SessionChip.ets — 会话列表面板中的单条会话胶囊
 *
 * 路径: entry/src/main/ets/overlays/AgentFloatWindow/chat/SessionChip.ets
 * 职责: 列表中的一条会话(点击切换 + 长按请求删除)
 * 依赖: common tokens
 *
 * 视觉:
 *   ┌────────────────────────────┐
 *   │  会话 1                     │   Row + R_MD 圆角 + active 时边框高亮
 *   └────────────────────────────┘
 *
 * Props:
 *   name: string                  会话名称
 *   active: boolean               是否当前激活
 *   onTap?: () => void            切换会话
 *   onLongPress?: () => void      长按删除入口(由父组件弹确认)
 */

import { TEXT, TEXT_2, BG_DARK, BG_CARD, BORDER, S_2, S_3, R_MD, F_XS, W_NORMAL, W_MEDIUM } from 'common';

@Component
export struct SessionChip {
  name: string = '';
  active: boolean = false;
  onTap?: () => void = (): void => {};
  onLongPress?: () => void = (): void => {};

  build() {
    Row() {
      Text(this.name)
        .fontSize(F_XS)
        .fontColor(this.active ? TEXT : TEXT_2)
        .fontWeight(this.active ? W_MEDIUM : W_NORMAL)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ left: S_3, right: S_3, top: S_2, bottom: S_2 })
    .borderRadius(R_MD)
    .backgroundColor(this.active ? BG_CARD : BG_DARK)
    .border({
      width: this.active ? 1 : 0,
      color: BORDER,
    })
    .gesture(LongPressGesture()
      .onAction((): void => {
        if (this.onLongPress) {
          this.onLongPress();
        }
      }))
    .onClick((): void => {
      if (this.onTap) {
        this.onTap();
      }
    });
  }
}
