// ============================================================================
//  pages/AiSettings/AiSettingsPage.ets - ai settings shell
// ============================================================================

import { BG_DARK, BORDER, MINT, TEXT, TEXT_3, TEXT_4, F_SM, F_XS, W_SEMIBOLD, R_MD, S_2, S_3, S_4 } from "common"
import { KeyboardAvoidMode, promptAction } from "@kit.ArkUI"
import { PageHeader } from "./PageHeader"
import { ConnectionStatus } from "./ConnectionStatus"
import { ActionBar } from "./ActionBar"
import { VendorPicker } from "./VendorPicker"
import { OcrConfigSection } from "./OcrConfigSection"
import { AiSettingsViewModel } from "../../viewmodels/AiSettingsViewModel"

// PR2-T2 P3: 添加新供应商 modal 4 字段 cfg
// 与 VendorPicker.ets AddCustomVendorCfg 同步(DRY 妥协 — ArkTS 1.1 不允许 inline object literal as type)
interface AddCustomVendorCfg {
  name: string
  baseUrl: string
  apiKey: string
  firstModel: string
}

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
        try { promptAction.showToast({ message: "配置加载失败", duration: 1500 }) } catch (_e) {}
      }
    })
  }

  private save(): void {
    this.vm.save().then((ok: boolean): void => {
      try {
        promptAction.showToast({ message: ok ? "已保存" : "保存失败", duration: 1500 })
      } catch (_e) {}
    })
  }

  private reset(): void {
    this.vm.reset().then((ok: boolean): void => {
      if (!ok) {
        try { promptAction.showToast({ message: "重置失败", duration: 1500 }) } catch (_e) {}
      }
    })
  }

  private test(): void {
    if (this.vm.apiKey.trim().length === 0) {
      try { promptAction.showToast({ message: "请先输入 API Key", duration: 1500 }) } catch (_e) {}
      return
    }
    this.vm.test()
  }

  private modelSummary(): string {
    return this.vm.getCurrentModel()
  }

  private endpointSummary(): string {
    return this.vm.getCurrentEndpoint()
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
            ConnectionStatus({
              configured: this.vm.configured,
              statusText: this.vm.statusText,
              testing: this.vm.testing,
              onTest: (): void => { this.test() },
            })

          Column() {
            Row() {
              // 圆环 icon(外环 + 内点) — PR2-T2 polish ticket #81 task A2 对齐 v6 设计稿
              Stack() {
                Circle()
                  .width(20)
                  .height(20)
                  .fill('transparent')
                  .stroke(MINT)
                  .strokeWidth(2)
                Circle()
                  .width(8)
                  .height(8)
                  .fill(MINT)
              }
              .width(20)
              .height(20)
              .margin({ right: 8 })

              Text("AI 服务")
                .fontSize(F_SM)
                .fontColor(TEXT)
                .fontWeight(W_SEMIBOLD)
            }
            .alignItems(VerticalAlign.Center)
            // PR2-T2 P4: 用 vendor 单一真理源解析(替代旧 modelSummary/endpointSummary 关键字嗅探)
            Text(`${this.vm.getCurrentVendor()} · 当前 ${this.vm.getCurrentModel()} · ${this.vm.getCurrentEndpoint()}`)
              .fontSize(F_XS)
              .fontColor(TEXT_3)
              .margin({ top: 4 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width("100%")
          .padding({ left: S_4, right: S_4, top: S_4, bottom: S_2 })

          Column() {
            Text("服务厂商")
              .fontSize(F_SM)
              .fontColor(TEXT)
              .fontWeight(W_SEMIBOLD)
            // v6 设计稿 subtitle — PR2-T2 polish ticket #81 task A3
            Text("5 预设 + 你添加的供应商。模型行点左侧'线 + 圆'切换当前 model。")
              .fontSize(F_XS)
              .fontColor(TEXT_3)
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Start)
          .padding({ left: S_4, right: S_4, top: S_4, bottom: S_2 })
          .width('100%')

          VendorPicker({
            currentVendorId: this.vm.vendorId,
            // PR2-T2 ticket #83 L1+L2+L3 (2026-09-08): per-vendor 数据从 VM 注入
            vendorApiKeys: this.vm.vendorApiKeys,
            vendorModels: this.vm.vendorModels,
            onSelect: (id: string): void => { this.vm.selectVendor(id) },
            // onEdit 不传: VendorPicker 自管 panel 展开(@State editingVendorId),
            // 单真理源架构,无需 ViewModel 介入。
            onAddCustom: (): void => { this.vm.openAddCustomVendor() },
            // PR2-T2 P3: modal 确认后回调,把 4 字段 cfg 传给 ViewModel
            // PR2-T2 polish: 返回新 vendorId 用于 NEW badge 跟踪(ticket #81 task A4)
            onAddVendorConfirm: (cfg: AddCustomVendorCfg): string => {
              return this.vm.addCustomVendor(cfg.name, cfg.baseUrl, cfg.apiKey, cfg.firstModel)
            },
            // PR2-T2 ticket #83 L3 (2026-09-08): per-vendor API Key 实时回调
            onApiKeyChange: (vendorId: string, key: string): void => {
              this.vm.setVendorApiKey(vendorId, key)
            },
            // PR2-T2 ticket #83 L2 (2026-09-08): per-vendor models UI 动作
            onAddModel: (vendorId: string, model: string): void => {
              this.vm.addVendorModel(vendorId, model)
            },
            onRemoveModel: (vendorId: string, model: string): void => {
              this.vm.removeVendorModel(vendorId, model)
            },
          })

          // PR2-T2 ticket #83 follow-up (2026-09-08): LLM section 专用 "保存模型设置" 按钮
          // user 反馈"我这里无法保存这些密钥信息" — 显式 LLM save 入口,不依赖底部 ActionBar
          // 仅存 LLM(不存 OCR),底部 ActionBar 仍负责 OCR
          Row() {
            Text('保存模型设置')
              .fontSize(F_SM)
              .fontColor(BG_DARK)
              .fontWeight(W_SEMIBOLD)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .padding(12)
              .backgroundColor(MINT)
              .borderRadius(R_MD)
              .onClick((): void => {
                this.vm.save().then((ok: boolean): void => {
                  try {
                    promptAction.showToast({
                      message: ok ? '模型设置已保存' : '保存失败',
                      duration: 1500,
                    })
                  } catch (_e) {}
                })
              })
          }
          .width('100%')
          .padding({ left: S_4, right: S_4, top: S_2, bottom: S_2 })

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

          Blank().height(40)
        }
        .width("100%")
      }
      .layoutWeight(1)
      // PR2-T2 ticket #83 follow-up (2026-09-08): ActionBar 移出 Scroll,save 按钮永远可见
      // (页面太长 + edit panel 展开后用户在 Scroll 底部,save 不可见)
      ActionBar({ onReset: (): void => { this.reset() }, onSave: (): void => { this.save() } })
    }
    .width("100%")
    .height("100%")
    .backgroundColor(BG_DARK)
  }
}
