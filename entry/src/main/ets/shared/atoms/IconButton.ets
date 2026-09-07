// ============================================================================
//  shared/atoms/IconButton.ets — compact icon button atom
//  ----------------------------------------------------------------------------
//  spec 016 PR-C (issue #67, audit C5): 从 overlays/NoteDetailOverlay/NoteIconButton
//  提取。消费者 ≥4 处(NoteDetailOverlay.ets:91/135/143/150 + NoteActionBar.ets:16/18),
//  达 audit 门槛 ≥4。
//
//  Props:
//    name:        AppIcon name(lucide icon name 或 自定义名)
//    color:       图标色, 默认 TEXT_2
//    bgColor:     按钮底色, 默认 GLASS_10
//    boxSize:     按钮边长, 默认 36vp
//    iconSize:    图标边长, 默认 16vp
//    isEnabled:   是否启用(false 时变灰, 不响应 onTap)
//    onTap:       点击回调
//
//  依赖:
//    common 令牌: TEXT_2 / GLASS_10 / R_MD
//    shared:      AppIcon
//
//  Atom 级: 仅组合一个原子 + 基础事件, 不含业务逻辑。
// ============================================================================

import { GLASS_10, TEXT_2, R_MD } from 'common'
import { AppIcon } from './AppIcon'

@Component
export struct IconButton {
  @Prop name: string = 'edit'
  @Prop color: ResourceColor = TEXT_2
  @Prop bgColor: ResourceColor = GLASS_10
  @Prop boxSize: number = 36
  @Prop iconSize: number = 16
  @Prop isEnabled: boolean = true
  onTap: () => void = (): void => {}

  build() {
    Stack() {
      AppIcon({ name: this.name, iconSize: this.iconSize, color: this.isEnabled ? this.color : TEXT_2 })
    }
    .width(this.boxSize)
    .height(this.boxSize)
    .borderRadius(R_MD + 2)
    .backgroundColor(this.isEnabled ? this.bgColor : '#08FFFFFF')
    .alignContent(Alignment.Center)
    .onClick((): void => {
      if (this.isEnabled) {
        this.onTap()
      }
    })
  }
}