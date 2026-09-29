/**
 * ReviewQueueMoveButton.ets — 无底色的复习队列移动按钮
 * 路径: entry/src/main/ets/pages/Review/ReviewQueueMoveButton.ets
 * 职责: 显示上移/下移 SVG 并发出移动意图。
 * 依赖: common 颜色令牌、队列方向 SVG。
 * 数据流: ReviewPlanRow → moveUp / color → onTap。
 */
import { MINT } from 'common'

@Component
export struct ReviewQueueMoveButton {
  @Prop moveUp: boolean = true
  @Prop color: ResourceColor = MINT
  onTap: () => void = (): void => {}

  build() {
    Button({ type: ButtonType.Normal }) {
      Image(this.moveUp ? $r('app.media.review_queue_up') : $r('app.media.review_queue_down'))
        .width(23)
        .height(23)
        .fillColor(this.color)
    }
    .width(40)
    .height(40)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .accessibilityText(this.moveUp ? '移入实时队列' : '移回复习队列')
    .onClick((): void => this.onTap())
  }
}
