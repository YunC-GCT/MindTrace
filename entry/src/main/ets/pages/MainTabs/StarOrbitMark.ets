/**
 * StarOrbitMark.ets — 星轨 AI 入口图形
 *
 * 路径: entry/src/main/ets/pages/MainTabs/StarOrbitMark.ets
 * 职责: 复用 AppIcon 的 Orbit 图形，配置底栏尺寸与颜色。
 * 层级: 页面局部展示组件；状态: orbitSize 尺寸输入。
 * 依赖: common 令牌、AppIcon；不依赖业务状态。
 * 数据流: AiTabButton → AppIcon。
 */

import { AI_ICON_SIZE, TAB_NAV_ACTIVE } from "common"
import { AppIcon } from "../../shared/atoms/AppIcon"

@Component
export struct StarOrbitMark {
  @Prop orbitSize: number = AI_ICON_SIZE

  build() {
    AppIcon({ name: "ai", iconSize: this.orbitSize, color: TAB_NAV_ACTIVE, strokeWidth: 1.6 })
  }
}
