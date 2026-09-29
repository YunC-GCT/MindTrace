/**
 * StarOrbitMark.ets — 星轨 AI 入口图形
 *
 * 路径: entry/src/main/ets/pages/MainTabs/StarOrbitMark.ets
 * 职责: 用 ArkUI 基础图形绘制双轨道、中心星核和轨道卫星。
 * 依赖: common 设计令牌；不依赖业务状态。
 */

import { MINT, MINT_LIGHT } from "common"

@Component
export struct StarOrbitMark {
  @Prop orbitSize: number = 30
  @Prop color: ResourceColor = MINT

  build() {
    Stack() {
      Ellipse()
        .width(this.orbitSize * 0.92)
        .height(this.orbitSize * 0.34)
        .fill(Color.Transparent)
        .stroke(this.color)
        .strokeWidth(1.15)
        .rotate({ angle: 24 })

      Ellipse()
        .width(this.orbitSize * 0.92)
        .height(this.orbitSize * 0.34)
        .fill(Color.Transparent)
        .stroke(this.color)
        .strokeWidth(1.15)
        .rotate({ angle: -24 })

      Circle({ width: this.orbitSize * 0.34, height: this.orbitSize * 0.34 })
        .fill(MINT_LIGHT)
        .stroke(this.color)
        .strokeWidth(1)

      Circle({ width: this.orbitSize * 0.11, height: this.orbitSize * 0.11 })
        .fill(this.color)
        .translate({ x: this.orbitSize * 0.39, y: -this.orbitSize * 0.15 })
    }
    .width(this.orbitSize)
    .height(this.orbitSize)
    .alignContent(Alignment.Center)
  }
}
