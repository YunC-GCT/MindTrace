/**
 * SessionsPanel.ets — 浮窗内的对话列表面板
 *
 * 路径: entry/src/main/ets/overlays/AgentFloatWindow/chat/SessionsPanel.ets
 * 职责: 渲染会话胶囊列表; List 自适应高度 (内容少时不撑大, 内容超出 maxHeight 才滚动)
 *       滚动条始终可见 (新增会话也能滑动查找)
 *       显隐和绝对定位由 AgentFloatWindow 控制, 本组件只渲染内容
 * 依赖: chat/SessionChip; chat/ChatModels; common
 *
 * Props:
 *   sessions: ChatSession[]                  所有会话
 *   activeSid: string                        当前激活会话 id
 *   onSelect: (sid: string) => void          点击切换 (父组件负责关面板)
 *   onRequestDelete: (sid: string) => void   长按删除 (父组件弹原生确认)
 *   onRequestClearAll: () => void            点击"清空全部对话" (父组件弹原生确认)
 *
 * 布局: 宽度 30%, 自适应高度 (List wrap content), 最多显示 5 条;
 *       无圆角边框; 滚动条始终可见; 列表下方固定一条清空入口
 */

import { BG_CARD, BORDER, DANGER_BRIGHT, F_XS, S_3, W_NORMAL } from 'common';
import { ChatSession } from './ChatModels';
import { SessionChip } from './SessionChip';

const MAX_VISIBLE_ITEMS: number = 5;
const CHIP_H_VP: number = 36;
const MAX_PANEL_H_VP: number = MAX_VISIBLE_ITEMS * CHIP_H_VP;
const PANEL_W_RATIO: string = '30%';

@Component
export struct SessionsPanel {
  @Prop sessions: ChatSession[] = [];
  @Prop activeSid: string = '';
  onSelect: (sid: string) => void = (): void => {};
  onRequestDelete: (sid: string) => void = (): void => {};
  onRequestClearAll: () => void = (): void => {};

  build() {
    Column() {
      List({ space: 0 }) {
        ForEach(this.sessions, (session: ChatSession): void => {
          ListItem() {
            SessionChip({
              name: session.name,
              active: session.id === this.activeSid,
              onTap: (): void => { this.onSelect(session.id); },
              onLongPress: (): void => { this.onRequestDelete(session.id); },
            })
          }
        }, (session: ChatSession): string => session.id);
      }
      .width('100%')
      .constraintSize({ maxHeight: MAX_PANEL_H_VP })
      .scrollBar(BarState.On)
      .edgeEffect(EdgeEffect.None);

      Row().width('100%').height(0.5).backgroundColor(BORDER);
      Row() {
        Text('清空全部对话')
          .fontSize(F_XS)
          .fontColor(DANGER_BRIGHT)
          .fontWeight(W_NORMAL)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .width('100%')
      .height(CHIP_H_VP)
      .padding({ left: S_3, right: S_3 })
      .onClick((): void => { this.onRequestClearAll(); });
    }
    .width(PANEL_W_RATIO)
    .backgroundColor(BG_CARD)
    .border({ width: 1, color: BORDER });
  }
}
