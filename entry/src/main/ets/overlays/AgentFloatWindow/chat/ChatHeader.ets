/**
 * ChatHeader.ets — 浮窗头部 (Stack overlay: 左 HistoryChip(对话历史) + 右 NewChatPlusButton(新建对话+); 标题覆盖层居中)
 *
 * 路径: entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatHeader.ets
 * 职责: 浮窗顶部, 由左到右依次为 HistoryChip(打开/关闭会话列表面板)/ Blank / NewChatPlusButton(快速新建);
 *       关闭按钮已移除 — 关闭浮窗靠点击 sheet 外 mask
 *       标题用 Stack overlay 占据整行宽度, textAlign.Center 自然居中到整个 ChatHeader 的水平中心
 * 依赖: common ColorTokens; 子组件: HistoryChip, NewChatPlusButton
 *
 * 布局 (Stack overlay):
 *    [— 背景 Row: HistoryChip | Blank | NewChatPlusButton]
 *                会话 2           ← 覆盖层, 占整行宽, 居中
 *
 * Props:
 *   onToggleHistory?: 左 HistoryChip 点击回调 (toggle 会话列表面板)
 *   onCreateSession?: 右 NewChatPlusButton 点击回调 (直接新建会话)
 */

import { S_1, S_2, S_3, S_4 } from 'common';
import { HistoryChip } from './HistoryChip';
import { NewChatPlusButton } from './NewChatPlusButton';

@Component
export struct ChatHeader {
  onToggleHistory?: () => void = (): void => {};
  onCreateSession?: () => void = (): void => {};

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 底层: HistoryChip (左) + Blank + NewChatPlusButton (右)
      Row() {
        HistoryChip({ onTap: this.onToggleHistory })

        Blank()

        NewChatPlusButton({ onTap: this.onCreateSession })
      }
      .width('100%')
      .height(44)
      .alignItems(VerticalAlign.Center)
      .padding({ left: S_4, right: S_3, top: S_2, bottom: S_1 });

      // 覆盖层: 标题 (占整行宽, textAlign.Center 居中到整行水平中点)
    }
    .width('100%')
    .height(44);
  }
}
