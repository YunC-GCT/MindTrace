/**
 * @file AiSettingsViewModel.ets — AI 设置页视图模型
 *
 * 职责：管理 API Key、端点、模型、OCR 配置的读写与连接测试。
 * 依赖：LlmConfig、OcrConfig、LlmClient、OcrTool
 */
import { LlmClient, LlmConfig, OcrConfig } from "common"
import type { CustomVendorConfig, ProviderConfig } from "common"
import { PROVIDERS } from "common"
import { DS_ENDPOINT } from "../pages/AiSettings/EndpointPicker"
import { PRO_MODEL } from "../pages/AiSettings/ModelPicker"
import { OcrTool } from "agents"
import type { OcrRecognitionResult } from "agents"

// PR2-T2 P3: 用户添加的自定义 vendor 列表
// (后续 PR 可扩 LlmConfig 加 KEY_CUSTOM_VENDORS 持久化;当前 in-memory)
// CustomVendorConfig = { vendorName, baseUrl, model }(common/providers.ets);apiKey 暂存 in-memory,后续接 AssetStoreKit
interface CustomVendorFull extends CustomVendorConfig {
  id: string
  apiKey: string
}

const DEFAULT_OCR_ENDPOINT: string = ""
const DEFAULT_OCR_MODE: string = "text"
const OCR_TEST_PNG_BYTES: number[] = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x04, 0x00, 0x00, 0x00, 0xB5, 0x1C, 0x0C, 0x02, 0x00, 0x00, 0x00,
  0x0B, 0x49, 0x44, 0x41, 0x54, 0x78, 0xDA, 0x63, 0xFC, 0xFF, 0x1F, 0x00,
  0x03, 0x03, 0x02, 0x00, 0xED, 0x1B, 0x17, 0xD9, 0x00, 0x00, 0x00, 0x00,
  0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]

@Observed
export class AiSettingsViewModel {
  apiKey: string = ""
  useCustomEP: boolean = false
  customEP: string = ""
  mdlIdx: number = 0
  useCustomMD: boolean = false
  customMD: string = ""
  configured: boolean = false
  testing: boolean = false
  statusText: string = "未配置"
  temp: number = 0.1
  maxT: number = 12000
  to: number = 120000
  ocrEndpoint: string = DEFAULT_OCR_ENDPOINT
  ocrEnabled: boolean = true
  ocrMode: string = DEFAULT_OCR_MODE
  ocrTesting: boolean = false
  ocrStatusText: string = "未测试"

  async load(): Promise<boolean> {
    let ok: boolean = true
    const llm: LlmConfig = LlmConfig.getInstance()
    try {
      // 全局 key — 仅作 fallback 显示(UI 已删全局 input)
      const key: string | null = await llm.getApiKey()
      this.apiKey = key === null ? "" : key
      this.configured = this.apiKey.trim().length > 0
      this.statusText = this.configured ? "已配置" : "未配置"
    } catch (_e) {
      ok = false
      this.apiKey = ""
      this.configured = false
      this.statusText = "未配置"
    }

    // PR2-T2 修复 C1 critical: load() 还原 vendorId — 不还原则刷新页面 vendor 选择回到默认值 'deepseek'
    this.vendorId = llm.getVendorId()

    // PR2-T2 ticket #83 L1 (2026-09-08): 还原 customVendors 数组
    const cvList: CustomVendorConfig[] = llm.getCustomVendors()
    this.customVendors = cvList.map(
      (v: CustomVendorConfig, i: number): CustomVendorFull => ({
        id: `custom-loaded-${i}-${Date.now()}`,
        vendorName: v.vendorName,
        baseUrl: v.baseUrl,
        model: v.model,
        apiKey: '',  // apiKey 在 L3 单独持久化,不在 customVendors JSON 里
      })
    )

    // PR2-T2 ticket #83 L2 (2026-09-08): 还原 per-vendor models
    this.vendorModels = {}
    for (const p of PROVIDERS) {
      this.vendorModels[p.id] = llm.getVendorModels(p.id)
    }

    // PR2-T2 ticket #83 L3 (2026-09-08): 还原 per-vendor API Keys(仅当前 vendor)
    this.vendorApiKeys = {}
    const curKey: string | null = await llm.getApiKey(this.vendorId)
    if (curKey !== null) {
      this.vendorApiKeys[this.vendorId] = curKey
    }

    this.syncEndpoint(llm.getEndpoint())
    this.syncModel(llm.getModel())
    this.temp = llm.getTemperature()
    this.maxT = llm.getMaxTokens()
    this.to = llm.getTimeoutMs()

    const ocr: OcrConfig = OcrConfig.getInstance()
    try {
      this.ocrEndpoint = ocr.getEndpoint()
      this.ocrEnabled = ocr.isEnabled()
      this.ocrMode = ocr.getMode()
      this.ocrStatusText = this.ocrEnabled ? "未测试" : "OCR 已关闭"
    } catch (_e) {
      ok = false
      this.ocrEndpoint = DEFAULT_OCR_ENDPOINT
      this.ocrEnabled = true
      this.ocrMode = DEFAULT_OCR_MODE
      this.ocrStatusText = "未测试"
    }
    return ok
  }

  async save(): Promise<boolean> {
    try {
      const llm: LlmConfig = LlmConfig.getInstance()
      // PR2-T2: 持久化 vendorId — 不持久化则切换 vendor 后刷新页面就丢失
      await llm.setVendorId(this.vendorId)
      // PR2-T2 ticket #83 L1 (2026-09-08): 持久化 customVendors 数组
      await llm.setCustomVendors(this.customVendors.map(
        (v: CustomVendorFull): CustomVendorConfig => ({
          vendorName: v.vendorName, baseUrl: v.baseUrl, model: v.model,
        })
      ))
      // PR2-T2 ticket #83 L2 (2026-09-08): 持久化 per-vendor models
      for (const vid of Object.keys(this.vendorModels)) {
        const existing: string[] | undefined = llm.getVendorModels(vid)
        // 仅写非空 vendor,避免覆盖 LlmConfig 默认 seed
        const ours: string[] = this.vendorModels[vid]
        if (ours.length > 0) {
          // 简化:重写整个 vendor 的 model list(对预设 vendor 也可,因为我们 seed 用 default)
          for (const m of ours) {
            await llm.addVendorModel(vid, m)
          }
          // 移除 LlmConfig 默认 seed 但不在 UI state 中的
          for (const m of existing) {
            if (ours.indexOf(m) < 0) { await llm.removeVendorModel(vid, m) }
          }
        }
      }
      // PR2-T2 ticket #83 L3 (2026-09-08): 持久化 per-vendor API Key
      for (const vid of Object.keys(this.vendorApiKeys)) {
        const k: string = this.vendorApiKeys[vid]
        if (k.length > 0) {
          await llm.setApiKey(k, vid)
        }
      }
      // PR2-T2 集成修复 (2026-09-08): 用 getCurrent* 而非 resolve* — 新方法是 vendorId-driven,旧方法是 keyword-sniff
      // (旧 resolveEndpoint/resolveModel 在 ticket #83 L4 清理 PR 删除)
      await llm.saveAll(this.getCurrentEndpoint(), this.getCurrentModel(), this.temp, this.maxT, this.to)
      // 全局 API key (back-compat path)— 仅当 user 显式填过;UI 已删全局 input,这里保留 catch-all
      const key: string = this.apiKey.trim()
      if (key.length > 0) {
        await llm.setApiKey(key)  // 无 vendorId → 全局(PR1 AssetStoreKit)
      }
      const ocr: OcrConfig = OcrConfig.getInstance()
      await ocr.setEndpoint(this.ocrEndpoint)
      await ocr.setEnabled(this.ocrEnabled)
      await ocr.setMode(this.ocrMode)
      this.ocrEndpoint = ocr.getEndpoint()
      this.ocrMode = ocr.getMode()
      this.statusText = "已保存"
      return true
    } catch (_e) {
      return false
    }
  }

  async reset(): Promise<boolean> {
    try {
      const llm: LlmConfig = LlmConfig.getInstance()
      await llm.resetDefaults()
      await llm.clearApiKey()
      this.apiKey = ""
      this.useCustomEP = false
      this.customEP = ""
      this.mdlIdx = 0
      this.useCustomMD = false
      this.customMD = ""
      this.configured = false
      this.statusText = "未配置"
      this.temp = 0.1
      this.maxT = 12000
      this.to = 120000

      const ocr: OcrConfig = OcrConfig.getInstance()
      await ocr.resetDefaults()
      this.ocrEndpoint = ocr.getEndpoint()
      this.ocrEnabled = ocr.isEnabled()
      this.ocrMode = ocr.getMode()
      this.ocrStatusText = "未测试"
      return true
    } catch (_e) {
      return false
    }
  }

  async test(): Promise<boolean> {
    const key: string = this.apiKey.trim()
    if (key.length === 0) {
      return false
    }
    this.testing = true
    try {
      const llm: LlmConfig = LlmConfig.getInstance()
      await llm.setApiKey(key)
      await llm.saveAll(this.resolveEndpoint(), this.resolveModel(), this.temp, this.maxT, this.to)
      await new LlmClient().call({
        messages: [
          { role: "system", content: "You are a connection test endpoint. Reply with exactly: OK" },
          { role: "user", content: "Reply OK only." },
        ],
        maxTokens: 512,
        timeoutMs: 60000,
      })
      this.statusText = "已配置 / 连接正常"
      this.configured = true
      return true
    } catch (e) {
      const errMsg: string = (e as Error).message ?? String(e)
      this.statusText = "连接失败: " + errMsg.substring(0, 80)
      return false
    } finally {
      this.testing = false
    }
  }

  async testOcr(): Promise<boolean> {
    if (!this.ocrEnabled) {
      this.ocrStatusText = "OCR 已关闭"
      return false
    }
    this.ocrTesting = true
    try {
      const tool: OcrTool = new OcrTool()
      const endpoint: string = OcrConfig.normalizeEndpointInput(this.ocrEndpoint)
      this.ocrEndpoint = endpoint
      const imageBytes: ArrayBuffer = new Uint8Array(OCR_TEST_PNG_BYTES).buffer as ArrayBuffer
      const result: OcrRecognitionResult = await tool.recognizeBytesWithEndpoint(
        imageBytes,
        endpoint,
        "ocr_test.png",
        this.ocrMode,
      )
      this.ocrStatusText = result.success
        ? "OCR 可达 / 公式 " + result.formulas.length.toString() + " / 文本 " + result.textLines.length.toString()
        : "OCR 失败 / " + (result.message.length > 0 ? result.message : "无返回")
      return result.success
    } catch (_e) {
      this.ocrStatusText = "OCR 测试失败"
      return false
    } finally {
      this.ocrTesting = false
    }
  }

  setApiKey(value: string): void {
    this.apiKey = value
  }

  setCustomEndpoint(value: string): void {
    this.customEP = value
    this.useCustomEP = value.trim().length > 0
  }

  toggleCustomEndpoint(value: boolean): void {
    this.useCustomEP = value
    if (!value) {
      this.customEP = ""
    }
  }

  selectModel(index: number): void {
    this.mdlIdx = index
    this.useCustomMD = false
    this.customMD = ""
  }

  setCustomModel(value: string): void {
    this.customMD = value
    this.useCustomMD = value.trim().length > 0
  }

  toggleCustomModel(value: boolean): void {
    this.useCustomMD = value
    if (!value) {
      this.customMD = ""
    }
  }

  setOcrEndpoint(value: string): void {
    this.ocrEndpoint = value
  }

  setOcrEnabled(value: boolean): void {
    this.ocrEnabled = value
  }

  setOcrMode(value: string): void {
    this.ocrMode = OcrConfig.normalizeModeInput(value)
  }

  resetOcrEndpoint(): void {
    this.ocrEndpoint = DEFAULT_OCR_ENDPOINT
    this.ocrMode = DEFAULT_OCR_MODE
  }

  currentModelText(): string {
    if (this.useCustomMD && this.customMD.trim().length > 0) {
      return this.customMD.trim()
    }
    return PRO_MODEL
  }

  modelLabel(): string {
    const model: string = this.currentModelText()
    if (model === PRO_MODEL) {
      return "DeepSeek-V4-Pro"
    }
    return model
  }

  endpointLabel(): string {
    const endpoint: string = this.resolveEndpoint()
    return endpoint === DS_ENDPOINT ? "DeepSeek 官方" : endpoint
  }

  private syncEndpoint(endpoint: string): void {
    const current: string = endpoint.trim()
    const lower: string = current.toLowerCase()
    if (
      current.length === 0 ||
      current === DS_ENDPOINT ||
      lower.indexOf('siliconflow') >= 0 ||
      (lower.indexOf('api.deepseek.com') >= 0 && lower.indexOf('chat/completions') < 0)
    ) {
      this.useCustomEP = false
      this.customEP = ""
      return
    }
    this.useCustomEP = true
    this.customEP = current
  }

  private syncModel(model: string): void {
    const current: string = model.trim()
    const lower: string = current.toLowerCase()
    if (
      current.length === 0 ||
      current === PRO_MODEL ||
      lower.indexOf('v3') >= 0 ||
      lower.indexOf('flash') >= 0 ||
      lower.indexOf('deepseek-chat') >= 0 ||
      lower.indexOf('deepseek-reasoner') >= 0 ||
      lower.indexOf('r1') >= 0
    ) {
      this.mdlIdx = 0
      this.useCustomMD = false
      this.customMD = ""
      return
    }
    this.mdlIdx = 0
    this.useCustomMD = true
    this.customMD = current
  }

  private resolveEndpoint(): string {
    return this.useCustomEP && this.customEP.length > 0 ? this.customEP : DS_ENDPOINT
  }

  private resolveModel(): string {
    if (this.useCustomMD && this.customMD.length > 0) {
      return this.customMD
    }
    return PRO_MODEL
  }

  // ===== PR2-T2 增量: VendorPicker 接口 =====
  // 选中的 vendor id('deepseek' / 'tongyi' / 'glm' / 'kimi' / 'doubao' / 'custom')
  vendorId: string = 'deepseek'
  // 注: panel 展开是 VendorPicker 内部 UI 状态(@State editingVendorId),
  //     不放在 ViewModel(避免双真理源同步问题)。

  // PR2-T2 ticket #83 L1 (2026-09-08): 用户添加的自定义 vendor 列表
  // in-memory mirror;save() 持久化到 LlmConfig
  customVendors: CustomVendorFull[] = []

  // PR2-T2 ticket #83 L2 (2026-09-08): per-vendor models Record
  // in-memory mirror;save() 持久化到 LlmConfig
  vendorModels: Record<string, string[]> = {}

  // PR2-T2 ticket #83 L3 (2026-09-08): per-vendor API Key Record
  // in-memory mirror;save() 持久化到 LlmConfig
  vendorApiKeys: Record<string, string> = {}

  selectVendor(id: string): void {
    this.vendorId = id
  }

  openAddCustomVendor(): void {
    // 占位 — 真正的 modal 打开在 VendorPicker 内(@State addCustomModalOpen)
    // 保留本方法作为扩展点
  }

  // PR2-T2 P3: 添加新 vendor(由 VendorPicker modal 确认后回调)
  // 同步切到新 vendor,后续 chat 用它的 baseUrl/model/apiKey
  // PR2-T2 polish ticket #81 task A4: 返回新 vendorId 用于 NEW badge 跟踪
  addCustomVendor(name: string, baseUrl: string, apiKey: string, firstModel: string): string {
    const id: string = 'custom-' + Date.now()
    this.customVendors.push({ id, vendorName: name, baseUrl, model: firstModel, apiKey })
    this.vendorId = id
    return id
  }

  // PR2-T2 ticket #83 L2 (2026-09-08): per-vendor models UI 动作
  // UI 加 model / 删 model,后续 save() 持久化
  addVendorModel(vendorId: string, model: string): void {
    const t: string = model.trim()
    if (t.length === 0) { return }
    if (this.vendorModels[vendorId] === undefined) {
      this.vendorModels[vendorId] = []
    }
    if (this.vendorModels[vendorId].indexOf(t) >= 0) { return }  // 防重
    this.vendorModels[vendorId].push(t)
  }

  removeVendorModel(vendorId: string, model: string): void {
    const existing: string[] | undefined = this.vendorModels[vendorId]
    if (existing === undefined) { return }
    this.vendorModels[vendorId] = existing.filter((m: string): boolean => m !== model)
  }

  // PR2-T2 ticket #83 L3 (2026-09-08): per-vendor API Key UI 动作
  setVendorApiKey(vendorId: string, key: string): void {
    this.vendorApiKeys[vendorId] = key
  }

  clearVendorApiKey(vendorId: string): void {
    delete this.vendorApiKeys[vendorId]
  }

  // PR2-T2 P4: AI 服务段摘要解析(替代旧 modelSummary/endpointSummary 关键字嗅探)
  // 单一真理源: 用 vendorId + findProvider(customVendor.baseUrl) 解析
  getCurrentVendor(): string {
    // 预设 vendor
    for (const p of PROVIDERS) {
      if (p.id === this.vendorId) { return p.vendorName }
    }
    // 自定义 vendor(从 customVendors 数组找)
    for (const v of this.customVendors) {
      if (v.id === this.vendorId) { return v.vendorName }
    }
    return this.vendorId
  }

  getCurrentModel(): string {
    for (const p of PROVIDERS) {
      if (p.id === this.vendorId) { return p.defaultModel }
    }
    for (const v of this.customVendors) {
      if (v.id === this.vendorId) { return v.model }
    }
    return ''
  }

  getCurrentEndpoint(): string {
    for (const p of PROVIDERS) {
      if (p.id === this.vendorId) { return p.baseUrl }
    }
    for (const v of this.customVendors) {
      if (v.id === this.vendorId) { return v.baseUrl }
    }
    return ''
  }
}
