// MindTrace - LLM 配置管理(单例 + preferences 持久化 + 运行时读写)
// 路径: common/src/main/ets/llm/LlmConfig.ets
// 职责: LLM 配置读写 + schema 迁移 + vendor/model 解析(catalog → alias)
// 创建: 2026-07-14
// PR1 2026-09-07: apiKey 凭据升级到 AssetStoreKit(委托 ApiKeyVault)
// PR2-T1 2026-09-07: 加 vendorId / customVendorConfig 字段(getEndpoint/getModel 按 vendorId 解析)
// 2026-10-25: 加 vendor_model_meta 持久化(discovery displayName/contextWindow/模态),
//             与 vendor_models 同步写、同步删; 老数据缺失该 key 时读取侧回落模型 ID。

import { preferences } from '@kit.ArkData';
import { ApiKeyVault } from '../security/ApiKeyVault';
import { LlmConfigInitResult, LlmError } from './LlmTypes';
import { DEFAULT_VENDOR_ID, findProvider } from './providers';
import type { CustomVendorConfig } from './providers';
import { getProviderCatalog } from './model-catalog';
import type { ProviderCatalog } from './model-catalog';
import { resolveModel } from './model-resolver';
import type { ResolvedModel } from './model-resolver';

const STORE_NAME = 'llm_config';
const KEY_SCHEMA_VERSION = 'schema_version';
const KEY_REQUESTED_ALIAS = 'requested_alias';
const SCHEMA_VERSION: number = 2;
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
// 2026-10-25: per-vendor 模型元信息持久化
// Record<vendorId, Record<modelId, VendorModelMeta>> — discovery 返回的 displayName /
// contextWindow / inputModalities / source,与 vendor_models 同步写、同步删。
const KEY_VENDOR_MODEL_META = 'vendor_model_meta';
// PR2-T2 ticket #83 L3 (2026-09-08): per-vendor API Key 持久化
// Record<vendorId, string> — 用户在 vendor 编辑 panel 填的 key
const KEY_VENDOR_API_KEYS = 'vendor_api_keys';
const KEY_ACTIVE_VENDOR_MODELS = 'active_vendor_models';
const KEY_MODEL_CONTEXT_WINDOWS = 'model_context_windows';

// 默认值 — 用户未配置时使用
const DEFAULT_ENDPOINT = 'https://api.deepseek.com';
const DEFAULT_MODEL = 'deepseek-v4-pro';
const DEFAULT_TEMPERATURE = 0.1;
const DEFAULT_MAX_TOKENS = 12000;
const DEFAULT_TIMEOUT_MS = 120000;
export const DEFAULT_ENABLE_THINKING = true;
export const DEFAULT_CONTEXT_WINDOW_TOKENS: number = 65536;

// 2026-10-25: 模型元信息 — 只存 discovery / 用户来源里真实拿到的字段, 不在这里推导能力。
// 持久化结构: { vendorId: { modelId: { displayName, contextWindow, inputModalities, source } } }
// 读取侧缺失时回落: displayName → model ID; contextWindow → model_context_windows → 0。
export interface VendorModelMeta {
  displayName: string;
  contextWindow: number;
  inputModalities: string[];
  source: string;   // 'catalog' | 'discovery' | 'user'
}

export class LlmConfig {
  private static instance: LlmConfig | null = null;
  private store: preferences.Preferences | null = null;
  private inited: boolean = false;

  // 运行时缓存
  private cachedEndpoint: string = DEFAULT_ENDPOINT;
  private cachedModel: string = DEFAULT_MODEL;
  // 2026-10-25: 区分「用户显式写过 model」与「缺省没写过」。
  // 迁移会把 legacy model 归一化成规范 ID, 但 getModel() 不能因此被 catalog 默认盖掉 (计划 §5.3)。
  private cachedModelExplicit: boolean = false;
  private cachedTemperature: number = DEFAULT_TEMPERATURE;
  private cachedMaxTokens: number = DEFAULT_MAX_TOKENS;
  private cachedTimeoutMs: number = DEFAULT_TIMEOUT_MS;
  private cachedEnableThinking: boolean = DEFAULT_ENABLE_THINKING;
  // PR2-T1: vendor 解析
  private cachedVendorId: string = 'deepseek';
  private cachedCustomVendor: CustomVendorConfig | null = null;
  // PR2-T2 L1 (2026-09-08): per-vendor customVendors 数组(替代单数 cachedCustomVendor 的扩展用法)
  private cachedCustomVendors: CustomVendorConfig[] = [];
  // PR2-T2 L2 (2026-09-08): per-vendor models Record — 用户编辑 panel 加的 model
  private cachedVendorModels: Record<string, string[]> = {};
  // 2026-10-25: per-vendor 模型元信息 — 与 cachedVendorModels 同步维护, 不做独立真源
  private cachedVendorModelMeta: Record<string, Record<string, VendorModelMeta>> = {};
  // PR2-T2 L3 (2026-09-08): per-vendor API Key Record — vendor 编辑 panel 填的 key
  private cachedVendorApiKeys: Record<string, string> = {};
  private cachedActiveVendorModels: Record<string, string> = {};
  private cachedModelContextWindows: Record<string, number> = {};
  // 迁移保护: 旧 model_context_windows JSON 解析失败时, 不覆盖 raw key。
  private cachedModelContextWindowsParsed: boolean = true;

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
    // 先读完 raw, 再做 schema 迁移, 最后 normalizeEndpoint/normalizeModel。
    // 迁移必须发生在 normalizeModel 之前 (计划 §5.2), 否则旧别名先被归一化,
    // 无法保留 requested_alias / 无法区分"用户显式选择"与"缺省"。
    const rawEndpoint: string = await s.get(KEY_ENDPOINT, '') as string;
    const rawModel: string = await s.get(KEY_MODEL, '') as string;
    const tp: number = await s.get(KEY_TEMPERATURE, -1) as number;
    if (tp >= 0) { this.cachedTemperature = tp; }
    const mt: number = await s.get(KEY_MAX_TOKENS, -1) as number;
    if (mt >= 0) { this.cachedMaxTokens = mt; }
    const tm: number = await s.get(KEY_TIMEOUT_MS, -1) as number;
    if (tm >= 0) { this.cachedTimeoutMs = tm; }
    const et: boolean = await s.get(KEY_ENABLE_THINKING, DEFAULT_ENABLE_THINKING) as boolean;
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
    // 2026-10-25: vendorModelMeta JSON Record(旧数据没有该 key → 空表, 读取侧回落 ID)
    const vmmJson: string = await s.get(KEY_VENDOR_MODEL_META, '') as string;
    if (vmmJson.length > 0) {
      try {
        const parsed = JSON.parse(vmmJson) as Record<string, Record<string, VendorModelMeta>>;
        this.cachedVendorModelMeta = this.sanitizeVendorModelMeta(parsed);
      } catch (_e) {
        this.cachedVendorModelMeta = {};
        console.error('[LlmConfig] LLM_CONFIG_MIGRATION_FAILED vendor_model_meta JSON parse error; raw key kept');
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
    const activeModelsJson: string = await s.get(KEY_ACTIVE_VENDOR_MODELS, '') as string;
    if (activeModelsJson.length > 0) {
      try {
        const parsed: Record<string, string> = JSON.parse(activeModelsJson);
        this.cachedActiveVendorModels = parsed ?? {};
      } catch (_e) {
        this.cachedActiveVendorModels = {};
      }
    }
    const contextWindowsJson: string = await s.get(KEY_MODEL_CONTEXT_WINDOWS, '') as string;
    if (contextWindowsJson.length > 0) {
      try {
        const parsed: Record<string, number> = JSON.parse(contextWindowsJson);
        this.cachedModelContextWindows = parsed ?? {};
        this.cachedModelContextWindowsParsed = true;
      } catch (_e) {
        this.cachedModelContextWindows = {};
        this.cachedModelContextWindowsParsed = false;
        console.error('[LlmConfig] LLM_CONFIG_MIGRATION_FAILED context_windows JSON parse error; raw key kept');
      }
    }
    const migratedModel: string = await this.migrateIfNeeded(rawModel);
    this.cachedEndpoint = this.normalizeEndpoint(rawEndpoint);
    this.cachedModelExplicit = rawModel.trim().length > 0;
    this.cachedModel = this.normalizeModel(migratedModel);
  }

  // ===== Schema 迁移 (2026-10-25, v2) =====
  // 幂等: schema_version >= 2 时直接返回, 不写任何 key。
  // 失败: 保留 raw key, 记录 LLM_CONFIG_MIGRATION_FAILED, 回退到内置 catalog 默认。
  private async migrateIfNeeded(rawModel: string): Promise<string> {
    const s = this.store!;
    let version: number = 0;
    try {
      version = await s.get(KEY_SCHEMA_VERSION, 0) as number;
    } catch (_e) {
      version = 0;
    }
    if (version >= SCHEMA_VERSION) {
      return rawModel;
    }
    try {
      return await this.migrateToSchemaV2(rawModel);
    } catch (e) {
      console.error('[LlmConfig] LLM_CONFIG_MIGRATION_FAILED '
        + ((e as Error).message ?? String(e)));
      return rawModel;
    }
  }

  private async migrateToSchemaV2(rawModel: string): Promise<string> {
    const vendorId: string = this.cachedVendorId;
    const explicitModel: string = this.getExplicitModelId(vendorId, rawModel);
    let effectiveModel: string = rawModel.trim();
    if (explicitModel.length > 0) {
      // 规则 1/3: 非空 active/vendor 选择优先, 绝不被 catalog 默认覆盖。
      effectiveModel = explicitModel;
    } else if (effectiveModel.length === 0) {
      // 规则 3: model 为空 → provider catalog 默认。
      const defaultCatalog: ProviderCatalog | null = getProviderCatalog(vendorId);
      if (defaultCatalog !== null && defaultCatalog.defaultModelId.length > 0) {
        effectiveModel = defaultCatalog.defaultModelId;
      } else {
        const provider = findProvider(vendorId);
        effectiveModel = provider !== null ? provider.defaultModel : DEFAULT_MODEL;
      }
    }

    const resolved: ResolvedModel = resolveModel(vendorId, effectiveModel);
    let canonicalId: string = resolved.canonicalId;
    if (canonicalId.length === 0) {
      canonicalId = effectiveModel.length > 0 ? effectiveModel : DEFAULT_MODEL;
    }
    if (resolved.reason === 'MODEL_ID_UNRESOLVED') {
      console.warn('[LlmConfig] MODEL_ID_UNRESOLVED model=' + effectiveModel
        + ' vendor=' + vendorId + ' (kept as-is)');
    }

    // 规则 4: 已有 context window 一律保留(含旧用户覆盖的 65536);
    // 只为 catalog 中尚无 key 的模型补初始值。
    let contextWindowsChanged: boolean = false;
    const catalog: ProviderCatalog | null = getProviderCatalog(vendorId);
    if (catalog !== null && this.cachedModelContextWindowsParsed) {
      for (const listing of catalog.models) {
        if (listing.contextWindow <= 0) {
          continue;
        }
        const key: string = LlmConfig.contextWindowKey(vendorId, listing.id);
        if (this.cachedModelContextWindows[key] === undefined) {
          this.cachedModelContextWindows[key] = LlmConfig.normalizeContextWindow(listing.contextWindow);
          contextWindowsChanged = true;
        }
      }
    }

    const s = this.store!;
    await s.put(KEY_MODEL, canonicalId);
    if (resolved.reason.startsWith('ALIAS_RESOLVED:') && resolved.requestedId.length > 0) {
      // 规则 2: 别名 → 规范 ID, 同时保留可逆的 requested_alias。
      await s.put(KEY_REQUESTED_ALIAS, resolved.requestedId);
    } else {
      // 非别名迁移不保留旧 requested_alias, 避免误导后续审计。
      await s.delete(KEY_REQUESTED_ALIAS);
    }
    if (contextWindowsChanged) {
      await s.put(KEY_MODEL_CONTEXT_WINDOWS, JSON.stringify(this.cachedModelContextWindows));
    }
    await s.put(KEY_SCHEMA_VERSION, SCHEMA_VERSION);
    await s.flush();
    return canonicalId;
  }

  // 规则 1: active_vendor_models 非空, 或 vendor_models 含当前 ID → 显式选择。
  // rawModel 为空但 vendor_models 非空时, 也保留第一条用户模型, 不写 catalog 默认。
  private getExplicitModelId(vendorId: string, rawModel: string): string {
    const active: string | undefined = this.cachedActiveVendorModels[vendorId];
    if (active !== undefined && active.trim().length > 0) {
      return active.trim();
    }
    const models: string[] | undefined = this.cachedVendorModels[vendorId];
    if (models === undefined || models.length === 0) {
      return '';
    }
    const trimmedRaw: string = rawModel.trim();
    if (trimmedRaw.length > 0) {
      return models.indexOf(trimmedRaw) >= 0 ? trimmedRaw : '';
    }
    return models[0].trim();
  }

  // ===== API Key (PR1: 委托 ApiKeyVault, 不再用明文 preferences) =====
  // PR2-T2 L3 (2026-09-08): per-vendor API Key — vendorId 给定则查 per-vendor map,否则 fallback 全局
  public async getApiKey(vendorId?: string): Promise<string | null> {
    const keyVendorId: string = vendorId !== undefined && vendorId.length > 0 ? vendorId : this.cachedVendorId;
    if (keyVendorId.length > 0) {
      const per: string | undefined = this.cachedVendorApiKeys[keyVendorId];
      if (per !== undefined && per.length > 0) { return per; }
    }
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
  // PR2-T2 ticket #83 T3 (2026-09-08): defensive copy(Standards #8 fix)— 返回 snapshot 而非 mutable ref
  // 修:用显式 typed local + Object.keys 复制,不用 spread(arkts-no-spread 严格模式禁 object spread into {...obj})
  public getAllVendorApiKeys(): Record<string, string> {
    const snapshot: Record<string, string> = {}
    for (const k of Object.keys(this.cachedVendorApiKeys)) {
      snapshot[k] = this.cachedVendorApiKeys[k]
    }
    return snapshot
  }

  public getAllActiveVendorModels(): Record<string, string> {
    const snapshot: Record<string, string> = {}
    for (const k of Object.keys(this.cachedActiveVendorModels)) {
      snapshot[k] = this.cachedActiveVendorModels[k]
    }
    return snapshot
  }

  public getAllModelContextWindows(): Record<string, number> {
    const snapshot: Record<string, number> = {}
    for (const k of Object.keys(this.cachedModelContextWindows)) {
      snapshot[k] = this.cachedModelContextWindows[k]
    }
    return snapshot
  }

  public getContextWindowTokens(vendorId?: string, model?: string): number {
    const resolvedVendor: string = vendorId !== undefined && vendorId.length > 0
      ? vendorId : this.cachedVendorId
    const resolvedModel: string = model !== undefined && model.trim().length > 0
      ? model.trim() : this.getModel()
    const value: number | undefined = this.cachedModelContextWindows[
      LlmConfig.contextWindowKey(resolvedVendor, resolvedModel)
    ]
    if (value !== undefined) { return LlmConfig.normalizeContextWindow(value) }
    // 没有落盘 key 时不再直接回 65536: 先读 catalog 的 contextWindow。
    const resolved: ResolvedModel = resolveModel(resolvedVendor, resolvedModel)
    if (resolved.listing !== null && resolved.listing.contextWindow > 0) {
      return LlmConfig.normalizeContextWindow(resolved.listing.contextWindow)
    }
    return DEFAULT_CONTEXT_WINDOW_TOKENS
  }

  public async setContextWindowTokens(vendorId: string, model: string, value: number): Promise<void> {
    this.requireInited()
    const normalizedModel: string = model.trim()
    if (vendorId.length === 0 || normalizedModel.length === 0) { return }
    const key: string = LlmConfig.contextWindowKey(vendorId, normalizedModel)
    this.cachedModelContextWindows[key] = LlmConfig.normalizeContextWindow(value)
    this.cachedModelContextWindowsParsed = true
    const s = this.store!
    await s.put(KEY_MODEL_CONTEXT_WINDOWS, JSON.stringify(this.cachedModelContextWindows))
    await s.flush()
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
    // T6 follow-up (2026-09-08): 改 static call 消 VM 重复
    if (LlmConfig.isCustomVendor(this.cachedVendorId)) {
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
    if (LlmConfig.isCustomVendor(this.cachedVendorId)) {
      const activeModel: string | undefined = this.cachedActiveVendorModels[this.cachedVendorId];
      if (activeModel !== undefined && activeModel.trim().length > 0) {
        return this.normalizeModelForVendor(activeModel, this.cachedVendorId);
      }
      // PR2-T2 L1: 优先查 customVendors[] 匹配 id
      const cv: CustomVendorConfig | null = this.findCustomVendor(this.cachedVendorId)
      if (cv !== null) { return cv.model; }
      // legacy 单数向后兼容
      if (this.cachedCustomVendor !== null) { return this.cachedCustomVendor.model; }
    }
    const activeModel: string | undefined = this.cachedActiveVendorModels[this.cachedVendorId];
    if (activeModel !== undefined && activeModel.trim().length > 0) {
      return this.normalizeModelForVendor(activeModel, this.cachedVendorId);
    }
    // PR2-T2 L2: 优先查 vendorModels[vendorId][0](用户加的 model)
    const userModels: string[] | undefined = this.cachedVendorModels[this.cachedVendorId];
    if (userModels !== undefined && userModels.length > 0) {
      return this.normalizeModelForVendor(userModels[0], this.cachedVendorId);
    }
    // L2.5: legacy KEY_MODEL 是用户显式写过的 (含迁移前的旧别名) → 必须胜过 catalog 默认。
    // 没写过时 cachedModelExplicit=false, 继续走 catalog 默认, 这样提供商换默认值能生效。
    if (this.cachedModelExplicit && this.cachedModel.length > 0) {
      return this.cachedModel;
    }
    // L2: provider 默认模型改由内置 catalog 提供 (providers.ets 的字段保留给其它 vendor)。
    // 运行时优先级: active → userModels → 显式 legacy model → catalog 默认。
    const catalog: ProviderCatalog | null = getProviderCatalog(this.cachedVendorId);
    if (catalog !== null && catalog.defaultModelId.length > 0) {
      return catalog.defaultModelId;
    }
    const p = findProvider(this.cachedVendorId);
    if (p !== null) { return p.defaultModel; }
    return this.cachedModel;
  }

  public async setModel(v: string): Promise<void> {
    this.requireInited();
    this.cachedModel = this.normalizeModel(v);
    this.cachedModelExplicit = v.trim().length > 0;
    await this.store!.put(KEY_MODEL, this.cachedModel);
    await this.store!.flush();
  }

  public getActiveVendorModel(vendorId: string): string {
    const activeModel: string | undefined = this.cachedActiveVendorModels[vendorId]
    if (activeModel !== undefined && activeModel.trim().length > 0) { return activeModel }
    const models: string[] = this.getVendorModels(vendorId)
    if (models.length > 0) { return models[0] }
    return ''
  }

  public async setActiveVendorModel(vendorId: string, model: string): Promise<void> {
    this.requireInited()
    const t: string = model.trim()
    if (vendorId.length === 0 || t.length === 0) { return }
    this.cachedActiveVendorModels[vendorId] = t
    const s = this.store!
    await s.put(KEY_ACTIVE_VENDOR_MODELS, JSON.stringify(this.cachedActiveVendorModels))
    await s.flush()
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

  public supportsStrictStructuredOutput(): boolean {
    if (LlmConfig.isCustomVendor(this.cachedVendorId)) {
      const custom: CustomVendorConfig | null = this.findCustomVendor(this.cachedVendorId);
      return custom !== null && custom.strictStructuredOutput === true;
    }
    const provider = findProvider(this.cachedVendorId);
    return provider !== null && provider.strictStructuredOutput;
  }

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
  // T6 follow-up (2026-09-08): 改 public static — VM 也可调(消 VM 重复的 magic)
  // isCustomVendor(id): VM.addCustomVendor 生成 'custom-'+Date.now() id,此 helper 封装 prefix 检测
  public static isCustomVendor(id: string): boolean {
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

  // ===== 2026-10-25: per-vendor 模型元信息(vendor_model_meta) =====
  // 读: 缺失(老数据)返回 null, 调用方回落到 model ID, 不抛错、不清空 chip。
  public getVendorModelMeta(vendorId: string, modelId: string): VendorModelMeta | null {
    const vendorMeta: Record<string, VendorModelMeta> | undefined = this.cachedVendorModelMeta[vendorId];
    if (vendorMeta === undefined) { return null; }
    const meta: VendorModelMeta | undefined = vendorMeta[modelId];
    if (meta === undefined) { return null; }
    // defensive copy: 调用方改字段不污染缓存
    const copy: VendorModelMeta = {
      displayName: meta.displayName,
      contextWindow: meta.contextWindow,
      inputModalities: Array.isArray(meta.inputModalities) ? meta.inputModalities.slice(0) : [],
      source: meta.source,
    };
    return copy;
  }

  public async setVendorModelMeta(vendorId: string, modelId: string, meta: VendorModelMeta): Promise<void> {
    this.requireInited();
    if (vendorId.length === 0 || modelId.length === 0) { return; }
    this.putVendorModelMetaInMemory(vendorId, modelId, meta);
    await this.persistVendorModelMeta();
  }

  // 与 removeVendorModel 同步删: 模型没了, 元信息不能留成僵尸条目
  public async removeVendorModelMeta(vendorId: string, modelId: string): Promise<void> {
    this.requireInited();
    this.dropVendorModelMetaInMemory(vendorId, modelId);
    await this.persistVendorModelMeta();
  }

  private putVendorModelMetaInMemory(vendorId: string, modelId: string, meta: VendorModelMeta): void {
    let vendorMeta: Record<string, VendorModelMeta> | undefined = this.cachedVendorModelMeta[vendorId];
    if (vendorMeta === undefined) {
      vendorMeta = {};
      this.cachedVendorModelMeta[vendorId] = vendorMeta;
    }
    const next: VendorModelMeta = {
      displayName: typeof meta.displayName === 'string' ? meta.displayName : '',
      // 0 表示 discovery 没给, 保持 0; 不借用 normalizeContextWindow(会把 0 抬到 4096)
      contextWindow: meta.contextWindow > 0 ? Math.floor(meta.contextWindow) : 0,
      inputModalities: Array.isArray(meta.inputModalities) ? meta.inputModalities.slice(0) : [],
      source: typeof meta.source === 'string' && meta.source.length > 0 ? meta.source : 'user',
    };
    vendorMeta[modelId] = next;
  }

  private dropVendorModelMetaInMemory(vendorId: string, modelId: string): void {
    const vendorMeta: Record<string, VendorModelMeta> | undefined = this.cachedVendorModelMeta[vendorId];
    if (vendorMeta === undefined) { return; }
    const nextVendor: Record<string, VendorModelMeta> = {};
    for (const k of Object.keys(vendorMeta)) {
      if (k !== modelId) { nextVendor[k] = vendorMeta[k]; }
    }
    if (Object.keys(nextVendor).length === 0) {
      this.cachedVendorModelMeta = this.rebuildRecordWithout<Record<string, VendorModelMeta>>(
        this.cachedVendorModelMeta, vendorId);
    } else {
      this.cachedVendorModelMeta[vendorId] = nextVendor;
    }
  }

  private async persistVendorModelMeta(): Promise<void> {
    await this.writeVendorModelMetaKey();
    await this.store!.flush();
  }

  // 只写 key 不 flush — addVendorModel/removeVendorModel 与 vendor_models 共用一次 flush
  private async writeVendorModelMetaKey(): Promise<void> {
    const s = this.store!;
    if (Object.keys(this.cachedVendorModelMeta).length === 0) {
      await s.delete(KEY_VENDOR_MODEL_META);
    } else {
      await s.put(KEY_VENDOR_MODEL_META, JSON.stringify(this.cachedVendorModelMeta));
    }
  }

  // 老结构 / 手改 JSON 的防御: 缺字段按 0/空串处理, 不让坏 meta 拖垮 chip 读取
  private sanitizeVendorModelMeta(
    raw: Record<string, Record<string, VendorModelMeta>>
  ): Record<string, Record<string, VendorModelMeta>> {
    const out: Record<string, Record<string, VendorModelMeta>> = {};
    // JSON.parse 可能给出数组/字符串/数字等非对象形状, 一律视为无 meta
    if (raw === null || raw === undefined || typeof raw !== 'object' || Array.isArray(raw)) {
      return out;
    }
    for (const vendorId of Object.keys(raw)) {
      const vendorMeta: Record<string, VendorModelMeta> | undefined = raw[vendorId];
      if (vendorMeta === undefined || vendorMeta === null
        || typeof vendorMeta !== 'object' || Array.isArray(vendorMeta)) {
        continue;
      }
      const nextVendor: Record<string, VendorModelMeta> = {};
      for (const modelId of Object.keys(vendorMeta)) {
        const item: VendorModelMeta | undefined = vendorMeta[modelId];
        if (item === undefined || item === null) { continue; }
        const displayName: string = typeof item.displayName === 'string' ? item.displayName : '';
        const contextWindow: number = typeof item.contextWindow === 'number' && item.contextWindow > 0
          ? Math.floor(item.contextWindow) : 0;
        const inputModalities: string[] = [];
        if (Array.isArray(item.inputModalities)) {
          for (const modality of item.inputModalities) {
            if (typeof modality === 'string' && modality.length > 0) {
              inputModalities.push(modality);
            }
          }
        }
        const source: string = typeof item.source === 'string' && item.source.length > 0
          ? item.source : 'user';
        const next: VendorModelMeta = {
          displayName: displayName,
          contextWindow: contextWindow,
          inputModalities: inputModalities,
          source: source,
        };
        nextVendor[modelId] = next;
      }
      if (Object.keys(nextVendor).length > 0) { out[vendorId] = nextVendor; }
    }
    return out;
  }

  public async addVendorModel(vendorId: string, model: string, meta?: VendorModelMeta): Promise<void> {
    const t: string = model.trim();
    if (t.length === 0) { return; }
    const existing: string[] = this.cachedVendorModels[vendorId] ?? [];
    const already: boolean = existing.indexOf(t) >= 0;
    if (!already) {
      this.cachedVendorModels[vendorId] = [...existing, t];
    }
    if (meta !== undefined) {
      // 同一 model ID 重新 discovery 时刷新元信息, 但绝不因缺 meta 清掉已有元信息
      this.putVendorModelMetaInMemory(vendorId, t, meta);
    }
    if (!already || meta !== undefined) {
      const s = this.store!;
      await s.put(KEY_VENDOR_MODELS, JSON.stringify(this.cachedVendorModels));
      if (meta !== undefined) {
        await this.writeVendorModelMetaKey();
      }
      await s.flush();
    }
  }

  public async removeVendorModel(vendorId: string, model: string): Promise<void> {
    const existing: string[] = this.cachedVendorModels[vendorId] ?? [];
    const filtered: string[] = existing.filter((m: string): boolean => m !== model);
    if (existing.length > 0 && filtered.length === 0) {
      // 空数组 — 删 entry 而非存空数组,简化后续 getVendorModels fallback
      // PR2-T2 ticket #83 T2 (2026-09-08): rebuildRecordWithout helper 替代 inline delete loop
      this.cachedVendorModels = this.rebuildRecordWithout<string[]>(this.cachedVendorModels, vendorId)
      // vendor 已无模型: 整组元信息一起删, 不留僵尸条目
      this.cachedVendorModelMeta = this.rebuildRecordWithout<Record<string, VendorModelMeta>>(
        this.cachedVendorModelMeta, vendorId)
    } else if (filtered.length > 0) {
      this.cachedVendorModels[vendorId] = filtered;
      // 2026-10-25: 元信息与 vendor_models 同步删
      this.dropVendorModelMetaInMemory(vendorId, model);
    }
    const s = this.store!;
    await s.put(KEY_VENDOR_MODELS, JSON.stringify(this.cachedVendorModels));
    await this.writeVendorModelMetaKey();
    await s.flush();
  }

  // ===== 恢复默认 =====
  public async resetDefaults(): Promise<void> {
    this.requireInited();
    this.cachedEndpoint = DEFAULT_ENDPOINT;
    this.cachedModel = DEFAULT_MODEL;
    this.cachedModelExplicit = false;
    this.cachedTemperature = DEFAULT_TEMPERATURE;
    this.cachedMaxTokens = DEFAULT_MAX_TOKENS;
    this.cachedTimeoutMs = DEFAULT_TIMEOUT_MS;
    this.cachedEnableThinking = DEFAULT_ENABLE_THINKING;
    this.cachedVendorId = 'deepseek';
    this.cachedCustomVendor = null;
    // PR2-T2 L1: 同时清 customVendors[]
    this.cachedCustomVendors = [];
    // PR2-T2 L2: 同时清 vendorModels
    this.cachedVendorModels = {};
    // 2026-10-25: 同时清模型元信息
    this.cachedVendorModelMeta = {};
    // PR2-T2 L3: 同时清 vendorApiKeys
    this.cachedVendorApiKeys = {};
    this.cachedActiveVendorModels = {};
    this.cachedModelContextWindows = {};
    this.cachedModelContextWindowsParsed = true;
    const s = this.store!;
    await s.put(KEY_ENDPOINT, DEFAULT_ENDPOINT);
    await s.put(KEY_MODEL, DEFAULT_MODEL);
    await s.put(KEY_TEMPERATURE, DEFAULT_TEMPERATURE);
    await s.put(KEY_MAX_TOKENS, DEFAULT_MAX_TOKENS);
    await s.put(KEY_TIMEOUT_MS, DEFAULT_TIMEOUT_MS);
    await s.put(KEY_ENABLE_THINKING, DEFAULT_ENABLE_THINKING);
    await s.put(KEY_VENDOR_ID, 'deepseek');
    await s.put(KEY_SCHEMA_VERSION, SCHEMA_VERSION);
    await s.delete(KEY_REQUESTED_ALIAS);
    await s.delete(KEY_CUSTOM_VENDOR);
    await s.delete(KEY_CUSTOM_VENDORS);
    await s.delete(KEY_VENDOR_MODELS);
    await s.delete(KEY_VENDOR_MODEL_META);
    await s.delete(KEY_VENDOR_API_KEYS);
    await s.delete(KEY_ACTIVE_VENDOR_MODELS);
    await s.delete(KEY_MODEL_CONTEXT_WINDOWS);
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

  private static contextWindowKey(vendorId: string, model: string): string {
    return vendorId + '::' + model
  }

  private static normalizeContextWindow(value: number): number {
    if (value !== value) { return DEFAULT_CONTEXT_WINDOW_TOKENS }
    return Math.max(4096, Math.min(1048576, Math.floor(value)))
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

  // 2026-10-25 模型适配 (计划 §2.3): 删除旧的三个字符串相等白名单,
  // 以及 v3/flash/r1 子串抛 NORMALIZE_KEYWORD_REJECTED 的路径。
  // 现在统一走 catalog ID → alias 解析; 未知 ID 保留原值并记 diagnostic, 不再静默拒绝。
  private normalizeModelForVendor(v: string, vendorId: string): string {
    const resolved: ResolvedModel = resolveModel(vendorId, v);
    if (resolved.reason === 'MODEL_ID_UNRESOLVED') {
      // 其它 vendor 的 catalog 仍为空 (能力待 discovery/人工补齐), 未知 ID 是预期状态,
      // 不在每次 getModel() 时刷日志; DeepSeek 有清单, 未知 ID 才是真 diagnostic。
      const catalog: ProviderCatalog | null = getProviderCatalog(vendorId);
      if (catalog !== null && catalog.models.length > 0) {
        console.warn('[LlmConfig] MODEL_ID_UNRESOLVED model=' + v.trim()
          + ' vendor=' + vendorId + ' (kept as-is)');
      }
    }
    return resolved.canonicalId.length > 0 ? resolved.canonicalId : DEFAULT_MODEL;
  }
}
