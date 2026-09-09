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
// PR2-T2 ticket #83 L1 (2026-09-08): per-vendor customVendors 持久化
// 与单数 legacy cachedCustomVendor 并存(向后兼容);新代码优先用数组
const KEY_CUSTOM_VENDORS = 'custom_vendors';
// PR2-T2 ticket #83 L2 (2026-09-08): per-vendor models 持久化
// Record<vendorId, string[]> — 用户在编辑 panel 加的 model,持久到 preferences
const KEY_VENDOR_MODELS = 'vendor_models';
// PR2-T2 ticket #83 L3 (2026-09-08): per-vendor API Key 持久化
// Record<vendorId, string> — 用户在 vendor 编辑 panel 填的 key
const KEY_VENDOR_API_KEYS = 'vendor_api_keys';

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
  // PR2-T2 L1 (2026-09-08): per-vendor customVendors 数组(替代单数 cachedCustomVendor 的扩展用法)
  private cachedCustomVendors: CustomVendorConfig[] = [];
  // PR2-T2 L2 (2026-09-08): per-vendor models Record — 用户编辑 panel 加的 model
  private cachedVendorModels: Record<string, string[]> = {};
  // PR2-T2 L3 (2026-09-08): per-vendor API Key Record — vendor 编辑 panel 填的 key
  private cachedVendorApiKeys: Record<string, string> = {};

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
    // PR2-T2 L1: customVendors JSON 数组(新)
    const cvListJson: string = await s.get(KEY_CUSTOM_VENDORS, '') as string;
    if (cvListJson.length > 0) {
      try {
        const parsed = JSON.parse(cvListJson) as CustomVendorConfig[];
        this.cachedCustomVendors = Array.isArray(parsed) ? parsed : [];
      } catch (_e) {
        this.cachedCustomVendors = [];
      }
    }
    // PR2-T2 L2: vendorModels JSON Record
    const vmJson: string = await s.get(KEY_VENDOR_MODELS, '') as string;
    if (vmJson.length > 0) {
      try {
        const parsed = JSON.parse(vmJson) as Record<string, string[]>;
        this.cachedVendorModels = parsed ?? {};
      } catch (_e) {
        this.cachedVendorModels = {};
      }
    }
    // PR2-T2 L3: vendorApiKeys JSON Record
    const vakJson: string = await s.get(KEY_VENDOR_API_KEYS, '') as string;
    if (vakJson.length > 0) {
      try {
        const parsed = JSON.parse(vakJson) as Record<string, string>;
        this.cachedVendorApiKeys = parsed ?? {};
      } catch (_e) {
        this.cachedVendorApiKeys = {};
      }
    }
  }

  // ===== API Key (PR1: 委托 ApiKeyVault, 不再用明文 preferences) =====
  // PR2-T2 L3 (2026-09-08): per-vendor API Key — vendorId 给定则查 per-vendor map,否则 fallback 全局
  public async getApiKey(vendorId?: string): Promise<string | null> {
    if (vendorId !== undefined && vendorId.length > 0) {
      const per: string | undefined = this.cachedVendorApiKeys[vendorId];
      if (per !== undefined && per.length > 0) { return per; }
    }
    // fallback 全局(AssetStoreKit via ApiKeyVault)
    return ApiKeyVault.get();
  }

  // setApiKey(key) 无 vendorId → 全局(back-compat,PR1 AssetStoreKit)
  // setApiKey(key, vendorId) → per-vendor map
  public async setApiKey(key: string, vendorId?: string): Promise<void> {
    const t: string = key.trim();
    if (t.length === 0) { throw new LlmError('API key empty', 'NOT_INITIALIZED'); }
    if (vendorId !== undefined && vendorId.length > 0) {
      this.cachedVendorApiKeys[vendorId] = t;
      const s = this.store!;
      await s.put(KEY_VENDOR_API_KEYS, JSON.stringify(this.cachedVendorApiKeys));
      await s.flush();
      return;
    }
    await ApiKeyVault.put(t);
  }

  public async isConfigured(): Promise<boolean> {
    const k = await this.getApiKey(this.cachedVendorId);
    return k !== null && k.length > 0;
  }

  // PR2-T2 ticket #83 L3 (2026-09-08): 读所有 per-vendor api keys(VM.load() 用)
  public getAllVendorApiKeys(): Record<string, string> {
    return this.cachedVendorApiKeys
  }

  // clearApiKey() 无 vendorId → 清全局(back-compat)
  // clearApiKey(vendorId) → 删 per-vendor entry(PR2-T2 bug fix 2026-09-08: rebuild Record 替代 delete,arkts-no-delete)
  public async clearApiKey(vendorId?: string): Promise<void> {
    if (vendorId !== undefined && vendorId.length > 0) {
      this.cachedVendorApiKeys = this.rebuildRecordWithout<string>(this.cachedVendorApiKeys, vendorId)
      const s = this.store!;
      await s.put(KEY_VENDOR_API_KEYS, JSON.stringify(this.cachedVendorApiKeys));
      await s.flush();
      return;
    }
    await ApiKeyVault.clear();
  }

  // ===== Endpoint (PR2-T1: 按 vendorId 解析) =====
  // PR2-T2 ticket #83 bug fix (2026-09-08): 实际 vendorId 是 'custom-{timestamp}',不是字面 'custom'
  public getEndpoint(): string {
    // PR2-T2 ticket #83 T2 (2026-09-08): isCustomVendor helper 替代 startsWith magic number
    if (this.isCustomVendor(this.cachedVendorId)) {
      // 优先查 customVendors[] 匹配 id(Bug #1 修复:不再只返回 [0])
      const cv: CustomVendorConfig | null = this.findCustomVendor(this.cachedVendorId)
      if (cv !== null) { return cv.baseUrl; }
      // legacy 单数字段向后兼容
      if (this.cachedCustomVendor !== null) { return this.cachedCustomVendor.baseUrl; }
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
  // PR2-T2 ticket #83 bug fix (2026-09-08): 实际 vendorId 是 'custom-{timestamp}',不是字面 'custom'
  public getModel(): string {
    if (this.isCustomVendor(this.cachedVendorId)) {
      // PR2-T2 L1: 优先查 customVendors[] 匹配 id
      const cv: CustomVendorConfig | null = this.findCustomVendor(this.cachedVendorId)
      if (cv !== null) { return cv.model; }
      // legacy 单数向后兼容
      if (this.cachedCustomVendor !== null) { return this.cachedCustomVendor.model; }
    }
    // PR2-T2 L2: 优先查 vendorModels[vendorId][0](用户加的 model)
    const userModels: string[] | undefined = this.cachedVendorModels[this.cachedVendorId];
    if (userModels !== undefined && userModels.length > 0) {
      return userModels[0];
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

  // ===== PR2-T2 L1 (2026-09-08): per-vendor customVendors 数组 =====
  public getCustomVendors(): CustomVendorConfig[] {
    return this.cachedCustomVendors;
  }

  // PR2-T2 ticket #83 bug fix (2026-09-08): 内部 helper — 按 id 找
  // CustomVendorConfig.id 字段(2026-09-08 引入)保证多 custom vendor 共存时 identity 稳定
  private findCustomVendor(id: string): CustomVendorConfig | null {
    for (const v of this.cachedCustomVendors) {
      if (v.id === id) { return v }
    }
    return null
  }

  // PR2-T2 ticket #83 T2 (2026-09-08): helpers 消除重复 + 消 magic number
  // isCustomVendor(id): VM.addCustomVendor 生成 'custom-'+Date.now() id,此 helper 封装 prefix 检测
  private isCustomVendor(id: string): boolean {
    return id.startsWith('custom') && id.length > 6
  }

  // rebuildRecordWithout<V>: 替代 inline delete + Object.keys loop(arkts-no-delete 兼容)
  private rebuildRecordWithout<V>(rec: Record<string, V>, key: string): Record<string, V> {
    const next: Record<string, V> = {}
    for (const k of Object.keys(rec)) {
      if (k !== key) { next[k] = rec[k] }
    }
    return next
  }

  public async setCustomVendors(arr: CustomVendorConfig[]): Promise<void> {
    this.requireInited();
    this.cachedCustomVendors = arr;
    const s = this.store!;
    if (arr.length === 0) {
      await s.delete(KEY_CUSTOM_VENDORS);
    } else {
      await s.put(KEY_CUSTOM_VENDORS, JSON.stringify(arr));
    }
    await s.flush();
  }

  public async addCustomVendor(cfg: CustomVendorConfig): Promise<void> {
    await this.setCustomVendors([...this.cachedCustomVendors, cfg]);
  }

  // PR2-T2 ticket #83 bug fix (2026-09-08): 优先按 id 匹配,fallback (vendorName+baseUrl) tuple
  public async removeCustomVendor(matcher: CustomVendorConfig): Promise<void> {
    const filtered: CustomVendorConfig[] = this.cachedCustomVendors.filter(
      (v: CustomVendorConfig): boolean => {
        if (matcher.id !== undefined && v.id !== undefined) {
          return v.id !== matcher.id  // 按 id 匹配(优先)
        }
        // fallback:按 (vendorName + baseUrl) tuple
        return !(v.vendorName === matcher.vendorName && v.baseUrl === matcher.baseUrl)
      }
    );
    await this.setCustomVendors(filtered);
  }

  // ===== PR2-T2 L2 (2026-09-08): per-vendor models 数组持久化 =====
  // getVendorModels 返回 vendor 的 model 列表;若空,seed default 1 个
  public getVendorModels(vendorId: string): string[] {
    const models: string[] | undefined = this.cachedVendorModels[vendorId];
    if (models !== undefined && models.length > 0) { return models; }
    // seed:首次访问且 vendor 是预设,返回 1 个 default model
    const p = findProvider(vendorId);
    if (p !== null) { return [p.defaultModel]; }
    return [];
  }

  public async addVendorModel(vendorId: string, model: string): Promise<void> {
    const t: string = model.trim();
    if (t.length === 0) { return; }
    const existing: string[] = this.cachedVendorModels[vendorId] ?? [];
    if (existing.indexOf(t) >= 0) { return; }  // 防重
    this.cachedVendorModels[vendorId] = [...existing, t];
    const s = this.store!;
    await s.put(KEY_VENDOR_MODELS, JSON.stringify(this.cachedVendorModels));
    await s.flush();
  }

  public async removeVendorModel(vendorId: string, model: string): Promise<void> {
    const existing: string[] = this.cachedVendorModels[vendorId] ?? [];
    const filtered: string[] = existing.filter((m: string): boolean => m !== model);
    if (filtered.length === 0) {
      // 空数组 — 删 entry 而非存空数组,简化后续 getVendorModels fallback
      // PR2-T2 ticket #83 T2 (2026-09-08): rebuildRecordWithout helper 替代 inline delete loop
      this.cachedVendorModels = this.rebuildRecordWithout<string[]>(this.cachedVendorModels, vendorId)
    } else {
      this.cachedVendorModels[vendorId] = filtered;
    }
    const s = this.store!;
    await s.put(KEY_VENDOR_MODELS, JSON.stringify(this.cachedVendorModels));
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
    // PR2-T2 L1: 同时清 customVendors[]
    this.cachedCustomVendors = [];
    // PR2-T2 L2: 同时清 vendorModels
    this.cachedVendorModels = {};
    // PR2-T2 L3: 同时清 vendorApiKeys
    this.cachedVendorApiKeys = {};
    const s = this.store!;
    await s.put(KEY_ENDPOINT, DEFAULT_ENDPOINT);
    await s.put(KEY_MODEL, DEFAULT_MODEL);
    await s.put(KEY_TEMPERATURE, DEFAULT_TEMPERATURE);
    await s.put(KEY_MAX_TOKENS, DEFAULT_MAX_TOKENS);
    await s.put(KEY_TIMEOUT_MS, DEFAULT_TIMEOUT_MS);
    await s.put(KEY_ENABLE_THINKING, false);
    await s.put(KEY_VENDOR_ID, 'deepseek');
    await s.delete(KEY_CUSTOM_VENDOR);
    await s.delete(KEY_CUSTOM_VENDORS);
    await s.delete(KEY_VENDOR_MODELS);
    await s.delete(KEY_VENDOR_API_KEYS);
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
