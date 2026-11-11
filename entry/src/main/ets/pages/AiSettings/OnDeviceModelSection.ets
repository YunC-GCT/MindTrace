// ============================================================================
//  pages/AiSettings/OnDeviceModelSection.ets — 端侧模型能力位(只读可观测)
//  ----------------------------------------------------------------------------
//  职责: 在 AI 设置页展示端侧模型是否就绪、未就绪的原因；
//        未就绪时禁用「优先使用端侧模型」开关并给出提示。
//        本票只做“可观测”，开关的开启语义与偏好持久化由后续票实现。
//
//  依赖: common 令牌(BG_CARD / TEXT / TEXT_3 / TEXT_4 / R_MD / R_LG / F_XS / F_SM)
//
//  Props:
//    available:  端侧模型是否就绪(由 OnDeviceLlm.checkAvailability() 决定)
//    statusText: 未就绪时的原因;就绪时为空串
// ============================================================================

import { BG_CARD, TEXT, TEXT_3, TEXT_4, R_MD, R_LG, F_XS, F_SM } from 'common'

@Component
export struct OnDeviceModelSection {
  // 端侧模型是否就绪
  @Prop available: boolean = false

  // 未就绪原因;就绪时为空串
  @Prop statusText: string = ''

  build() {
    Column() {
      // 状态行: 端侧模型：就绪 / 未就绪（原因）
      Row() {
        Row() {
          Text(`端侧模型：${this.available ? '就绪' : '未就绪' + (this.statusText.length > 0 ? '（' + this.statusText + '）' : '')}`)
            .fontSize(F_SM)
            .fontColor(this.available ? TEXT : TEXT_3)
            .layoutWeight(1)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .borderRadius(R_MD)
        .backgroundColor('#0AFFFFFF')
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 8 })

      // 开关行: v1 端侧恒为不可用,开关只做能力位展示;开启语义留给后续票
      Row() {
        Text('优先使用端侧模型')
          .fontSize(F_SM)
          .fontColor(this.available ? TEXT : TEXT_3)
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: false })
          .enabled(this.available)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 0, bottom: 8 })

      if (!this.available) {
        Row() {
          Text('端侧模型未就绪，暂不可开启')
            .fontSize(F_XS)
            .fontColor(TEXT_4)
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 0, bottom: 12 })
      }
    }
    .width('100%')
    .borderRadius(R_LG)
    .backgroundColor(BG_CARD)
    .margin({ left: 8, right: 8 })
  }
}
