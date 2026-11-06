/**
 * EmbeddingConfigSection.ets — 检索向量化配置区块
 *
 * 路径: entry/src/main/ets/pages/AiSettings/EmbeddingConfigSection.ets
 * 职责: 提供语义检索开关、embedding 模型名输入与自检入口；
 *       纯展示组件，读写都走 AiSettingsViewModel。
 * 依赖: common 主题 token。
 */

import { BG_CARD, TEXT, TEXT_3, TEXT_4, R_MD, R_LG, F_XS, F_SM } from 'common'

@Component
export struct EmbeddingConfigSection {
  @Prop isEnabled: boolean = false
  @Prop model: string = ''
  @Prop endpoint: string = ''
  @Prop apiKey: string = ''
  @Prop statusText: string = ''
  @Prop testing: boolean = false

  onEnabledChange?: (v: boolean) => void = (_v: boolean): void => {}
  onModelChange?: (v: string) => void = (_v: string): void => {}
  onEndpointChange?: (v: string) => void = (_v: string): void => {}
  onApiKeyChange?: (v: string) => void = (_v: string): void => {}
  onTest?: () => void = (): void => {}

  build() {
    Column() {
      Row() {
        Text('语义检索（云端 embedding）')
          .fontSize(F_SM)
          .fontColor(TEXT)
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.isEnabled })
          .onChange((v: boolean): void => {
            if (this.onEnabledChange) {
              this.onEnabledChange(v)
            }
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })

      Row() {
        TextInput({ text: this.model, placeholder: '如 text-embedding-v4' })
          .layoutWeight(1)
          .height(44)
          .fontSize(F_XS)
          .fontColor(TEXT)
          .placeholderColor(TEXT_4)
          .backgroundColor('#0AFFFFFF')
          .borderRadius(R_MD)
          .padding({ left: 8, right: 8 })
          .enabled(this.isEnabled)
          .onChange((v: string): void => {
            if (this.onModelChange) {
              this.onModelChange(v)
            }
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 0, bottom: 8 })

      Row() {
        TextInput({ text: this.endpoint, placeholder: '接口地址，如 https://open.bigmodel.cn/api/paas/v4' })
          .layoutWeight(1)
          .height(44)
          .fontSize(F_XS)
          .fontColor(TEXT)
          .placeholderColor(TEXT_4)
          .backgroundColor('#0AFFFFFF')
          .borderRadius(R_MD)
          .padding({ left: 8, right: 8 })
          .enabled(this.isEnabled)
          .onChange((v: string): void => {
            if (this.onEndpointChange) {
              this.onEndpointChange(v)
            }
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 0, bottom: 8 })

      Row() {
        TextInput({ text: this.apiKey, placeholder: 'API Key（本地服务通常不需要，可留空）' })
          .type(InputType.Password)
          .layoutWeight(1)
          .height(44)
          .fontSize(F_XS)
          .fontColor(TEXT)
          .placeholderColor(TEXT_4)
          .backgroundColor('#0AFFFFFF')
          .borderRadius(R_MD)
          .padding({ left: 8, right: 8 })
          .enabled(this.isEnabled)
          .onChange((v: string): void => {
            if (this.onApiKeyChange) {
              this.onApiKeyChange(v)
            }
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 0, bottom: 8 })

      Row() {
        Text(this.statusText.length > 0 ? this.statusText : '未启用')
          .fontSize(F_XS)
          .fontColor(TEXT_3)
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Button(this.testing ? '...' : '测试')
          .fontSize(F_XS)
          .fontColor(TEXT)
          .height(34)
          .borderRadius(R_MD)
          .backgroundColor('#0AFFFFFF')
          .enabled(!this.testing && this.isEnabled)
          .onClick((): void => {
            if (this.onTest) {
              this.onTest()
            }
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 4, bottom: 8 })

      Row() {
        Text('使用 OpenAI 兼容的 /embeddings 接口，与聊天配置相互独立：可以指向任意厂商、'
          + '自建服务或本地推理服务。启用后笔记正文会发送到该接口以生成向量，'
          + '用于把「换个说法问同一件事」检索出来；关闭时只用本地全文检索。')
          .fontSize(F_XS)
          .fontColor(TEXT_4)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 0, bottom: 8 })
    }
    .width('100%')
    .borderRadius(R_LG)
    .backgroundColor(BG_CARD)
    .margin({ left: 8, right: 8 })
  }
}
