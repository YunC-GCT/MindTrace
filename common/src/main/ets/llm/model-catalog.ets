/**
 * model-catalog.ets — L2 内置模型清单(规范 ID + 能力)
 *
 * 路径: common/src/main/ets/llm/model-catalog.ets
 * 职责: 为每个 provider 提供离线可用的默认模型条目与能力字段; 是
 *       "模型 ID / 上下文 / 输出上限 / 输入模态 / 思考档位" 的唯一内置真源。
 * 依赖: 无(纯静态数据 + 查找函数)
 *
 * 数据流:
 *   providers.ets (L1 route) → model-catalog.ets (L2 listing)
 *     → model-resolver.ets (ID/alias 解析) → ModelCapabilities.ets / LlmClient.ets
 *
 * 数据来源 (2026-10-25 任务书官方 /models 实时清单):
 *   deepseek-flash   DeepSeek-V4.1-Flash  context 1048576  max_output 393216  text,image  low/high/max (default high)
 *   deepseek-v4-pro  DeepSeek-V4-Pro      context 1048576  max_output 393216  text        low/high/max (default high)
 *
 * 其余 4 个 vendor (tongyi / glm / kimi / doubao) 的内置清单当前为空:
 *   能力待 discovery 或人工补齐。不要为了让 UI 有数据而编造 contextWindow /
 *   maxOutputTokens / inputModalities; 未知能力按解析器的保守策略处理。
 *
 * ArkTS 1.1 strict 适配:
 *   - 无对象字面量裸索引; 所有条目显式标注 ModelListing / ProviderCatalog。
 *   - 数组与对象均为静态常量, 不在这里做网络或 preferences 读写。
 */

export interface ModelEffortInfo {
  supportedLevels: string[];
  defaultLevel: string;
}

export interface ModelListing {
  id: string;
  displayName: string;
  providerId: string;
  contextWindow: number;
  maxOutputTokens: number;
  inputModalities: string[];        // 'text' | 'image'
  effort: ModelEffortInfo;          // supportedLevels 为空数组 = 该模型无思考档
  source: string;                   // 'catalog' | 'discovery' | 'user'
}

export interface ProviderCatalog {
  providerId: string;
  defaultModelId: string;
  models: ModelListing[];
}

const DEEPSEEK_EFFORT: ModelEffortInfo = {
  supportedLevels: ['low', 'high', 'max'],
  defaultLevel: 'high',
};

const DEEPSEEK_FLASH: ModelListing = {
  id: 'deepseek-flash',
  displayName: 'DeepSeek-V4.1-Flash',
  providerId: 'deepseek',
  contextWindow: 1048576,
  maxOutputTokens: 393216,
  inputModalities: ['text', 'image'],
  effort: DEEPSEEK_EFFORT,
  source: 'catalog',
};

const DEEPSEEK_V4_PRO: ModelListing = {
  id: 'deepseek-v4-pro',
  displayName: 'DeepSeek-V4-Pro',
  providerId: 'deepseek',
  contextWindow: 1048576,
  maxOutputTokens: 393216,
  inputModalities: ['text'],
  effort: DEEPSEEK_EFFORT,
  source: 'catalog',
};

const DEEPSEEK_CATALOG: ProviderCatalog = {
  providerId: 'deepseek',
  defaultModelId: 'deepseek-v4-pro',
  models: [DEEPSEEK_FLASH, DEEPSEEK_V4_PRO],
};

// 能力待 discovery 或人工补齐 — 只保留 providers.ets 已有的默认模型 ID。
const TONGYI_CATALOG: ProviderCatalog = {
  providerId: 'tongyi',
  defaultModelId: 'qwen3-max',
  models: [],
};

const GLM_CATALOG: ProviderCatalog = {
  providerId: 'glm',
  defaultModelId: 'glm-5.3',
  models: [],
};

const KIMI_CATALOG: ProviderCatalog = {
  providerId: 'kimi',
  defaultModelId: 'kimi-k2.6',
  models: [],
};

const DOUBAO_CATALOG: ProviderCatalog = {
  providerId: 'doubao',
  defaultModelId: 'doubao-seed-1.6',
  models: [],
};

const PROVIDER_CATALOGS: ProviderCatalog[] = [
  DEEPSEEK_CATALOG,
  TONGYI_CATALOG,
  GLM_CATALOG,
  KIMI_CATALOG,
  DOUBAO_CATALOG,
];

export function getProviderCatalog(providerId: string): ProviderCatalog | null {
  const id: string = providerId.trim();
  for (const catalog of PROVIDER_CATALOGS) {
    if (catalog.providerId === id) {
      return catalog;
    }
  }
  return null;
}

export function getCatalogDefaultListing(providerId: string): ModelListing | null {
  const catalog: ProviderCatalog | null = getProviderCatalog(providerId);
  if (catalog === null) {
    return null;
  }
  for (const listing of catalog.models) {
    if (listing.id === catalog.defaultModelId) {
      return listing;
    }
  }
  return null;
}
