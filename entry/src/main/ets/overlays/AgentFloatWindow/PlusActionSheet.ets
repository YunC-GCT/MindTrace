/**
 * PlusActionSheet.ets — AI 浮窗 + 按钮弹出菜单容器 (bindPopup)
 *
 * 路径: entry/src/main/ets/overlays/AgentFloatWindow/PlusActionSheet.ets
 * 职责: 包覆 PlusButton, 点击后向上弹出 3 个动作胶囊 (CameraAction / AlbumAction / FileAction)
 * 依赖: common; 子组件: PlusButton / CameraAction / AlbumAction / FileAction
 *
 * 视觉:
 *         ┌──────────────────────────────┐
 *         │  📷        🖼        📄       │  ← 弹窗 (Row, GLASS_8 底, R_LG)
 *         └──────────────────────────────┘
 *                       ▼
 *                    ┌─────┐
 *                    │  +  │                  ← PlusButton (触发器)
 *                    └─────┘
 *
 * 业务接入:
 *   onCamera?: 拍照 → 调父组件 onCameraAction → CameraKitLauncher
 *   onAlbum?:  选图 → 调父组件 onAlbumAction  → AlbumPickerLauncher
 *   FileAction: 暂未接入 (无 TODO)
 *
 * 状态管理:
 *   showPopup: @State boolean (本地管理, 不暴露)
 */

import {
  BG_CARD, BORDER,
  S_2, R_LG,
} from 'common';
import { PlusButton } from './PlusButton';
import { CameraAction } from './CameraAction';
import { AlbumAction } from './AlbumAction';
import { FileAction } from './FileAction';

interface PopupStateEvent {
  isVisible: boolean;
}

@Component
export struct PlusActionSheet {
  @State showPopup: boolean = false;

  onCamera?: () => void = (): void => {};
  onAlbum?: () => void = (): void => {};

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PlusButton({
        onTap: (): void => {
          this.showPopup = !this.showPopup;
        },
      })
    }
    .bindPopup($$this.showPopup, {
      builder: this.popupBuilder,
      placement: Placement.Top,
      popupColor: Color.Transparent,
      backgroundBlurStyle: BlurStyle.NONE,
      radius: R_LG,
      enableArrow: true,
      autoCancel: true,
      onStateChange: (e: PopupStateEvent): void => {
        if (!e.isVisible) {
          this.showPopup = false;
        }
      },
    });
  }

  @Builder
  popupBuilder() {
    Row({ space: S_2 }) {
      CameraAction({
        onTap: (): void => {
          this.showPopup = false;
          if (this.onCamera) {
            this.onCamera();
          }
        },
      })
      AlbumAction({
        onTap: (): void => {
          this.showPopup = false;
          if (this.onAlbum) {
            this.onAlbum();
          }
        },
      })
      FileAction({
        onTap: (): void => {
          this.showPopup = false;
        },
      })
    }
    .padding(S_2)
    .backgroundColor(BG_CARD)
    .borderRadius(R_LG)
    .border({ width: 1, color: BORDER });
  }
}
