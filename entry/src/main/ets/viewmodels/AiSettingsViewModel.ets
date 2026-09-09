/**
 * @file AiSettingsViewModel.ets — AI 设置页视图模型
 *
 * 职责：管理 API Key、端点、模型、OCR 配置的读写与连接测试。
 * 依赖：LlmConfig、OcrConfig、LlmClient、OcrTool
 */
import { LlmClient, LlmConfig, OcrConfig } from "common"
import type { CustomVendorConfig, ProviderConfig } from "common"
import { PROVIDERS } from "common"
import { OcrTool } from "agents"
import type { OcrRecognitionResult } from "agents"

// PR2-T2 P3: 用户添加的自定义 vendor 列表
// PR2-T2 ticket #83 L1 (2026-09-08): 不用 extends CustomVendorConfig,直接声明全部字段
//   (避免 ArkTS strict 在 inline literal 位置无法解析 extends 类型)
function toCustomVendorConfig(v: CustomVendorConfig, i: number): CustomVendorConfig {
  const stableId: string = v.id !== undefined && v.id.length > 0
    ? v.id
    : `custom-fallback-${i}`
  return {
    id: stableId,
    vendorName: v.vendorName,
    baseUrl: v.baseUrl,
    model: v.model,
  }
}

function makeCustomVendorEntry(
  id: string, name: string, baseUrl: string, model: string
): CustomVendorConfig {
  return { id, vendorName: name, baseUrl, model }
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
  // PR2-T2 ticket #83 L4 (2026-09-08): 删 useCustomEP / customEP / mdlIdx / useCustomMD / customMD 字段
  //   (旧 keyword-sniff 路径,已被 L1+L2+L3 LlmConfig 取代)
  // PR2-T2 ticket #83 L4: 删 temp / maxT / to 字段
  //   (温度 / max_tokens / timeout — 走 LlmConfig 内部 cache)
  configured: boolean = false
  testing: boolean = false
  statusText: string = "未配置"
  ocrEndpoint: string = DEFAULT_OCR_ENDPOINT
  ocrEnabled: boolean = true
  ocrMode: string = DEFAULT_OCR_MODE
  ocrTesting: boolean = false
  ocrStatusText: string = "未测试"

  async load(): Promise<boolean> {
    let ok: boolean = true
    const llm: LlmConfig = LlmConfig.getInstance()
    // PR2-T2 修复 C1 critical: load() 还原 vendorId — 不还原则刷新页面 vendor 选择回到默认值 'deepseek'
    this.vendorId = llm.getVendorId()

    // PR2-T2 ticket #83 L1 (2026-09-08): 还原 customVendors 数组
    const cvList: CustomVendorConfig[] = llm.getCustomVendors()
    this.customVendors = cvList.map(toCustomVendorConfig)

    // PR2-T2 ticket #83 T4 (2026-09-08): legacy data migration
    // T6 follow-up (2026-09-08): 仅 single legacy vendor(cvList.length === 1)时 assign cachedVendorId
    // 多 vendor 时 fallback id 已 unique,不需要 migration 避免 id 冲突
    if (LlmConfig.isCustomVendor(this.vendorId) && cvList.length === 1) {
      for (const v of this.customVendors) {
        if (v.id === undefined || v.id.length === 0) {
          v.id = this.vendorId
        }
      }
    }

    // PR2-T2 ticket #83 L2 (2026-09-08): 还原 per-vendor models
    this.vendorModels = {}
    for (const p of PROVIDERS) {
      const models: string[] = llm.getVendorModels(p.id)
      this.vendorModels[p.id] = models
    }

    // PR2-T2 ticket #83 L3 (2026-09-08): 还原 per-vendor API Keys
    // Bug fix (2026-09-08): 还原所有 vendor keys(原代码只还原 current)
    this.vendorApiKeys = llm.getAllVendorApiKeys()
    this.activeVendorModels = llm.getAllActiveVendorModels()

    try {
      const key: string | null = await llm.getApiKey(this.vendorId)
      this.configured = key !== null && key.trim().length > 0
      this.statusText = this.configured ? "已配置" : "未配置"
    } catch (_e) {
      ok = false
      this.configured = false
      this.statusText = "未配置"
    }

    // PR2-T2 ticket #83 L4 (2026-09-08): 不再调 syncEndpoint / syncModel(keyword-sniff 已删)
    // PR2-T2 ticket #83 L4: temp / maxT / to 走 LlmConfig cache,不在 VM

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

  async saveLlm(): Promise<boolean> {
    try {
      const llm: LlmConfig = LlmConfig.getInstance()
      // PR2-T2: 持久化 vendorId — 不持久化则切换 vendor 后刷新页面就丢失
      await llm.setVendorId(this.vendorId)
      // PR2-T2 ticket #83 L1 (2026-09-08): 持久化 customVendors 数组
      // Bug fix (2026-09-08): 含 id 字段(保证跨重启 identity 稳定)
      // Bug fix (2026-09-08): 也持久化 apiKey(走 per-vendor L3 通道,不在 CustomVendorConfig 里)
      await llm.setCustomVendors(this.customVendors)
      // PR2-T2 ticket #83 L2 (2026-09-08): 持久化 per-vendor models
      for (const vid of Object.keys(this.vendorModels)) {
        const existing: string[] | undefined = llm.getVendorModels(vid)
        const ours: string[] = this.vendorModels[vid]
        for (const m of ours) {
          await llm.addVendorModel(vid, m)
        }
        if (existing !== undefined) {
          for (const m of existing) {
            if (ours.indexOf(m) < 0) { await llm.removeVendorModel(vid, m) }
          }
        }
      }
      for (const vid of Object.keys(this.activeVendorModels)) {
        const model: string = this.activeVendorModels[vid]
        if (model.length > 0) { await llm.setActiveVendorModel(vid, model) }
      }
      // PR2-T2 ticket #83 L3 (2026-09-08): 持久化 per-vendor API Key
      for (const vid of Object.keys(this.vendorApiKeys)) {
        const k: string = this.vendorApiKeys[vid].trim()
        if (k.length > 0) {
          await llm.setApiKey(k, vid)
        } else {
          await llm.clearApiKey(vid)
        }
      }
      // PR2-T2 集成修复 (2026-09-08): 用 getCurrent* 而非 resolve* — 新方法是 vendorId-driven,旧方法是 keyword-sniff
      // (旧 resolveEndpoint/resolveModel 在 ticket #83 L4 清理 PR 删除)
      // PR2-T2 ticket #83 L4 (2026-09-08): temp / maxT / to 走 LlmConfig cache
      await llm.saveAll(
        this.getCurrentEndpoint(),
        this.getCurrentModel(),
        llm.getTemperature(),
        llm.getMaxTokens(),
        llm.getTimeoutMs()
      )
      this.statusText = "已保存"
      return true
    } catch (_e) {
      return false
    }
  }

  async saveOcr(): Promise<boolean> {
    try {
      const ocr: OcrConfig = OcrConfig.getInstance()
      await ocr.setEndpoint(this.ocrEndpoint)
      await ocr.setEnabled(this.ocrEnabled)
      await ocr.setMode(this.ocrMode)
      this.ocrEndpoint = ocr.getEndpoint()
      this.ocrMode = ocr.getMode()
      return true
    } catch (_e) {
      return false
    }
  }

  async save(): Promise<boolean> {
    const llmOk: boolean = await this.saveLlm()
    const ocrOk: boolean = await this.saveOcr()
    return llmOk && ocrOk
  }

  async reset(): Promise<boolean> {
    try {
      const llm: LlmConfig = LlmConfig.getInstance()
      await llm.resetDefaults()
      await llm.clearApiKey()
      // PR2-T2 ticket #83 L4 (2026-09-08): 不再 reset useCustomEP/customEP/mdlIdx/useCustomMD/customMD/temp/maxT/to(已删字段)
      this.configured = false
      this.statusText = "未配置"

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

  async resetOcr(): Promise<boolean> {
    try {
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
    const llm: LlmConfig = LlmConfig.getInstance()
    const saved: boolean = await this.saveLlm()
    if (!saved) {
      this.statusText = "模型设置保存失败"
      return false
    }
    const key: string | null = await llm.getApiKey(this.vendorId)
    if (key === null || key.trim().length === 0) {
      this.statusText = "请先在当前供应商配置 API Key"
      return false
    }
    this.testing = true
    try {
      await llm.setVendorId(this.vendorId)
      // PR2-T2 ticket #83 L4 (2026-09-08): 用 getCurrent* + LlmConfig cache,不再调 resolve*/temp/maxT/to
      await llm.saveAll(
        this.getCurrentEndpoint(),
        this.getCurrentModel(),
        llm.getTemperature(),
        llm.getMaxTokens(),
        llm.getTimeoutMs()
      )
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

  // PR2-T2 ticket #83 L4 (2026-09-08): 删 setCustomEndpoint / toggleCustomEndpoint /
  //   selectModel / setCustomModel / toggleCustomModel / setTemp / setMaxTokens / setTimeout
  //   (旧 keyword-sniff 路径 + LLM 参数 setter — 全部走 LlmConfig / 自身 setters)

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

  // PR2-T2 ticket #83 L4 (2026-09-08): 删 currentModelText / modelLabel / endpointLabel
  //   (旧 keyword-sniff 路径 — 改用 getCurrent* 方法)
  // PR2-T2 ticket #83 L4: 删 syncEndpoint / syncModel keyword-sniff
  // PR2-T2 ticket #83 L4: 删 resolveEndpoint / resolveModel(由 getCurrent* 取代)

  // ===== PR2-T2 增量: VendorPicker 接口 =====
  // 选中的 vendor id('deepseek' / 'tongyi' / 'glm' / 'kimi' / 'doubao' / 'custom')
  vendorId: string = 'deepseek'
  // 注: panel 展开是 VendorPicker 内部 UI 状态(@State editingVendorId),
  //     不放在 ViewModel(避免双真理源同步问题)。

  // PR2-T2 ticket #83 L1 (2026-09-08): 用户添加的自定义 vendor 列表
  // in-memory mirror;save() 持久化到 LlmConfig
  customVendors: CustomVendorConfig[] = []

  // PR2-T2 ticket #83 L2 (2026-09-08): per-vendor models Record
  // in-memory mirror;save() 持久化到 LlmConfig
  vendorModels: Record<string, string[]> = {}

  // PR2-T2 ticket #83 L3 (2026-09-08): per-vendor API Key Record
  // in-memory mirror;save() 持久化到 LlmConfig
  vendorApiKeys: Record<string, string> = {}
  activeVendorModels: Record<string, string> = {}

  selectVendor(id: string): void {
    this.vendorId = id
  }

  selectVendorModel(vendorId: string, model: string): void {
    const next: Record<string, string> = {}
    for (const k of Object.keys(this.activeVendorModels)) {
      next[k] = this.activeVendorModels[k]
    }
    next[vendorId] = model
    this.activeVendorModels = next
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
    const cv: CustomVendorConfig = makeCustomVendorEntry(id, name, baseUrl, firstModel)
    this.customVendors = [...this.customVendors, cv]
    this.setVendorApiKey(id, apiKey)
    const nextModels: Record<string, string[]> = {}
    for (const k of Object.keys(this.vendorModels)) {
      nextModels[k] = this.vendorModels[k]
    }
    nextModels[id] = [firstModel]
    this.vendorModels = nextModels
    this.selectVendorModel(id, firstModel)
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
    const existing: string[] = this.vendorModels[vendorId]
    const nextModels: string[] = [...existing, t]
    const next: Record<string, string[]> = {}
    for (const k of Object.keys(this.vendorModels)) {
      next[k] = this.vendorModels[k]
    }
    next[vendorId] = nextModels
    this.vendorModels = next
    if (this.activeVendorModels[vendorId] === undefined || this.activeVendorModels[vendorId].length === 0) {
      this.selectVendorModel(vendorId, t)
    }
  }

  removeVendorModel(vendorId: string, model: string): void {
    const existing: string[] | undefined = this.vendorModels[vendorId]
    if (existing === undefined) { return }
    const filtered: string[] = existing.filter((m: string): boolean => m !== model)
    const next: Record<string, string[]> = {}
    for (const k of Object.keys(this.vendorModels)) {
      next[k] = this.vendorModels[k]
    }
    next[vendorId] = filtered
    this.vendorModels = next
    if (this.activeVendorModels[vendorId] === model) {
      const nextModel: string = filtered.length > 0 ? filtered[0] : this.providerDefaultModel(vendorId)
      this.selectVendorModel(vendorId, nextModel)
    }
  }

  // PR2-T2 ticket #83 L3 (2026-09-08): per-vendor API Key UI 动作
  setVendorApiKey(vendorId: string, key: string): void {
    const next: Record<string, string> = {}
    for (const k of Object.keys(this.vendorApiKeys)) {
      next[k] = this.vendorApiKeys[k]
    }
    next[vendorId] = key
    this.vendorApiKeys = next
  }

  clearVendorApiKey(vendorId: string): void {
    // PR2-T2 ticket #83 L3 (2026-09-08): ArkTS 严格模式禁 delete operator
    // 用 rebuild Record 替代(保留其他 vendor keys)
    const next: Record<string, string> = {}
    for (const k of Object.keys(this.vendorApiKeys)) {
      if (k !== vendorId) { next[k] = this.vendorApiKeys[k] }
    }
    this.vendorApiKeys = next
  }

  // PR2-T2 P4: AI 服务段摘要解析(替代旧 modelSummary/endpointSummary 关键字嗅探)
  // 单一真理源: 用 vendorId + findProvider(customVendor.baseUrl) 解析
  getCurrentVendor(): string {
    // 预设 vendor
    for (const p of PROVIDERS) {
      if (p.id === this.vendorId) {
        return p.vendorName
      }
    }
    // 自定义 vendor(从 customVendors 数组找)
    for (const v of this.customVendors) {
      if (v.id === this.vendorId) { return v.vendorName }
    }
    return this.vendorId
  }

  getCurrentModel(): string {
    const activeModel: string | undefined = this.activeVendorModels[this.vendorId]
    if (activeModel !== undefined && activeModel.trim().length > 0) { return activeModel }
    const models: string[] | undefined = this.vendorModels[this.vendorId]
    if (models !== undefined && models.length > 0) { return models[0] }
    for (const p of PROVIDERS) {
      if (p.id === this.vendorId) {
        return p.defaultModel
      }
    }
    for (const v of this.customVendors) {
      if (v.id === this.vendorId) { return v.model }
    }
    return ''
  }

  private providerDefaultModel(vendorId: string): string {
    for (const p of PROVIDERS) {
      if (p.id === vendorId) { return p.defaultModel }
    }
    for (const v of this.customVendors) {
      if (v.id === vendorId) { return v.model }
    }
    return ''
  }

  getCurrentEndpoint(): string {
    for (const p of PROVIDERS) {
      if (p.id === this.vendorId) {
        return p.baseUrl
      }
    }
    for (const v of this.customVendors) {
      if (v.id === this.vendorId) { return v.baseUrl }
    }
    return ''
  }
}
