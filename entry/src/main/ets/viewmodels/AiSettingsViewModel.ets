/**
 * @file AiSettingsViewModel.ets — AI 设置页视图模型
 *
 * 职责：管理 API Key、端点、模型、OCR 配置的读写与连接测试。
 * 依赖：LlmConfig、OcrConfig、LlmClient、OcrTool
 */
import { LlmClient, LlmConfig, OcrConfig } from "common"
import { DS_ENDPOINT } from "../pages/AiSettings/EndpointPicker"
import { PRO_MODEL } from "../pages/AiSettings/ModelPicker"
import { OcrTool } from "agents"
import type { OcrRecognitionResult } from "agents"

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
      await llm.saveAll(this.resolveEndpoint(), this.resolveModel(), this.temp, this.maxT, this.to)
      const key: string = this.apiKey.trim()
      if (key.length > 0) {
        await llm.setApiKey(key)
        this.configured = true
      } else {
        await llm.clearApiKey()
        this.configured = false
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
}
