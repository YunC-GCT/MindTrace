/**
 * BatchAction.ets — AI 浮窗 + 按钮弹出菜单中的「批量」动作胶囊
 *
 * 路径: entry/src/main/ets/overlays/AgentFloatWindow/BatchAction.ets
 * 职责: 44×44 圆角按钮, 文案「批量」, 点击进入多选整理（spec 031 P2/P3 收口）
 * 依赖: common (TEXT, GLASS_10, R_LG)
 */
import { TEXT, GLASS_10, R_LG } from 'common';

@Component
export struct BatchAction {
  onTap?: () => void = (): void => {};

  build() {
    Column() {
      Text('批量')
        .fontSize(12)
        .fontColor(TEXT)
    }
    .width(44)
    .height(44)
    .borderRadius(R_LG)
    .backgroundColor(GLASS_10)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .onClick((): void => {
      if (this.onTap) {
        this.onTap();
      }
    });
  }
}
