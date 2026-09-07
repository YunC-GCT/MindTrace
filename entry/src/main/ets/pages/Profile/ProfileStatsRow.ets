// ============================================================================
//  pages/Profile/ProfileStatsRow.ets — 我的页统计方块行
//  ----------------------------------------------------------------------------
//  职责: 横向 3 个统计方块(笔记/掌握率/今日新增)。
//
//  布局:
//    [StatsBox "笔记"] [StatsBox "掌握率"] [StatsBox "今日新增"]
//
//  依赖:
//    shared: StatsBox
//    common 令牌: S_4
//
//  Props:
//    notes: 笔记总数
//    avg:   掌握率(整数 %)
//    today: 今日新增笔记数
//  ============================================================================

import { S_4 } from "common"
import { StatsBox } from "../../shared/atoms/StatsBox"

@Component
export struct ProfileStatsRow {
  // 笔记总数
  @Prop notes: number = 0

  // 掌握率(整数 %)
  @Prop avg: number = 0

  // 今日新增笔记数
  @Prop today: number = 0

  build() {
    Row() {
      // 笔记数
      StatsBox({ value: this.notes + "", label: "笔记" })

      // 掌握率
      StatsBox({ value: this.avg + "%", label: "掌握率" })

      // 今日新增
      StatsBox({ value: this.today + "", label: "今日新增" })
    }
    .width("100%")
    .padding({ left: S_4, right: S_4, bottom: S_4 })
    .justifyContent(FlexAlign.SpaceEvenly)
  }
}
