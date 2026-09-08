// MindTrace - LLM 配置管理(单例 + preferences 持久化 + 运行时读写)
// 创建: 2026-07-14
// PR1 2026-09-07: apiKey 凭据升级到 AssetStoreKit(委托 ApiKeyVault)
// PR2-T1 2026-09-07: 加 vendorId / customVendorConfig 字段(getEndpoint/getModel 按 vendorId 解析)

import { preferences } from '@kit.ArkData';
import { ApiKeyVault } from '../security/ApiKeyVault';
import { LlmConfigInitResult, LlmError } from './LlmTypes';
import { DEFAULT_VENDOR_ID, findProvider } from './providers';
import type { CustomVendorConfig } from './providers';

const STORE_NAME = 'llm_config';
const KEY_ENDPOINT = 'endpoint';
const KEY_MODEL = 'model';
const KEY_TEMPERATURE = 'temperature';
const KEY_MAX_TOKENS = 'max_tokens';
const KEY_TIMEOUT_MS = 'timeout_ms';
const KEY_ENABLE_THINKING = 'enable_thinking';
const KEY_VENDOR_ID = 'vendor_id';
const KEY_CUSTOM_VENDOR = 'custom_vendor';

// 默认值 — 用户未配置时使用
const DEFAULT_ENDPOINT = 'https://api.deepseek.com';
const DEFAULT_MODEL = 'deepseek-v4-pro';
const DEFAULT_TEMPERATURE = 0.1;
const DEFAULT_MAX_TOKENS = 12000;
const DEFAULT_TIMEOUT_MS = 120000;

export class LlmConfig {
  private static instance: LlmConfig | null = null;
  private store: preferences.Preferences | null = null;
  private inited: boolean = false;

  // 运行时缓存
  private cachedEndpoint: string = DEFAULT_ENDPOINT;
  private cachedModel: string = DEFAULT_MODEL;
  private cachedTemperature: number = DEFAULT_TEMPERATURE;
  private cachedMaxTokens: number = DEFAULT_MAX_TOKENS;
  private cachedTimeoutMs: number = DEFAULT_TIMEOUT_MS;
  private cachedEnableThinking: boolean = false;
  // PR2-T1: vendor 解析
  private cachedVendorId: string = 'deepseek';
  private cachedCustomVendor: CustomVendorConfig | null = null;

  private constructor() {}

  public static getInstance(): LlmConfig {
    if (LlmConfig.instance === null) {
      LlmConfig.instance = new LlmConfig();
    }
    return LlmConfig.instance;
  }

  // ===== 初始化 =====
  public async init(context: Context): Promise<LlmConfigInitResult> {
    if (this.inited && this.store !== null) {
      return { ok: true, message: 'LlmConfig already initialized' };
    }
    try {
      this.store = await preferences.getPreferences(context, STORE_NAME);
      await this.loadAll();
      this.inited = true;
      return { ok: true, message: 'LlmConfig initialized' };
    } catch (e) {
      return { ok: false, message: 'LlmConfig init failed: ' + JSON.stringify(e) };
    }
  }

  private async loadAll(): Promise<void> {
    const s = this.store!;
    const ep: string = await s.get(KEY_ENDPOINT, '') as string;
    this.cachedEndpoint = this.normalizeEndpoint(ep);
    const md: string = await s.get(KEY_MODEL, '') as string;
    this.cachedModel = this.normalizeModel(md);
    const tp: number = await s.get(KEY_TEMPERATURE, -1) as number;
    if (tp >= 0) { this.cachedTemperature = tp; }
    const mt: number = await s.get(KEY_MAX_TOKENS, -1) as number;
    if (mt >= 0) { this.cachedMaxTokens = mt; }
    const tm: number = await s.get(KEY_TIMEOUT_MS, -1) as number;
    if (tm >= 0) { this.cachedTimeoutMs = tm; }
    const et: boolean = await s.get(KEY_ENABLE_THINKING, false) as boolean;
    this.cachedEnableThinking = et;
    // PR2-T1: vendorId + customVendor(JSON 字符串)
    const vid: string = await s.get(KEY_VENDOR_ID, '') as string;
    this.cachedVendorId = vid.length > 0 ? vid : DEFAULT_VENDOR_ID;
    const cvJson: string = await s.get(KEY_CUSTOM_VENDOR, '') as string;
    if (cvJson.length > 0) {
      try {
        this.cachedCustomVendor = JSON.parse(cvJson) as CustomVendorConfig;
      } catch (_e) {
        this.cachedCustomVendor = null;
      }
    }
  }

  // ===== API Key (PR1: 委托 ApiKeyVault, 不再用明文 preferences) =====
  public async getApiKey(): Promise<string | null> {
    return ApiKeyVault.get();
  }

  public async setApiKey(key: string): Promise<void> {
    const t: string = key.trim();
    if (t.length === 0) { throw new LlmError('API key empty', 'NOT_INITIALIZED'); }
    await ApiKeyVault.put(t);
  }

  public async isConfigured(): Promise<boolean> {
    const k = await this.getApiKey();
    return k !== null && k.length > 0;
  }

  public async clearApiKey(): Promise<void> {
    await ApiKeyVault.clear();
  }

  // ===== Endpoint (PR2-T1: 按 vendorId 解析) =====
  public getEndpoint(): string {
    if (this.cachedVendorId === 'custom' && this.cachedCustomVendor !== null) {
      return this.cachedCustomVendor.baseUrl;
    }
    const p = findProvider(this.cachedVendorId);
    if (p !== null) { return p.baseUrl; }
    return this.cachedEndpoint;
  }

  public async setEndpoint(v: string): Promise<void> {
    this.requireInited();
    this.cachedEndpoint = this.normalizeEndpoint(v);
    await this.store!.put(KEY_ENDPOINT, this.cachedEndpoint);
    await this.store!.flush();
  }

  // ===== Model (PR2-T1: 按 vendorId 解析) =====
  public getModel(): string {
    if (this.cachedVendorId === 'custom' && this.cachedCustomVendor !== null) {
      return this.cachedCustomVendor.model;
    }
    const p = findProvider(this.cachedVendorId);
    if (p !== null) { return p.defaultModel; }
    return this.cachedModel;
  }

  public async setModel(v: string): Promise<void> {
    this.requireInited();
    this.cachedModel = this.normalizeModel(v);
    await this.store!.put(KEY_MODEL, this.cachedModel);
    await this.store!.flush();
  }

  // ===== Temperature =====
  public getTemperature(): number { return this.cachedTemperature; }
  public async setTemperature(v: number): Promise<void> {
    this.requireInited();
    this.cachedTemperature = Math.max(0, Math.min(2, v));
    await this.store!.put(KEY_TEMPERATURE, this.cachedTemperature);
    await this.store!.flush();
  }

  // ===== Max Tokens =====
  public getMaxTokens(): number { return this.cachedMaxTokens; }
  public async setMaxTokens(v: number): Promise<void> {
    this.requireInited();
    this.cachedMaxTokens = Math.max(1, Math.min(16000, v));
    await this.store!.put(KEY_MAX_TOKENS, this.cachedMaxTokens);
    await this.store!.flush();
  }

  // ===== Timeout =====
  public getTimeoutMs(): number { return this.cachedTimeoutMs; }
  public async setTimeoutMs(v: number): Promise<void> {
    this.requireInited();
    this.cachedTimeoutMs = Math.max(1000, Math.min(300000, v));
    await this.store!.put(KEY_TIMEOUT_MS, this.cachedTimeoutMs);
    await this.store!.flush();
  }

  // ===== Enable Thinking =====
  public getEnableThinking(): boolean { return this.cachedEnableThinking; }
  public async setEnableThinking(v: boolean): Promise<void> {
    this.requireInited();
    this.cachedEnableThinking = v;
    await this.store!.put(KEY_ENABLE_THINKING, v);
    await this.store!.flush();
  }

  // ===== PR2-T1: Vendor 解析 =====
  public getVendorId(): string { return this.cachedVendorId; }

  public async setVendorId(id: string): Promise<void> {
    this.requireInited();
    this.cachedVendorId = id;
    await this.store!.put(KEY_VENDOR_ID, id);
    await this.store!.flush();
  }

  public getCustomVendorConfig(): CustomVendorConfig | null { return this.cachedCustomVendor; }

  public async setCustomVendorConfig(cfg: CustomVendorConfig | null): Promise<void> {
    this.requireInited();
    this.cachedCustomVendor = cfg;
    const s = this.store!;
    if (cfg === null) {
      await s.delete(KEY_CUSTOM_VENDOR);
    } else {
      await s.put(KEY_CUSTOM_VENDOR, JSON.stringify(cfg));
    }
    await s.flush();
  }

  // ===== 恢复默认 =====
  public async resetDefaults(): Promise<void> {
    this.requireInited();
    this.cachedEndpoint = DEFAULT_ENDPOINT;
    this.cachedModel = DEFAULT_MODEL;
    this.cachedTemperature = DEFAULT_TEMPERATURE;
    this.cachedMaxTokens = DEFAULT_MAX_TOKENS;
    this.cachedTimeoutMs = DEFAULT_TIMEOUT_MS;
    this.cachedEnableThinking = false;
    this.cachedVendorId = 'deepseek';
    this.cachedCustomVendor = null;
    const s = this.store!;
    await s.put(KEY_ENDPOINT, DEFAULT_ENDPOINT);
    await s.put(KEY_MODEL, DEFAULT_MODEL);
    await s.put(KEY_TEMPERATURE, DEFAULT_TEMPERATURE);
    await s.put(KEY_MAX_TOKENS, DEFAULT_MAX_TOKENS);
    await s.put(KEY_TIMEOUT_MS, DEFAULT_TIMEOUT_MS);
    await s.put(KEY_ENABLE_THINKING, false);
    await s.put(KEY_VENDOR_ID, 'deepseek');
    await s.delete(KEY_CUSTOM_VENDOR);
    await s.flush();
  }

  // ===== 一键保存所有 =====
  public async saveAll(
    endpoint: string, model: string, temperature: number,
    maxTokens: number, timeoutMs: number,
  ): Promise<void> {
    this.requireInited();
    this.cachedEndpoint = this.normalizeEndpoint(endpoint);
    this.cachedModel = this.normalizeModel(model);
    this.cachedTemperature = Math.max(0, Math.min(2, temperature));
    this.cachedMaxTokens = Math.max(1, Math.min(16000, maxTokens));
    this.cachedTimeoutMs = Math.max(1000, Math.min(300000, timeoutMs));
    const s = this.store!;
    await s.put(KEY_ENDPOINT, this.cachedEndpoint);
    await s.put(KEY_MODEL, this.cachedModel);
    await s.put(KEY_TEMPERATURE, this.cachedTemperature);
    await s.put(KEY_MAX_TOKENS, this.cachedMaxTokens);
    await s.put(KEY_TIMEOUT_MS, this.cachedTimeoutMs);
    await s.flush();
  }

  private requireInited(): void {
    if (!this.inited || this.store === null) {
      throw new LlmError('LlmConfig not initialized', 'NOT_INITIALIZED');
    }
  }

  private normalizeEndpoint(v: string): string {
    return this.normalizeEndpointForVendor(v, this.cachedVendorId);
  }

  // PR2-T2 集成修复 (2026-09-08): siliconflow 关键字检查仅在 DeepSeek vendor 下生效
  // 原因: siliconflow 是 DeepSeek API 的 fallback 关键字,其他 vendor 不应被此关键字拒绝。
  //       VendorPicker PR2-T2 引入 5 vendor 后,如不 vendor-aware,任何 URL 含 siliconflow 子串
  //       的 endpoint 都会被错误拒绝。
  private normalizeEndpointForVendor(v: string, vendorId: string): string {
    const t: string = v.trim();
    if (t.length === 0) {
      return DEFAULT_ENDPOINT;
    }
    const lower: string = t.toLowerCase();
    if (vendorId === 'deepseek' && lower.indexOf('siliconflow') >= 0) {
      throw new LlmError(
        `LlmConfig.normalizeEndpoint: input "${v}" matches reserved keyword "siliconflow"; ` +
        `siliconflow is not supported for DeepSeek. Use DEFAULT_ENDPOINT or override ` +
        `normalizeEndpoint() if this is intentional.`,
        'NORMALIZE_KEYWORD_REJECTED'
      );
    }
    if (lower.indexOf('api.deepseek.com') >= 0) {
      const idx: number = lower.indexOf('/chat/completions');
      if (idx >= 0) {
        return t.substring(0, idx);
      }
      return t;
    }
    return t;
  }

  private normalizeModel(v: string): string {
    return this.normalizeModelForVendor(v, this.cachedVendorId);
  }

  // PR2-T2 集成修复 (2026-09-08): reserved keywords 检查仅在 DeepSeek vendor 下生效
  // 原因: 5 vendor 引入后,其他 vendor 的合法模型名含 'flash' / 'r1' / 数字版本等子串
  //       (例: qwen-flash, glm-4-flash, kimi-r1, qwen3-max, kimi-k2.6)。
  //       Vendor-agnostic 检查会错误拒绝这些合法名,破坏 LLM 链路。
  // ticket #9 原意 (DeepSeek 模型命名空间) 通过 vendorId === 'deepseek' 限定保留。
  private normalizeModelForVendor(v: string, vendorId: string): string {
    const t: string = v.trim();
    if (t.length === 0) {
      return DEFAULT_MODEL;
    }
    if (vendorId === 'deepseek') {
      const lower: string = t.toLowerCase();
      if (
        lower.indexOf('v3') >= 0 ||
        lower.indexOf('flash') >= 0 ||
        lower.indexOf('deepseek-chat') >= 0 ||
        lower.indexOf('deepseek-reasoner') >= 0 ||
        lower.indexOf('r1') >= 0
      ) {
        throw new LlmError(
          `LlmConfig.normalizeModel: input "${v}" matches a reserved keyword; ` +
          `DEFAULT_MODEL is enforced for DeepSeek. Reserved keywords: v3, flash, deepseek-chat, ` +
          `deepseek-reasoner, r1. ` +
          `(DEFAULT_MODEL itself is allowed — see ticket PR0 fix 2026-09-06.)`,
          'NORMALIZE_KEYWORD_REJECTED'
        );
      }
    }
    return t;
  }
}
