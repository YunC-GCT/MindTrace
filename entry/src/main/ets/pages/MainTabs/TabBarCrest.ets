/**
 * TabBarCrest.ets — 一体底栏的中央弧形背景
 * 路径: entry/src/main/ets/pages/MainTabs/TabBarCrest.ets
 * 层级: 页面局部展示组件；状态: 无。
 * 职责: 复用草稿的贝塞尔轮廓，遮住中央直线接缝。
 * 依赖: common 尺寸令牌与 tab_crest SVG。
 * 数据流: TabBar → 装饰背景，不处理点击。
 */
import { TAB_CREST_WIDTH, TAB_CREST_HEIGHT } from "common"

@Component
export struct TabBarCrest {
  build() {
    Image($r("app.media.tab_crest"))
      .width(TAB_CREST_WIDTH)
      .height(TAB_CREST_HEIGHT + 1)
      .hitTestBehavior(HitTestMode.None)
  }
}
