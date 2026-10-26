/**
 * model-resolver.ets — 模型 ID 解析(先 catalog ID, 后别名表)
 *
 * 路径: common/src/main/ets/llm/model-resolver.ets
 * 职责: 把用户/旧配置里的 model 字符串解析成当前 provider 的规范 ID,
 *       同时返回该 ID 在清单中的 Listing、准确型号的 ModelSpec 与不可用原因。
 *       清单回答"模型是否存在", 规格回答"请求怎么构造" — 两者不互相推导。
 * 依赖: ./model-catalog (内置清单 + 规格)
 *
 * 数据流:
 *   LlmConfig.normalizeModel / LlmClient.call / ModelSelector
 *     → resolveModel(providerId, requestedId)
 *     → ModelListing + ModelSpec + usable/reason
 *
 * 解析顺序 (不可交换):
 *   1. 空输入        → provider 的 defaultModelId, reason='EMPTY_REQUEST'
 *   2. catalog 命中  → 原样使用, usable=true
 *   3. 别名命中      → canonicalId=规范 ID, degraded=false, reason='ALIAS_RESOLVED:<原值>'
 *   4. 都不命中      → usable=false, reason='MODEL_ID_UNRESOLVED', canonicalId 保留原值
 *
 * 规格查找独立于清单: 清单为空的 vendor (通义/GLM/Kimi/豆包) 仍可能有一份
 * verified / unverified 的 ModelSpec, 由 spec 自身声明能否构造请求字段。
 *
 * ArkTS 1.1 strict 适配:
 *   - interface + 显式 ModelListing/ModelSpec/ProviderCatalog 类型, 不使用 any。
 *   - 别名表用显式 Record<string, string>, 不写裸对象字面量索引。
 */

import { getCatalogDefaultListing, getModelSpec, getProviderCatalog } from './model-catalog';
import type { ModelListing, ModelSpec, ProviderCatalog } from './model-catalog';

export interface ResolvedModel {
  requestedId: string;
  canonicalId: string;
  listing: ModelListing | null;
  spec: ModelSpec | null;
  usable: boolean;
  degraded: boolean;
  reason: string;
}

// 服务端实测回显的旧别名 → 当前规范 ID (2026-10-25)
const DEEPSEEK_ALIASES: Record<string, string> = {
  'deepseek-v4-flash': 'deepseek-flash',
  'deepseek-v4-flash-vision-exp': 'deepseek-flash',
};

function findListing(catalog: ProviderCatalog, id: string): ModelListing | null {
  for (const listing of catalog.models) {
    if (listing.id === id) {
      return listing;
    }
  }
  return null;
}

function resolveProviderDefault(providerId: string): string {
  const catalog: ProviderCatalog | null = getProviderCatalog(providerId);
  if (catalog !== null) {
    return catalog.defaultModelId;
  }
  return '';
}

function resolveAlias(providerId: string, requestedId: string): string {
  if (providerId !== 'deepseek') {
    return '';
  }
  const canonical: string | undefined = DEEPSEEK_ALIASES[requestedId];
  return canonical !== undefined ? canonical : '';
}

function resolveSpec(providerId: string, canonicalId: string): ModelSpec | null {
  if (canonicalId.length === 0) {
    return null;
  }
  return getModelSpec(providerId, canonicalId);
}

export function resolveModel(providerId: string, requestedId: string): ResolvedModel {
  const provider: string = providerId.trim();
  const requested: string = requestedId.trim();
  const catalog: ProviderCatalog | null = getProviderCatalog(provider);

  // 1. 空输入 → provider catalog 默认, 不把空白字符串当模型名发送。
  if (requested.length === 0) {
    const defaultId: string = resolveProviderDefault(provider);
    const defaultListing: ModelListing | null = getCatalogDefaultListing(provider);
    const emptyResult: ResolvedModel = {
      requestedId: requested,
      canonicalId: defaultId.length > 0 ? defaultId : requested,
      listing: defaultListing,
      spec: resolveSpec(provider, defaultId),
      usable: defaultListing !== null,
      degraded: false,
      reason: 'EMPTY_REQUEST',
    };
    return emptyResult;
  }

  // 2. 先查当前清单: 清单直接存在的 ID 不做二次猜测。
  if (catalog !== null) {
    const directListing: ModelListing | null = findListing(catalog, requested);
    if (directListing !== null) {
      const directResult: ResolvedModel = {
        requestedId: requested,
        canonicalId: requested,
        listing: directListing,
        spec: resolveSpec(provider, requested),
        usable: true,
        degraded: false,
        reason: '',
      };
      return directResult;
    }
  }

  // 3. 再查别名表: canonicalId 写规范 ID, requestedId 保留输入。
  const canonicalId: string = resolveAlias(provider, requested);
  if (canonicalId.length > 0) {
    const aliasListing: ModelListing | null = catalog !== null ? findListing(catalog, canonicalId) : null;
    const aliasResult: ResolvedModel = {
      requestedId: requested,
      canonicalId: canonicalId,
      listing: aliasListing,
      spec: resolveSpec(provider, canonicalId),
      usable: aliasListing !== null,
      degraded: false,
      reason: 'ALIAS_RESOLVED:' + requested,
    };
    return aliasResult;
  }

  // 4. 未知 ID: 保留原值 + 原因, 不静默换型号; 规格仍按准确型号查找。
  const unresolvedResult: ResolvedModel = {
    requestedId: requested,
    canonicalId: requested,
    listing: null,
    spec: resolveSpec(provider, requested),
    usable: false,
    degraded: false,
    reason: 'MODEL_ID_UNRESOLVED',
  };
  return unresolvedResult;
}
