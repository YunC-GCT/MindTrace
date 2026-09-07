// MindTrace - LLM 配置管理(单例 + preferences 持久化 + 运行时读写)
// 创建: 2026-07-14

import { preferences } from '@kit.ArkData';
import { LlmConfigInitResult, LlmError } from './LlmTypes';

const STORE_NAME = 'llm_config';
const KEY_API_KEY = 'api_key';
const KEY_ENDPOINT = 'endpoint';
const KEY_MODEL = 'model';
const KEY_TEMPERATURE = 'temperature';
const KEY_MAX_TOKENS = 'max_tokens';
const KEY_TIMEOUT_MS = 'timeout_ms';
const KEY_ENABLE_THINKING = 'enable_thinking';

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
  }

  // ===== API Key =====
  public async getApiKey(): Promise<string | null> {
    this.requireInited();
    const v: string = await this.store!.get(KEY_API_KEY, '') as string;
    return v.length > 0 ? v : null;
  }

  public async setApiKey(key: string): Promise<void> {
    this.requireInited();
    const t: string = key.trim();
    if (t.length === 0) { throw new LlmError('API key empty', 'NOT_INITIALIZED'); }
    await this.store!.put(KEY_API_KEY, t);
    await this.store!.flush();
  }

  public async isConfigured(): Promise<boolean> {
    const k = await this.getApiKey();
    return k !== null && k.length > 0;
  }

  public async clearApiKey(): Promise<void> {
    this.requireInited();
    await this.store!.delete(KEY_API_KEY);
    await this.store!.flush();
  }

  // ===== Endpoint =====
  public getEndpoint(): string { return this.cachedEndpoint; }
  public async setEndpoint(v: string): Promise<void> {
    this.requireInited();
    this.cachedEndpoint = this.normalizeEndpoint(v);
    await this.store!.put(KEY_ENDPOINT, this.cachedEndpoint);
    await this.store!.flush();
  }

  // ===== Model =====
  public getModel(): string { return this.cachedModel; }
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

  // ===== 恢复默认 =====
  public async resetDefaults(): Promise<void> {
    this.requireInited();
    this.cachedEndpoint = DEFAULT_ENDPOINT;
    this.cachedModel = DEFAULT_MODEL;
    this.cachedTemperature = DEFAULT_TEMPERATURE;
    this.cachedMaxTokens = DEFAULT_MAX_TOKENS;
    this.cachedTimeoutMs = DEFAULT_TIMEOUT_MS;
    this.cachedEnableThinking = false;
    const s = this.store!;
    await s.put(KEY_ENDPOINT, DEFAULT_ENDPOINT);
    await s.put(KEY_MODEL, DEFAULT_MODEL);
    await s.put(KEY_TEMPERATURE, DEFAULT_TEMPERATURE);
    await s.put(KEY_MAX_TOKENS, DEFAULT_MAX_TOKENS);
    await s.put(KEY_TIMEOUT_MS, DEFAULT_TIMEOUT_MS);
    await s.put(KEY_ENABLE_THINKING, false);
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
    const t: string = v.trim();
    if (t.length === 0) {
      return DEFAULT_ENDPOINT;
    }
    const lower: string = t.toLowerCase();
    if (lower.indexOf('siliconflow') >= 0) {
      throw new LlmError(
        `LlmConfig.normalizeEndpoint: input "${v}" matches reserved keyword "siliconflow"; ` +
        `siliconflow is not supported. Use DEFAULT_ENDPOINT or override ` +
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
    const t: string = v.trim();
    if (t.length === 0) {
      return DEFAULT_MODEL;
    }
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
        `DEFAULT_MODEL is enforced. Reserved keywords: v3, flash, deepseek-chat, ` +
        `deepseek-reasoner, r1. ` +
        `(DEFAULT_MODEL itself is allowed — see ticket PR0 fix 2026-09-06.)`,
        'NORMALIZE_KEYWORD_REJECTED'
      );
    }
    return t;
  }
}
