/**
 * model-discovery.ets — 运行时 /models 发现(只返回候选, 不落盘)
 *
 * 路径: common/src/main/ets/llm/model-discovery.ets
 * 职责: 对 catalog 不认识的 provider 发起 GET {baseUrl}/models, 把响应解析为
 *       ModelListing[] 候选; 结果只作为设置页候选返回, 绝不写入 preferences。
 * 依赖: @kit.NetworkKit, @kit.ArkTS, ./model-catalog
 *
 * 数据流:
 *   settings / caller → discoverModels(providerId, baseUrl, apiKey, timeoutMs)
 *     → catalog 命中则直接返回内置清单(不发网络)
 *     → 否则 GET /models → data[] / models{} → ModelListing[]
 *     → 失败: ok=false + errorCode, 调用方保留内置 catalog
 *
 * 边界 (照计划 §2.2 / DSH discovery.ts):
 *   - 响应体超过 4 MiB: 直接拒绝, 不截断。
 *   - 容量字段多别名容忍; 认不出的字段只保留 id, 不猜能力。
 *   - 非 2xx / 解析失败 / 超时: ok=false + errorCode; 不抛异常给 UI。
 *   - 不读取也不写入 LlmConfig.preferences。
 *
 * ArkTS 1.1 strict 适配:
 *   - JSON 先转 Record<string, Object> 再逐字段类型收窄, 不使用 any。
 *   - 所有对象字面量显式标注 ModelListing / ModelEffortInfo。
 */

import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { getProviderCatalog } from './model-catalog';
import type { ModelEffortInfo, ModelListing, ProviderCatalog } from './model-catalog';

const MAX_DISCOVERY_BYTES: number = 4 * 1024 * 1024;
const DEFAULT_DISCOVERY_TIMEOUT_MS: number = 10000;

export interface DiscoveryResult {
  ok: boolean;
  models: ModelListing[];
  errorCode: string;
  errorReason: string;
}

function logFallback(providerId: string, errorCode: string, errorReason: string): void {
  console.warn('[model-discovery] MODEL_DISCOVERY_FALLBACK provider=' + providerId
    + ' code=' + errorCode + ' reason=' + errorReason);
}

function failure(providerId: string, errorCode: string, errorReason: string): DiscoveryResult {
  logFallback(providerId, errorCode, errorReason);
  const result: DiscoveryResult = {
    ok: false,
    models: [],
    errorCode: errorCode,
    errorReason: errorReason,
  };
  return result;
}

function buildModelsUrl(baseUrl: string): string {
  const raw: string = baseUrl.trim();
  if (raw.length === 0) {
    return '';
  }
  let base: string = raw.replace(/\/+$/, '');
  const chatIndex: number = base.toLowerCase().indexOf('/chat/completions');
  if (chatIndex >= 0) {
    base = base.substring(0, chatIndex);
  }
  if (base.toLowerCase().endsWith('/models')) {
    return base;
  }
  return base + '/models';
}

function utf8Length(text: string): number {
  const encoder: util.TextEncoder = util.TextEncoder.create('utf-8');
  return encoder.encodeInto(text).length;
}

function responseText(result: Object | ArrayBuffer | string | undefined | null): string {
  if (result === undefined || result === null) {
    return '';
  }
  if (typeof result === 'string') {
    return result as string;
  }
  if (result instanceof ArrayBuffer) {
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
    return decoder.decodeToString(new Uint8Array(result));
  }
  return JSON.stringify(result);
}

function readField(record: Record<string, Object>, key: string): Object | undefined {
  return record[key];
}

function asRecord(value: Object | undefined): Record<string, Object> | null {
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== 'object') {
    return null;
  }
  if (Array.isArray(value)) {
    return null;
  }
  return value as Record<string, Object>;
}

function pickString(record: Record<string, Object>, keys: string[]): string {
  for (const key of keys) {
    const value: Object | undefined = readField(record, key);
    if (typeof value === 'string') {
      const text: string = (value as string).trim();
      if (text.length > 0) {
        return text;
      }
    }
  }
  return '';
}

function pickNumber(record: Record<string, Object>, keys: string[]): number {
  for (const key of keys) {
    const value: Object | undefined = readField(record, key);
    if (typeof value === 'number') {
      const numeric: number = value as number;
      if (numeric === numeric && numeric > 0) {
        return numeric;
      }
    }
    if (typeof value === 'string') {
      const parsed: number = Number(value as string);
      if (parsed === parsed && parsed > 0) {
        return parsed;
      }
    }
  }
  return 0;
}

function nestedNumber(record: Record<string, Object>, parentKey: string, childKey: string): number {
  const parent: Record<string, Object> | null = asRecord(readField(record, parentKey));
  if (parent === null) {
    return 0;
  }
  return pickNumber(parent, [childKey]);
}

function pickStringArray(record: Record<string, Object>, keys: string[]): string[] {
  for (const key of keys) {
    const value: Object | undefined = record[key];
    if (value === undefined || value === null || !Array.isArray(value)) {
      continue;
    }
    const out: string[] = [];
    for (const item of value as Object[]) {
      if (typeof item === 'string' && (item as string).length > 0) {
        out.push(item as string);
      }
    }
    if (out.length > 0) {
      return out;
    }
  }
  return [];
}

function buildEffort(record: Record<string, Object>): ModelEffortInfo {
  const raw: Object | undefined = record['effort'];
  if (raw === undefined || raw === null || typeof raw !== 'object') {
    return { supportedLevels: [], defaultLevel: '' };
  }
  const effortRecord: Record<string, Object> = raw as Record<string, Object>;
  const levels: string[] = pickStringArray(effortRecord,
    ['supported_levels', 'supportedLevels', 'levels']);
  const defaultLevel: string = pickString(effortRecord,
    ['default_level', 'defaultLevel', 'default']);
  const effort: ModelEffortInfo = {
    supportedLevels: levels,
    defaultLevel: defaultLevel,
  };
  return effort;
}

function buildListing(providerId: string, record: Record<string, Object>, fallbackId: string): ModelListing | null {
  const declaredId: string = pickString(record, ['id', 'model']);
  const id: string = declaredId.length > 0 ? declaredId : fallbackId.trim();
  if (id.length === 0) {
    return null;
  }
  const declaredName: string = pickString(record, ['name', 'display_name']);
  let contextWindow: number = pickNumber(record,
    ['context_window', 'contextWindow', 'context_length', 'max_input_tokens']);
  if (contextWindow <= 0) {
    // OpenRouter/网关形状: limit.context 是上下文窗口, 不是输出上限。
    contextWindow = nestedNumber(record, 'limit', 'context');
  }
  let maxOutputTokens: number = pickNumber(record,
    ['max_output_tokens', 'maxOutputTokens', 'max_tokens']);
  if (maxOutputTokens <= 0) {
    maxOutputTokens = nestedNumber(record, 'limit', 'output');
  }
  if (maxOutputTokens <= 0) {
    maxOutputTokens = nestedNumber(record, 'top_provider', 'max_completion_tokens');
  }
  // 官方 /models 直接给能力时就采信; 认不出的字段仍不猜, 留空由解析器按保守处理。
  const inputModalities: string[] = pickStringArray(record,
    ['input_modalities', 'inputModalities', 'modalities']);
  const effort: ModelEffortInfo = buildEffort(record);
  const listing: ModelListing = {
    id: id,
    displayName: declaredName.length > 0 ? declaredName : id,
    providerId: providerId,
    contextWindow: contextWindow > 0 ? Math.floor(contextWindow) : 0,
    maxOutputTokens: maxOutputTokens > 0 ? Math.floor(maxOutputTokens) : 0,
    inputModalities: inputModalities,
    effort: effort,
    source: 'discovery',
  };
  return listing;
}

function containsId(listings: ModelListing[], id: string): boolean {
  for (const listing of listings) {
    if (listing.id === id) {
      return true;
    }
  }
  return false;
}

function pushListing(listings: ModelListing[], providerId: string, record: Record<string, Object>,
  fallbackId: string): void {
  const listing: ModelListing | null = buildListing(providerId, record, fallbackId);
  if (listing === null) {
    return;
  }
  if (containsId(listings, listing.id)) {
    return;
  }
  listings.push(listing);
}

function listingsFromArray(providerId: string, entries: Object[]): ModelListing[] {
  const listings: ModelListing[] = [];
  for (const entry of entries) {
    const record: Record<string, Object> | null = asRecord(entry);
    if (record === null) {
      continue;
    }
    pushListing(listings, providerId, record, '');
  }
  return listings;
}

function listingsFromRecordMap(providerId: string, modelsRecord: Record<string, Object>): ModelListing[] {
  const listings: ModelListing[] = [];
  for (const key of Object.keys(modelsRecord)) {
    const value: Object | undefined = readField(modelsRecord, key);
    const record: Record<string, Object> | null = asRecord(value);
    if (record === null) {
      // 网关 models{} 也允许 "model-id": "display name" 的形态。
      if (typeof value === 'string') {
        const displayName: string = (value as string).trim();
        const directEffort: ModelEffortInfo = {
          supportedLevels: [],
          defaultLevel: '',
        };
        const direct: ModelListing = {
          id: key,
          displayName: displayName.length > 0 ? displayName : key,
          providerId: providerId,
          contextWindow: 0,
          maxOutputTokens: 0,
          inputModalities: [],
          effort: directEffort,
          source: 'discovery',
        };
        if (!containsId(listings, direct.id)) {
          listings.push(direct);
        }
      }
      continue;
    }
    pushListing(listings, providerId, record, key);
  }
  return listings;
}

function parseModelEntries(providerId: string, raw: string): ModelListing[] | null {
  let parsed: Record<string, Object>;
  try {
    parsed = JSON.parse(raw) as Record<string, Object>;
  } catch (_e) {
    return null;
  }
  if (parsed === null) {
    return null;
  }
  const dataValue: Object | undefined = readField(parsed, 'data');
  if (Array.isArray(dataValue)) {
    return listingsFromArray(providerId, dataValue as Object[]);
  }
  const modelsValue: Object | undefined = readField(parsed, 'models');
  if (Array.isArray(modelsValue)) {
    return listingsFromArray(providerId, modelsValue as Object[]);
  }
  const modelsRecord: Record<string, Object> | null = asRecord(modelsValue);
  if (modelsRecord !== null) {
    return listingsFromRecordMap(providerId, modelsRecord);
  }
  return null;
}

/**
 * 纯解析入口: 拿到 /models 原文后直接解码, 不发网络。
 * 供设置页在复用已缓存的响应体时使用, 也让解析规则可被单测直接覆盖。
 */
export function parseDiscoveryPayload(providerId: string, raw: string): DiscoveryResult {
  const provider: string = providerId.trim();
  const listings: ModelListing[] | null = parseModelEntries(provider, raw);
  if (listings === null) {
    return failure(provider, 'DISCOVERY_PARSE_FAILED', 'payload is not a model list');
  }
  if (listings.length === 0) {
    return failure(provider, 'DISCOVERY_EMPTY_LIST', 'payload has no model entries');
  }
  const parsed: DiscoveryResult = {
    ok: true,
    models: listings,
    errorCode: '',
    errorReason: '',
  };
  return parsed;
}

export async function discoverModels(
  providerId: string,
  baseUrl: string,
  apiKey: string,
  timeoutMs: number,
): Promise<DiscoveryResult> {
  const provider: string = providerId.trim();

  // catalog route 是权威: 已内置清单的 provider 不发网络。
  const catalog: ProviderCatalog | null = getProviderCatalog(provider);
  if (catalog !== null && catalog.models.length > 0) {
    const authoritative: DiscoveryResult = {
      ok: true,
      models: catalog.models.slice(0),
      errorCode: '',
      errorReason: 'CATALOG_AUTHORITATIVE',
    };
    return authoritative;
  }

  const url: string = buildModelsUrl(baseUrl);
  if (url.length === 0) {
    return failure(provider, 'DISCOVERY_INVALID_BASE_URL', 'baseUrl is empty');
  }
  const key: string = apiKey.trim();
  if (key.length === 0) {
    return failure(provider, 'DISCOVERY_NO_API_KEY', 'apiKey is empty');
  }
  const effectiveTimeout: number = timeoutMs > 0 ? timeoutMs : DEFAULT_DISCOVERY_TIMEOUT_MS;

  const request = http.createHttp();
  let response: http.HttpResponse;
  try {
    response = await request.request(url, {
      method: http.RequestMethod.GET,
      header: {
        'Accept': 'application/json',
        'Authorization': 'Bearer ' + key,
      },
      connectTimeout: effectiveTimeout,
      readTimeout: effectiveTimeout,
      expectDataType: http.HttpDataType.STRING,
    });
  } catch (e) {
    request.destroy();
    const error: BusinessError = e as BusinessError;
    const message: string = error.message ?? String(e);
    const timedOut: boolean = error.code === 2300028
      || message.toLowerCase().indexOf('timeout') >= 0;
    return failure(provider, timedOut ? 'DISCOVERY_TIMEOUT' : 'DISCOVERY_NETWORK_ERROR', message);
  }
  request.destroy();

  if (response.responseCode < 200 || response.responseCode >= 300) {
    return failure(provider, 'DISCOVERY_HTTP_ERROR', 'HTTP ' + response.responseCode.toString());
  }

  const raw: string = responseText(response.result);
  if (utf8Length(raw) > MAX_DISCOVERY_BYTES) {
    return failure(provider, 'DISCOVERY_TOO_LARGE', 'response body exceeds 4 MiB');
  }

  const models: ModelListing[] | null = parseModelEntries(provider, raw);
  if (models === null) {
    return failure(provider, 'DISCOVERY_PARSE_ERROR', 'response did not contain data[] or models{}');
  }

  const result: DiscoveryResult = {
    ok: true,
    models: models,
    errorCode: '',
    errorReason: '',
  };
  return result;
}
