// ============================================================================
//  pages/AiSettings/AiSettingsPage.ets - ai settings shell
// ============================================================================

import { BG_DARK, BORDER, TEXT, TEXT_3, TEXT_4, F_SM, F_XS, W_SEMIBOLD, S_2, S_3, S_4, Toast } from "common"
import { KeyboardAvoidMode, promptAction } from "@kit.ArkUI"
import { PageHeader } from "./PageHeader"
import { ConnectionStatus } from "./ConnectionStatus"
import { ActionBar } from "./ActionBar"
import { EndpointPicker } from "./EndpointPicker"
import { ModelPicker } from "./ModelPicker"
import { KeyInput } from "./KeyInput"
import { OcrConfigSection } from "./OcrConfigSection"
import { AiSettingsViewModel } from "../../viewmodels/AiSettingsViewModel"

@Entry
@Component
struct AiSettingsPage {
  @StorageProp("statusBarHeight") sbh: number = 0
  @State vm: AiSettingsViewModel = new AiSettingsViewModel()

  aboutToAppear(): void {
    try {
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET)
    } catch (_e) {}
    this.reload()
  }

  aboutToDisappear(): void {
    try {
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE)
    } catch (_e) {}
  }

  private reload(): void {
    this.vm.load().then((ok: boolean): void => {
      if (!ok) {
        try { promptAction.showToast({ message: Toast.CONFIG_LOAD_FAILED, duration: 1500 }) } catch (_e) {}
      }
    })
  }

  private save(): void {
    this.vm.save().then((ok: boolean): void => {
      try {
        promptAction.showToast({ message: ok ? Toast.PLAN_SAVE_OK : Toast.PLAN_SAVE_FAILED, duration: 1500 })
      } catch (_e) {}
    })
  }

  private reset(): void {
    this.vm.reset().then((ok: boolean): void => {
      if (!ok) {
        try { promptAction.showToast({ message: Toast.PLAN_RESET_FAILED, duration: 1500 }) } catch (_e) {}
      }
    })
  }

  private test(): void {
    if (this.vm.apiKey.trim().length === 0) {
      try { promptAction.showToast({ message: Toast.API_KEY_REQUIRED, duration: 1500 }) } catch (_e) {}
      return
    }
    this.vm.test()
  }

  private modelSummary(): string {
    return this.vm.modelLabel()
  }

  private endpointSummary(): string {
    if (this.vm.useCustomEP && this.vm.customEP.trim().length > 0) {
      return this.vm.customEP.trim()
    }
    return "DeepSeek 官方"
  }

  private ocrSummary(): string {
    if (!this.vm.ocrEnabled) {
      return "OCR 已关闭"
    }
    const modeLabel: string = this.vm.ocrMode === 'formula'
      ? '公式模式'
      : (this.vm.ocrMode === 'auto' ? '自动模式' : '快速模式')
    if (this.vm.ocrEndpoint.trim().length === 0) {
      return modeLabel + " / 未配置 OCR"
    }
    return modeLabel + " / " + this.vm.ocrEndpoint.trim()
  }

  build() {
    Column() {
      Row().width("100%").height(this.sbh).backgroundColor(BG_DARK)
      PageHeader({ title: "AI 设置" })
      Row().width("100%").height(0.5).backgroundColor(BORDER)

      Scroll() {
        Column() {
          ConnectionStatus({ configured: this.vm.configured, statusText: this.vm.statusText })

          Column() {
            Text("AI 服务")
              .fontSize(F_SM)
              .fontColor(TEXT)
              .fontWeight(W_SEMIBOLD)
            Text(this.modelSummary() + " · " + this.endpointSummary())
              .fontSize(F_XS)
              .fontColor(TEXT_3)
              .margin({ top: 4 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width("100%")
          .padding({ left: S_4, right: S_4, top: S_4, bottom: S_2 })

          Text("端点")
            .fontSize(F_XS)
            .fontColor(TEXT_3)
            .fontWeight(W_SEMIBOLD)
            .padding({ left: S_4, right: S_4, top: S_2, bottom: S_2 })

          EndpointPicker({
            useCustom: this.vm.useCustomEP,
            customText: this.vm.customEP,
            onToggle: (v: boolean): void => { this.vm.toggleCustomEndpoint(v) },
            onCustomChange: (v: string): void => { this.vm.setCustomEndpoint(v) },
          })

          Text("模型")
            .fontSize(F_XS)
            .fontColor(TEXT_3)
            .fontWeight(W_SEMIBOLD)
            .padding({ left: S_4, right: S_4, top: S_3, bottom: S_2 })

          ModelPicker({
            mdlIdx: this.vm.mdlIdx,
            useCustom: this.vm.useCustomMD,
            customText: this.vm.customMD,
            onSelect: (i: number): void => { this.vm.selectModel(i) },
            onToggle: (v: boolean): void => { this.vm.toggleCustomModel(v) },
            onCustomChange: (v: string): void => { this.vm.setCustomModel(v) },
          })

          Text("API Key")
            .fontSize(F_XS)
            .fontColor(TEXT_3)
            .fontWeight(W_SEMIBOLD)
            .padding({ left: S_4, right: S_4, top: S_3, bottom: S_2 })

          KeyInput({
            apiKey: this.vm.apiKey,
            testing: this.vm.testing,
            onChange: (v: string): void => { this.vm.setApiKey(v) },
            onTest: (): void => { this.test() },
          })

          Column() {
            Text("OCR 服务")
              .fontSize(F_SM)
              .fontColor(TEXT)
              .fontWeight(W_SEMIBOLD)
            Text(this.ocrSummary())
              .fontSize(F_XS)
              .fontColor(TEXT_3)
              .margin({ top: 4 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width("100%")
          .padding({ left: S_4, right: S_4, top: S_4, bottom: S_2 })

          OcrConfigSection({
            endpoint: this.vm.ocrEndpoint,
            isEnabled: this.vm.ocrEnabled,
            mode: this.vm.ocrMode,
            statusText: this.vm.ocrStatusText,
            testing: this.vm.ocrTesting,
            onEndpointChange: (v: string): void => { this.vm.setOcrEndpoint(v) },
            onEnabledChange: (v: boolean): void => { this.vm.setOcrEnabled(v) },
            onModeChange: (v: string): void => { this.vm.setOcrMode(v) },
            onReset: (): void => { this.vm.resetOcrEndpoint() },
            onTest: (): void => {
              this.vm.testOcr().then((ok: boolean): void => {
                try {
                  promptAction.showToast({
                    message: ok ? "OCR 连接正常" : this.vm.ocrStatusText,
                    duration: 1500,
                  })
                } catch (_e) {}
              })
            },
          })

          ActionBar({ onReset: (): void => { this.reset() }, onSave: (): void => { this.save() } })
          Blank().height(40)
        }
        .width("100%")
      }
      .layoutWeight(1)
    }
    .width("100%")
    .height("100%")
    .backgroundColor(BG_DARK)
  }
}
