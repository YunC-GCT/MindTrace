// ============================================================================
//  pages/MainTabs/TabBar.ets — 五入口底部导航容器
//  ----------------------------------------------------------------------------
//  职责: 承载 4 个页面入口与中央 AI 入口，提供统一底栏背景和中央承托层。
//  来源: 从 Index.ets 提取内联 TabBar Row。
//  数据流: @Prop cur + onTabChange callback 通知父组件切换。
//  接口:
//    @Prop  cur      — 当前选中 Tab 索引
//    onTabChange      — (index: number) => void
//    onAiTap           — AI 按钮点击回调
//  依赖: HomeTabButton, NotesTabButton, AiTabButton, ReviewTabButton,
//       ProfileTabButton (pages/MainTabs)
//  ============================================================================

import {
  TAB_NAV_BG, TAB_NAV_BORDER,
  TAB_BAR_HEIGHT, TAB_ROW_HEIGHT, TAB_BOTTOM_PADDING,
  S_6,
} from "common"
import { HomeTabButton } from "./HomeTabButton"
import { NotesTabButton } from "./NotesTabButton"
import { AiTabButton } from "./AiTabButton"
import { ReviewTabButton } from "./ReviewTabButton"
import { ProfileTabButton } from "./ProfileTabButton"
import { TabBarCrest } from "./TabBarCrest"

@Component
export struct TabBar {
  @Prop cur: number = 0
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0
  onTabChange: (i: number) => void = (_i: number): void => {}
  onAiTap: () => void = (): void => {}

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 背景延伸到系统手势区，原生手势条由系统绘制。
      Row()
        .width("100%").height(TAB_ROW_HEIGHT + Math.max(S_6, this.navigationBarHeight))
        .backgroundColor(TAB_NAV_BG)
        .border({ width: { top: 0.7 }, color: TAB_NAV_BORDER })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])

      Column() {
        TabBarCrest()
      }
      .width("100%").height(TAB_BAR_HEIGHT + Math.max(S_6, this.navigationBarHeight))
      .hitTestBehavior(HitTestMode.None)

      Row() {
        HomeTabButton({
          active: this.cur === 0,
          onTap: (): void => { this.onTabChange(0) },
        })
        NotesTabButton({
          active: this.cur === 1,
          onTap: (): void => { this.onTabChange(1) },
        })

        AiTabButton({ onTap: (): void => { this.onAiTap() } })

        ReviewTabButton({
          active: this.cur === 3,
          onTap: (): void => { this.onTabChange(3) },
        })
        ProfileTabButton({
          active: this.cur === 4,
          onTap: (): void => { this.onTabChange(4) },
        })
      }
      .width("100%").height(TAB_BAR_HEIGHT + Math.max(S_6, this.navigationBarHeight))
      .padding({ left: 10, right: 10, bottom: TAB_BOTTOM_PADDING + Math.max(S_6, this.navigationBarHeight) })
      .alignItems(VerticalAlign.Bottom)
    }
    .width("100%").height(TAB_BAR_HEIGHT + Math.max(S_6, this.navigationBarHeight))
  }
}
