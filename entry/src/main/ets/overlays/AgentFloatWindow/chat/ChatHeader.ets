/**
 * ChatHeader.ets — 浮窗头部 (Stack overlay: 左 NewChatChip + 全行宽居中标题 + 右关闭)
 *
 * 路径: entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatHeader.ets
 * 职责: 浮窗顶部 (新建对话胶囊居左, 关闭按钮居右; 标题用 Stack overlay 占据整行宽度,
 *       textAlign.Center 自然居中到整个 ChatHeader 的水平中心)
 * 依赖: common ColorTokens + SVG Path; 子组件: NewChatChip
 *
 * 布局 (Stack overlay):
 *    [— 背景 Row: NewChatChip | X]
 *                会话 2           ← 覆盖层, 占整行宽, 居中
 *
 * Props:
 *   sessionTitle:  当前会话标题 (默认 "对话标题" 占位)
 *   onNewChat?:    新建对话回调
 *   onClose?:      关闭浮窗回调
 */

import { TEXT, TEXT_3, S_1, S_2, S_3, S_4, F_MD, W_SEMIBOLD } from "common";
import { NewChatChip } from './NewChatChip';

@Component
export struct ChatHeader {
  // 当前会话标题 (默认占位 "对话标题")
  sessionTitle: string = '对话标题';

  // 新建对话回调
  onNewChat?: () => void = (): void => {};

  // 关闭回调
  onClose?: () => void = (): void => {};

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 底层: NewChatChip (左) + ✕ (右)
      Row() {
        NewChatChip({ onTap: this.onNewChat })

        Blank()

        // 右: ✕ 关闭浮窗 (Path 画 X,不用 emoji)
        Stack() {
          Path()
            .width(14).height(14)
            .commands("M18 6 L6 18 M6 6 L18 18")
            .stroke(TEXT_3)
            .strokeWidth(2)
            .strokeLineCap(LineCapStyle.Round)
            .fill(Color.Transparent)
        }
        .width(32).height(44)
        .alignContent(Alignment.Center)
        .onClick((): void => {
          if (this.onClose) { this.onClose(); }
        });
      }
      .width('100%')
      .height(44)
      .alignItems(VerticalAlign.Center)
      .padding({ left: S_4, right: S_3, top: S_2, bottom: S_1 });

      // 覆盖层: 标题 (占整行宽, textAlign.Center 居中到整行水平中点)
      Text(this.sessionTitle)
        .width('100%')
        .height(44)
        .textAlign(TextAlign.Center)
        .fontSize(F_MD)
        .fontColor(TEXT)
        .fontWeight(W_SEMIBOLD)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: S_3, right: S_3 })
        .position({ x: 0, y: 0 })
        .hitTestBehavior(HitTestMode.None);
    }
    .width('100%')
    .height(44);
  }
}
