/**
 * StudyModeActionSheet.ets — 学习模式纵向选择弹层
 *
 * 路径: entry/src/main/ets/overlays/AgentFloatWindow/StudyModeActionSheet.ets
 * 职责: 管理弹层显隐与纯前端模式选择, 选择后更新触发胶囊文案并收起弹层
 * 依赖: common; 子组件: ModeChip / LightModeChip / StandardModeChip / DeepModeChip
 *
 * 状态字段:
 *   showPopup:   弹层是否显示
 *   selectedMode: 当前前端选中的模式标签, 空字符串表示尚未选择
 */

import { BG_CARD, BORDER, S_2, R_LG } from 'common';
import { ModeChip } from './ModeChip';
import { LightModeChip, LIGHT_MODE_LABEL } from './LightModeChip';
import { StandardModeChip, STANDARD_MODE_LABEL } from './StandardModeChip';
import { DeepModeChip, DEEP_MODE_LABEL } from './DeepModeChip';

interface StudyModePopupStateEvent {
  isVisible: boolean;
}

@Component
export struct StudyModeActionSheet {
  @State showPopup: boolean = false;
  @State selectedMode: string = '';

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      ModeChip({
        label: this.selectedMode.length > 0 ? this.selectedMode : '学习模式',
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
      onStateChange: (event: StudyModePopupStateEvent): void => {
        if (!event.isVisible) {
          this.showPopup = false;
        }
      },
    });
  }

  @Builder
  popupBuilder() {
    Column({ space: S_2 }) {
      LightModeChip({
        selected: this.selectedMode === LIGHT_MODE_LABEL,
        onTap: (): void => {
          this.selectedMode = LIGHT_MODE_LABEL;
          this.showPopup = false;
        },
      })
      StandardModeChip({
        selected: this.selectedMode === STANDARD_MODE_LABEL,
        onTap: (): void => {
          this.selectedMode = STANDARD_MODE_LABEL;
          this.showPopup = false;
        },
      })
      DeepModeChip({
        selected: this.selectedMode === DEEP_MODE_LABEL,
        onTap: (): void => {
          this.selectedMode = DEEP_MODE_LABEL;
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
