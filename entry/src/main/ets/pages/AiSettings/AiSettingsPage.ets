// ============================================================================
//  pages/AiSettings/AiSettingsPage.ets - ai settings shell
// ============================================================================

import { BG_CARD, BG_DARK, BORDER, MINT, TEXT, TEXT_3, F_MD, F_SM, F_XS, W_SEMIBOLD, R_LG, R_MD, S_2, S_4, LocalChatProvider } from "common"
import { KeyboardAvoidMode, promptAction } from "@kit.ArkUI"
import { PageHeader } from "./PageHeader"
import { ConnectionStatus } from "./ConnectionStatus"
import { ActionBar } from "./ActionBar"
import { VendorPicker } from "./VendorPicker"
import { OcrConfigSection } from "./OcrConfigSection"
import { OnDeviceModelSection } from "./OnDeviceModelSection"
import { XiaoyiEntrySection } from "./XiaoyiEntrySection"
import { AiSettingsViewModel } from "../../viewmodels/AiSettingsViewModel"
import { DebugFaults } from "../../services/DebugFaults"
import type { DebugFault } from "../../services/DebugFaults"

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
  // issue #221: 端侧能力位(只读可观测)
  @State onDeviceAvailable: boolean = false
  @State onDeviceStatus: string = ''
  // #224 调试入口: 默认隐藏; 连点标题 5 次后出现
  @State debugVisible: boolean = false
  @State debugFault: string = 'none'
  private titleTapCount: number = 0
  private titleLastTapAt: number = 0

  aboutToAppear(): void {
    try {
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET)
    } catch (_e) {}
    this.reload()
    // #224: 页面显式传 Context 读一次持久化档位(服务侧异步链路取不到 Context 时也能回填 UI)
    DebugFaults.load(getContext(this)).then((v: DebugFault): void => {
      this.debugFault = v
    }).catch((_e: Error): void => {})
    // issue #221 修订: 端侧就绪以系统问答模型 init() 结果为准(不再看模型文件)
    this.onDeviceStatus = '检测中…'
    try {
      const provider: LocalChatProvider = new LocalChatProvider()
      provider.init().then((ready: boolean): void => {
        this.onDeviceAvailable = ready
        this.onDeviceStatus = ready ? '' : '系统端侧问答模型初始化失败（设备不支持或模型未就绪）'
      }).catch((e: Error): void => {
        this.onDeviceAvailable = false
        this.onDeviceStatus = '端侧状态读取失败：' + e.message
      })
    } catch (_e) {
      this.onDeviceAvailable = false
      this.onDeviceStatus = '端侧状态读取失败'
    }
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

  private saveLlm = (): void => {
    this.vm.saveLlm().then((ok: boolean): void => {
      try {
        promptAction.showToast({ message: ok ? "模型设置已保存" : "模型设置保存失败", duration: 1500 })
      } catch (_e) {}
    })
  }

  private saveOcr = (): void => {
    this.vm.saveOcr().then((ok: boolean): void => {
      try {
        promptAction.showToast({ message: ok ? "OCR 配置已保存" : "OCR 配置保存失败", duration: 1500 })
      } catch (_e) {}
    })
  }

  private resetOcr = (): void => {
    this.vm.resetOcr().then((ok: boolean): void => {
      if (!ok) {
        try { promptAction.showToast({ message: "OCR 重置失败", duration: 1500 }) } catch (_e) {}
      }
    })
  }

  private test = (): void => {
    this.vm.test().then((ok: boolean): void => {
      if (!ok) {
        try { promptAction.showToast({ message: this.vm.statusText, duration: 1500 }) } catch (_e) {}
      }
    })
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

  // #224 隐藏入口: 2s 内连点标题 5 次展开调试行
  private onTitleTap = (): void => {
    const now: number = Date.now()
    if (now - this.titleLastTapAt > 2000) {
      this.titleTapCount = 0
    }
    this.titleLastTapAt = now
    this.titleTapCount += 1
    if (this.titleTapCount < 5) {
      return
    }
    this.titleTapCount = 0
    const alreadyVisible: boolean = this.debugVisible
    this.debugVisible = true
    if (!alreadyVisible) {
      try { promptAction.showToast({ message: '调试入口已开启', duration: 1500 }) } catch (_e) {}
    }
  }

  private selectDebugFault = (value: DebugFault): void => {
    this.debugFault = value
    DebugFaults.set(value).then((): void => {
      const label: string = value === 'empty' ? '空流' : (value === 'interrupted' ? '中断' : '正常')
      try { promptAction.showToast({ message: '调试故障：' + label, duration: 1500 }) } catch (_e) {}
    }).catch((_e: Error): void => {
      try { promptAction.showToast({ message: '调试故障设置失败', duration: 1500 }) } catch (_e) {}
    })
  }

  @Builder
  debugChip(label: string, value: DebugFault) {
    Text(label)
      .fontSize(F_XS)
      .fontColor(this.debugFault === value ? '#FFFFFF' : TEXT_3)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(32)
      .backgroundColor(this.debugFault === value ? MINT : '#0AFFFFFF')
      .borderRadius(R_MD)
      .margin({ left: value === 'none' ? 0 : 6 })
      .onClick((): void => { this.selectDebugFault(value) })
  }

  build() {
    Column() {
      Row().width("100%").height(this.sbh).backgroundColor(BG_DARK)
      Stack() {
        PageHeader({ title: "AI 设置" })
        // #224 隐藏入口: 透明标题覆盖层, 2s 内连点 5 次展开调试行(不影响左侧返回)
        Text("AI 设置")
          .fontSize(F_MD)
          .fontWeight(W_SEMIBOLD)
          .fontColor(Color.Transparent)
          .padding({ left: 24, right: 24, top: S_2, bottom: S_2 })
          .onClick((): void => { this.onTitleTap() })
      }
      .width("100%")
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
            activeVendorModels: this.vm.activeVendorModels,
            modelContextWindows: this.vm.modelContextWindows,
            customVendors: this.vm.customVendors,
            onSelect: (id: string): void => { this.vm.selectVendor(id) },
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
            onSelectModel: (vendorId: string, model: string): void => {
              this.vm.selectVendorModel(vendorId, model)
            },
            onContextWindowChange: (vendorId: string, model: string, value: number): void => {
              this.vm.setModelContextWindow(vendorId, model, value)
            },
            onSaveEdit: (_vendorId: string): void => {
              this.saveLlm()
            },
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

          OnDeviceModelSection({
            available: this.onDeviceAvailable,
            statusText: this.onDeviceStatus,
          })

          // #224 调试行: 仅在连点标题 5 次后可见
          if (this.debugVisible) {
            Column() {
              Text('调试：流式故障注入')
                .fontSize(F_XS)
                .fontColor(TEXT_3)
                .width('100%')
              Row() {
                this.debugChip('正常', 'none')
                this.debugChip('空流', 'empty')
                this.debugChip('中断', 'interrupted')
              }
              .width('100%')
              .margin({ top: 6 })
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .margin({ left: 8, right: 8 })
            .borderRadius(R_LG)
            .backgroundColor(BG_CARD)
          }

          // issue #225: 应用内「问小艺」入口（不可用时只显示提示行）
          XiaoyiEntrySection()

          Blank().height(40)
        }
        .width("100%")
      }
      .layoutWeight(1)
      // PR2-T2 ticket #83 follow-up (2026-09-08): ActionBar 移出 Scroll,save 按钮永远可见
      // (页面太长 + edit panel 展开后用户在 Scroll 底部,save 不可见)
      ActionBar({ onReset: (): void => { this.resetOcr() }, onSave: (): void => { this.saveOcr() } })
    }
    .width("100%")
    .height("100%")
    .backgroundColor(BG_DARK)
  }
}
