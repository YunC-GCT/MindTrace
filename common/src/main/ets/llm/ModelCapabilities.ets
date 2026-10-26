/**
 * ModelCapabilities.ets — 从 ModelSpec 推导思考/强度能力, 从 Listing 推导图像能力
 *
 * 路径: common/src/main/ets/llm/ModelCapabilities.ets
 * 职责: 把「能不能开思考 / 能不能关 / 可调哪些推理强度 / 能不能收图像」收敛成
 *       ModelSpec.request + ModelListing.inputModalities 的字段读取。
 * 依赖: ./model-resolver (保留旧入口 resolveModelCapability)
 *
 * 数据流:
 *   LlmClient.composeRequest / 设置页
 *     → resolveModel(providerId, model)
 *     → resolveCapabilities(resolved.listing, resolved.spec)
 *
 * 四种 control 必须区分 (design §修正后的 ModelSpec):
 *   - toggle      可开可关, defaultEnabled 决定未选择时的默认
 *   - always_on   强制开启, on/off 写入均为空; effort 仍可单独调
 *   - unsupported 已确认不支持 → UI 不显示开关, 请求不写 thinking/effort
 *   - unverified  尚无证据 → UI 显示「能力未确认」, 请求不猜任何字段
 *
 * 未知模型为什么不猜: 猜错的两个方向代价不对称 —— 把 always_on 模型写成 disabled
 * 会让请求直接失败或降智, 给不支持思考的模型塞 thinking/reasoning_effort 可能 400;
 * 而不写字段最坏只是沿用服务端默认。所以 unverified 的语义是「不表态」。
 *
 * ArkTS 1.1 strict 适配:
 *   - 能力只读 Listing + Spec, 不再调用 model.indexOf(...) 猜族群。
 *   - 对象字面量显式标注 ModelCapability。
 */

import { resolveModel } from './model-resolver';
import type { ResolvedModel } from './model-resolver';
import type { ModelEffortSpec, ModelListing, ModelSpec } from './model-catalog';

export type ThinkingMode = 'toggle' | 'always_on' | 'unsupported' | 'unverified';

export interface ModelCapability {
  thinking: ThinkingMode;
  efforts: string[];                 // 可调推理强度; 空数组表示没有可调档位
  defaultEffort: string;             // spec.request.effort.defaultLevel; 空串表示无默认档
  supportsImage: boolean;            // inputModalities 含 'image' 才为 true
  defaultThinkingEnabled: boolean;   // 用户未选择时按规格推出的默认 (unverified/unsupported = false)
  effortPath: string[];              // 写入路径, 供调试日志/测试核对
}

export function supportsImageInput(listing: ModelListing | null): boolean {
  if (listing === null) {
    return false;
  }
  return listing.inputModalities.indexOf('image') >= 0;
}

export function resolveCapabilities(
  listing: ModelListing | null,
  spec: ModelSpec | null,
): ModelCapability {
  const supportsImage: boolean = supportsImageInput(listing);
  if (spec === null) {
    // 没有规格 ≠ 不支持; 这是"没证据", 请求层与 UI 都必须显示未确认。
    const unknown: ModelCapability = {
      thinking: 'unverified',
      efforts: [],
      defaultEffort: '',
      supportsImage: supportsImage,
      defaultThinkingEnabled: false,
      effortPath: [],
    };
    return unknown;
  }

  const thinking: ThinkingMode = spec.request.thinking.control;
  const thinkingAllowed: boolean = thinking === 'toggle' || thinking === 'always_on';
  const effort: ModelEffortSpec | null = spec.request.effort;
  const efforts: string[] = thinkingAllowed && effort !== null ? effort.levels.slice(0) : [];
  const defaultEffort: string = thinkingAllowed && effort !== null && effort.defaultLevel !== null
    ? effort.defaultLevel : '';
  const defaultThinkingEnabled: boolean = thinking === 'always_on'
    || (thinking === 'toggle' && spec.request.thinking.defaultEnabled === true);
  const capability: ModelCapability = {
    thinking: thinking,
    efforts: efforts,
    defaultEffort: defaultEffort,
    supportsImage: supportsImage,
    defaultThinkingEnabled: defaultThinkingEnabled,
    effortPath: thinkingAllowed && effort !== null ? effort.path.slice(0) : [],
  };
  return capability;
}

// 兼容旧调用点: 先走 catalog/alias 解析拿 listing + spec, 再按规格推导。
export function resolveModelCapability(vendorId: string, model: string): ModelCapability {
  const resolved: ResolvedModel = resolveModel(vendorId, model);
  return resolveCapabilities(resolved.listing, resolved.spec);
}
