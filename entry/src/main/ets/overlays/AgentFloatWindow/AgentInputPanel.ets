/**
 * AgentInputPanel.ets — AI 浮窗输入面板 (ViewModel 版)
 *
 * 路径: entry/src/main/ets/overlays/AgentFloatWindow/AgentInputPanel.ets
 * 职责: 外层面板容器, 自适应高度; 编排 ModeChip / PlusButton / SendButton
 * 依赖: common; 子组件: ModeChip / PlusButton / SendButton; ViewModel: AgentInputViewModel
 *
 * 布局:
 *   ┌─ 面板 (外层 Column, GLASS_8 底 + R_LG 圆角 + 1vp BORDER) ──┐
 *   │  TextArea  (minLines 1 / maxLines 4, 无 layoutWeight)    │
 *   │  placeholder: "给 MindTrace 发送消息"                     │
 *   │                                                          │
 *   │  Row (alignItems center):                                │
 *   │    ModeChip("模型选择")  ModeChip("学习模式")            │
 *   │                                PlusButton  SendButton    │
 *   └──────────────────────────────────────────────────────────┘
 *
 * Props:
 *   vm:        AgentInputViewModel (@ObjectLink, 状态 + 业务)
 *   modelName: 当前模型名 (显示在第一个 ModeChip 中)
 *   onCamera?:  + 弹窗 → 相机按钮 (转交至父组件 onCameraAction)
 *   onAlbum?:   + 弹窗 → 相册按钮 (转交至父组件 onAlbumAction)
 *   onStop?:    停止后副作用钩 (父组件清 statusMeta)
 * 胶囊: 暂无回调 (后续告知)
 */

import {
  TEXT, TEXT_3, BORDER,
  GLASS_8,
  S_2, S_3, R_LG,
  F_SM,
} from 'common';
import { ModeChip } from './ModeChip';
import { PlusActionSheet } from './PlusActionSheet';
import { SendButton } from './SendButton';
import { AgentInputViewModel } from '../../viewmodels/AgentInputViewModel';

@Component
export struct AgentInputPanel {
  @ObjectLink vm: AgentInputViewModel;
  @Prop modelName: string = '';

  onCamera?: () => void = (): void => {};
  onAlbum?: () => void = (): void => {};
  onStop?: () => void = (): void => {};

  build() {
    Column() {
      // === TextArea 多行输入 (自然高度, 1–4 行) ===
      TextArea({ text: this.vm.inputText, placeholder: '给 MindTrace 发送消息' })
        .width('100%')
        .minLines(1)
        .maxLines(4)
        .fontSize(F_SM)
        .fontColor(TEXT)
        .placeholderColor(TEXT_3)
        .backgroundColor(Color.Transparent)
        .padding({ left: S_3, right: S_3, top: S_2, bottom: S_2 })
        .onChange((value: string): void => {
          this.vm.updateText(value);
        });

      // === 底部控件行: 胶囊 (左) + PlusButton + SendButton (右) ===
      Row() {
        Row() {
          ModeChip({ label: this.modelName.length > 0 ? this.modelName : '模型选择' })
          ModeChip({ label: '学习模式' })
            .margin({ left: S_2 })
        }

        Blank()

        PlusActionSheet({
          onCamera: this.onCamera,
          onAlbum: this.onAlbum,
        })
        SendButton({
          busy: this.vm.busy,
          canSend: this.vm.canSend(),
          onSend: (): void => { this.vm.send(); },
          onStop: (): void => {
            this.vm.stop();
            if (this.onStop) {
              this.onStop();
            }
          },
        })
          .margin({ left: S_2 })
      }
      .width('100%')
      .margin({ top: S_2 })
      .alignItems(VerticalAlign.Center);
    }
    .width('100%')
    .backgroundColor(GLASS_8)
    .borderRadius(R_LG)
    .padding(S_3)
    .border({ width: 1, color: BORDER });
  }
}
