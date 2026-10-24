/**
 * ModelCapabilities.ets — 从模型清单条目推导思考/图像能力
 *
 * 路径: common/src/main/ets/llm/ModelCapabilities.ets
 * 职责: 把「能不能开思考 / 可调哪些推理强度 / 能不能收图像」从模型名子串
 *       收敛成 ModelListing 的字段读取, 供流式与非流式两条传输路径共用。
 * 依赖: ./model-resolver (保留旧入口 resolveModelCapability)
 *
 * 数据流:
 *   LlmClient.callJsonInternal / LlmClient.callStreamInternal
 *     → resolveModel(providerId, model).listing
 *     → resolveCapabilities(listing)
 *     → buildThinkingFields(body, capability, request)
 *
 * 规则:
 *   - effort.supportedLevels 非空 → thinking='toggle', efforts=supportedLevels
 *   - effort.supportedLevels 为空 → thinking='unsupported', 一个思考字段都不写
 *   - inputModalities 含 'image' → supportsImage=true
 *   - listing 为 null / 未知条目 → 无思考、纯文本 (保守处理)
 *
 * 未知模型为什么不猜: 猜错的两个方向代价不对称 —— 把 always_on 模型写成 disabled
 * 会让请求直接失败或降智, 给不支持思考的模型塞 thinking/reasoning_effort 可能 400;
 * 而不写字段最坏只是沿用服务端默认。所以 unsupported 的语义是「不表态」, 不是「关掉」。
 *
 * ArkTS 1.1 strict 适配:
 *   - 能力只读 ModelListing, 不再调用 model.indexOf(...)。
 *   - 对象字面量显式标注 ModelCapability。
 */

import { resolveModel } from './model-resolver';
import type { ResolvedModel } from './model-resolver';
import type { ModelListing } from './model-catalog';

export type ThinkingMode = 'toggle' | 'always_on' | 'unsupported';

export interface ModelCapability {
  thinking: ThinkingMode;
  efforts: string[];       // 可调推理强度; 空数组表示不支持
  defaultEffort: string;   // listing.effort.defaultLevel; 空串表示无默认档
  supportsImage: boolean;  // inputModalities 含 'image' 才为 true
}

export function supportsImageInput(listing: ModelListing | null): boolean {
  if (listing === null) {
    return false;
  }
  return listing.inputModalities.indexOf('image') >= 0;
}

export function resolveCapabilities(listing: ModelListing | null): ModelCapability {
  if (listing === null) {
    const unknown: ModelCapability = {
      thinking: 'unsupported',
      efforts: [],
      defaultEffort: '',
      supportsImage: false,
    };
    return unknown;
  }

  const levels: string[] = listing.effort.supportedLevels;
  const supportsImage: boolean = supportsImageInput(listing);
  if (levels.length === 0) {
    const noThinking: ModelCapability = {
      thinking: 'unsupported',
      efforts: [],
      defaultEffort: '',
      supportsImage: supportsImage,
    };
    return noThinking;
  }

  const toggle: ModelCapability = {
    thinking: 'toggle',
    efforts: levels.slice(0),
    defaultEffort: listing.effort.defaultLevel,
    supportsImage: supportsImage,
  };
  return toggle;
}

// 兼容旧调用点 (LlmClient 历史签名为 vendorId + model):
// 先走 catalog/alias 解析拿 listing, 再按清单字段推导; 不再看模型名子串。
export function resolveModelCapability(vendorId: string, model: string): ModelCapability {
  const resolved: ResolvedModel = resolveModel(vendorId, model);
  return resolveCapabilities(resolved.listing);
}
