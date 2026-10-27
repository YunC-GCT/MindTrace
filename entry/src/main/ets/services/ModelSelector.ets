/**
 * ModelSelector.ets — 模型选择业务
 *
 * 路径: entry/src/main/ets/services/ModelSelector.ets
 * 职责: 模型状态读取 + 显示名格式化 + 可用性判定(usable / degraded / 中文原因)
 * 依赖: common (LlmConfig + resolveModel + model-catalog)
 *
 * 用法:
 *   import { ModelSelector } from '../services/ModelSelector';
 *   ModelSelector.currentLabel()                       // → "DeepSeek-V4-Pro"
 *   ModelSelector.availabilityFor(vendorId, listing)   // → chip 置灰/弱提示/保存拦截
 *
 * 2026-10-25: 元信息读取
 *   - 显示名优先 catalog listing, 其次 vendor_model_meta.displayName, 最后回落模型 ID。
 *   - 可用性以 resolveModel() 为唯一真源; 只在"没有权威内置清单可对照"时降级:
 *       discovery 拿到 / 没有 catalog 的 vendor(通义/GLM/Kimi/豆包/自定义) → usable + degraded(能力未确认),
 *       有 catalog 但 ID 不在其中(如 DeepSeek 手输错 ID) → unusable(unresolved), 保存需拦截。
 *
 * 2026-10-26: 能力信号只认规格证据 (common/capabilitySignal), 与规格控件同源:
 *   - verified → 不降级; partial → 「字段已核实（默认值未证实）」;
 *   - 无规格 / unverified → degraded + 「能力未确认」, 但仍允许保存(不伪装成不支持)。
 *   清单为空只代表"没有可发现清单", 不再被当成"能力未知"。
 */

import { capabilityHint, capabilitySignal, LlmConfig, getProviderCatalog, resolveModel } from 'common';
import type { CapabilitySignal, ModelListing, ModelSpec, ProviderCatalog, ResolvedModel } from 'common';

export interface ModelAvailability {
  usable: boolean;
  degraded: boolean;
  reasonCode: string;   // resolveModel().reason 或 CAPABILITY_UNCONFIRMED
  hint: string;         // 中文短提示; 空串 = 不显示
}

export class ModelSelector {
  /**
   * 当前模型的显示标签 (供 UI 显示)
   * 读取 LlmConfig 的 vendor + model, 由 catalog/别名解析出 listing;
   * 清单里没有该 ID 时查 vendor_model_meta 的 displayName, 最后原样返回 ID。
   */
  static currentLabel(): string {
    const config: LlmConfig = LlmConfig.getInstance();
    const vendorId: string = config.getVendorId().trim();
    const id: string = config.getModel().trim();
    const resolved: ResolvedModel = resolveModel(vendorId, id);
    if (resolved.listing !== null) {
      return resolved.listing.displayName;
    }
    const metaKey: string = resolved.canonicalId.length > 0 ? resolved.canonicalId : id;
    const meta = config.getVendorModelMeta(vendorId, metaKey);
    if (meta !== null && meta.displayName.length > 0) {
      return meta.displayName;
    }
    return id;
  }

  /**
   * 当前模型的原始 ID (供后续选择器 UI 列表展示/匹配)
   */
  static currentRaw(): string {
    return LlmConfig.getInstance().getModel().trim();
  }

  static availabilityFor(vendorId: string, listing: ModelListing): ModelAvailability {
    return ModelSelector.availabilityOf(vendorId, listing.id, listing.source);
  }

  /**
   * 准确型号的 ModelSpec; 规格只按 (providerId, canonicalId) 查, 不看 vendor 名推导。
   * resolveModel 已经带上 canonicalId + spec, 不再二次查表。
   */
  static specFor(vendorId: string, modelId: string): ModelSpec | null {
    return resolveModel(vendorId.trim(), modelId.trim()).spec;
  }

  /**
   * 能力信号: 只读规格证据 ('verified' | 'partial' | 'unconfirmed')。
   * 缺失规格 = 未确认, 不是"不支持"; 清单是否存在不影响这个判断。
   */
  static capabilitySignalOf(vendorId: string, modelId: string): CapabilitySignal {
    return capabilitySignal(ModelSelector.specFor(vendorId, modelId));
  }

  /**
   * 面板横幅用: 清单为空时补一句能力状态 (空串 = 无需提示)。
   * 与 chip hint、规格控件同源, 避免"未提供内置清单"和思考开关同时出现。
   */
  static capabilityNote(vendorId: string, modelId: string): string {
    const signal: CapabilitySignal = ModelSelector.capabilitySignalOf(vendorId, modelId);
    if (signal === 'verified') { return '请求字段已核实'; }
    return capabilityHint(signal);
  }

  /**
   * 可用性判定。source 来自 ModelListing.source('catalog' | 'discovery' | 'user')。
   * 不在这里编造上下文/模态/输出上限 — 只决定"能不能选、要不要提示"。
   */
  static availabilityOf(vendorId: string, modelId: string, source: string): ModelAvailability {
    const provider: string = vendorId.trim();
    const requested: string = modelId.trim();
    const resolved: ResolvedModel = resolveModel(provider, requested);
    if (resolved.usable) {
      const signal: CapabilitySignal = capabilitySignal(resolved.spec);
      if (signal !== 'verified') {
        return ModelSelector.byCapability(signal);
      }
      // 字段已核实: 只剩解析层的旧别名映射需要提示, 其余不打扰用户。
      if (resolved.reason.startsWith('ALIAS_RESOLVED:')) {
        const alias: ModelAvailability = {
          usable: true,
          degraded: true,
          reasonCode: resolved.reason,
          hint: ModelSelector.reasonText(resolved.reason),
        };
        return alias;
      }
      const clean: ModelAvailability = {
        usable: true,
        degraded: false,
        reasonCode: '',
        hint: '',
      };
      return clean;
    }

    // discovery 返回的 ID 已被官方 /models 证实存在, 只是能力字段没给全 → 降级可用。
    if (source === 'discovery') {
      return ModelSelector.byCapability(capabilitySignal(resolved.spec));
    }

    // 没有权威内置清单可对照的 vendor(通义/GLM/Kimi/豆包/自定义): ID 无从证伪,
    // 按"能力未确认"处理, 不拦保存; 有清单的 vendor 才把未命中当不可用。
    const catalog: ProviderCatalog | null = getProviderCatalog(provider);
    const hasAuthoritativeCatalog: boolean = catalog !== null && catalog.models.length > 0;
    if (!hasAuthoritativeCatalog) {
      return ModelSelector.byCapability(capabilitySignal(resolved.spec));
    }

    const blocked: ModelAvailability = {
      usable: false,
      degraded: resolved.degraded,
      reasonCode: resolved.reason,
      hint: ModelSelector.reasonText(resolved.reason),
    };
    return blocked;
  }

  // 能力未确认/部分确认: 仍允许保存(不伪装成不支持), 只降级提示。
  // verified 也走这里(无权威清单的 vendor 走这条), 必须原样放行 —— 否则
  // 清单为空的手动 ID 会一边显示"请求字段已核实"、一边挂"能力未确认"。
  private static byCapability(signal: CapabilitySignal): ModelAvailability {
    if (signal === 'verified') {
      const clean: ModelAvailability = {
        usable: true,
        degraded: false,
        reasonCode: '',
        hint: '',
      };
      return clean;
    }
    const code: string = signal === 'partial' ? 'CAPABILITY_PARTIAL' : 'CAPABILITY_UNCONFIRMED';
    const degraded: ModelAvailability = {
      usable: true,
      degraded: true,
      reasonCode: code,
      hint: capabilityHint(signal),
    };
    return degraded;
  }

  /**
   * reason code → 中文短句。UI 不直接印 MODEL_ID_UNRESOLVED 这类内部 code。
   */
  static reasonText(code: string): string {
    const c: string = code.trim();
    if (c.length === 0) { return ''; }
    if (c === 'MODEL_ID_UNRESOLVED') { return '模型 ID 未在已确认清单中'; }
    if (c === 'EMPTY_REQUEST') { return '未填写模型 ID'; }
    if (c === 'CAPABILITY_UNCONFIRMED') { return '能力未确认'; }
    if (c === 'CAPABILITY_PARTIAL') { return '字段已核实（默认值未证实）'; }
    if (c === 'MODEL_SPEC_INCOMPLETE') { return '模型规格不完整'; }
    if (c.startsWith('ALIAS_RESOLVED:')) { return '旧模型名，已自动映射'; }
    return '模型不可用';
  }

  /**
   * chip 来源标签: 内置清单 / 发现所得 / 手动输入。
   */
  static sourceLabel(source: string): string {
    if (source === 'catalog') { return '内置'; }
    if (source === 'discovery') { return '发现'; }
    if (source === 'user') { return '手动'; }
    return '';
  }
}
