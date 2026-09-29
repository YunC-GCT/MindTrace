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
//  依赖: TabButton, AiTabButton (pages/MainTabs)
//  ============================================================================

import {
  MINT_BORDER, BG_DARK, BORDER,
  S_1, S_2, S_4,
  TAB_BAR_HEIGHT, AI_BTN_SIZE,
} from "common"
import { TabButton } from "./TabButton"
import { AiTabButton } from "./AiTabButton"

interface TabItem {
  idx: number
  name: string
  icon: Resource
}

const TABS: TabItem[] = [
  { idx: 0, name: "首页", icon: $r("app.media.ic_home") },
  { idx: 1, name: "笔记", icon: $r("app.media.ic_notes") },
  { idx: 2, name: "AI",   icon: $r("app.media.ic_ai") },
  { idx: 3, name: "复习", icon: $r("app.media.ic_review") },
  { idx: 4, name: "我的", icon: $r("app.media.ic_me") },
]

@Component
export struct TabBar {
  @Prop cur: number = 0
  onTabChange: (i: number) => void = (_i: number): void => {}
  onAiTap: () => void = (): void => {}

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 背景层独立出来，中央承托层可以覆盖顶部边界，形成轻微的 AI 凹托。
      Row()
        .width("100%").height(TAB_BAR_HEIGHT)
        .padding({ left: S_1 + 2, right: S_1 + 2, bottom: S_2 + 2 })
        .linearGradient({
          angle: 180,
          colors: [["#00000000", 0], [BG_DARK, 1]],
        })
        .backdropBlur(24)
        .border({ width: { top: 1 }, color: BORDER })

      Row() {
        TabButton({
          icon: TABS[0].icon,
          label: TABS[0].name,
          active: this.cur === 0,
          onTap: (): void => { this.onTabChange(0) },
        })
        TabButton({
          icon: TABS[1].icon,
          label: TABS[1].name,
          active: this.cur === 1,
          onTap: (): void => { this.onTabChange(1) },
        })

        Stack() {
          Ellipse()
            .width(AI_BTN_SIZE + S_4)
            .height(AI_BTN_SIZE + S_2)
            .fill(BG_DARK)
            .stroke(MINT_BORDER)
            .strokeWidth(1)

          AiTabButton({ onTap: (): void => { this.onAiTap() } })
        }
        .layoutWeight(1)
        .height(TAB_BAR_HEIGHT)
        .alignContent(Alignment.Bottom)

        TabButton({
          icon: TABS[3].icon,
          label: TABS[3].name,
          active: this.cur === 3,
          onTap: (): void => { this.onTabChange(3) },
        })
        TabButton({
          icon: TABS[4].icon,
          label: TABS[4].name,
          active: this.cur === 4,
          onTap: (): void => { this.onTabChange(4) },
        })
      }
      .width("100%").height(TAB_BAR_HEIGHT)
      .padding({ left: S_1 + 2, right: S_1 + 2, bottom: S_2 + 2 })
      .justifyContent(FlexAlign.SpaceAround)
      .alignItems(VerticalAlign.Bottom)
    }
    .width("100%").height(TAB_BAR_HEIGHT)
  }
}
