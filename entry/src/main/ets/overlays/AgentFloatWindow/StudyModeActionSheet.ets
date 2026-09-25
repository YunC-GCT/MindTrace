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
import type { NoteGenerationRoute } from 'common';

interface StudyModePopupStateEvent {
  isVisible: boolean;
}

@Component
export struct StudyModeActionSheet {
  @State showPopup: boolean = false;
  @Prop selectedRoute: NoteGenerationRoute = 'standard';
  onRouteChange?: (route: NoteGenerationRoute) => void = (_route: NoteGenerationRoute): void => {};

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      ModeChip({
        label: this.routeLabel(this.selectedRoute),
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
        selected: this.selectedRoute === 'light',
        onTap: (): void => {
          this.selectRoute('light');
        },
      })
      StandardModeChip({
        selected: this.selectedRoute === 'standard',
        onTap: (): void => {
          this.selectRoute('standard');
        },
      })
      DeepModeChip({
        selected: this.selectedRoute === 'deep',
        onTap: (): void => {
          this.selectRoute('deep');
        },
      })
    }
    .padding(S_2)
    .backgroundColor(BG_CARD)
    .borderRadius(R_LG)
    .border({ width: 1, color: BORDER });
  }

  private selectRoute(route: NoteGenerationRoute): void {
    if (this.onRouteChange) {
      this.onRouteChange(route);
    }
    this.showPopup = false;
  }

  private routeLabel(route: NoteGenerationRoute): string {
    if (route === 'light') {
      return LIGHT_MODE_LABEL;
    }
    if (route === 'deep') {
      return DEEP_MODE_LABEL;
    }
    return STANDARD_MODE_LABEL;
  }
}
