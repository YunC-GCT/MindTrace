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
 */

import { LlmConfig, getProviderCatalog, resolveModel } from 'common';
import type { ModelListing, ProviderCatalog, ResolvedModel } from 'common';

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
   * 可用性判定。source 来自 ModelListing.source('catalog' | 'discovery' | 'user')。
   * 不在这里编造上下文/模态/输出上限 — 只决定"能不能选、要不要提示"。
   */
  static availabilityOf(vendorId: string, modelId: string, source: string): ModelAvailability {
    const provider: string = vendorId.trim();
    const requested: string = modelId.trim();
    const resolved: ResolvedModel = resolveModel(provider, requested);
    if (resolved.usable) {
      const ok: ModelAvailability = {
        usable: true,
        degraded: resolved.degraded,
        reasonCode: resolved.degraded ? 'CAPABILITY_UNCONFIRMED' : resolved.reason,
        hint: resolved.degraded ? ModelSelector.reasonText('CAPABILITY_UNCONFIRMED') : '',
      };
      return ok;
    }

    // discovery 返回的 ID 已被官方 /models 证实存在, 只是能力字段没给全 → 降级可用。
    if (source === 'discovery') {
      return ModelSelector.unconfirmed();
    }

    // 没有权威内置清单可对照的 vendor(通义/GLM/Kimi/豆包/自定义): ID 无从证伪,
    // 按"能力未确认"处理, 不拦保存; 有清单的 vendor 才把未命中当不可用。
    const catalog: ProviderCatalog | null = getProviderCatalog(provider);
    const hasAuthoritativeCatalog: boolean = catalog !== null && catalog.models.length > 0;
    if (!hasAuthoritativeCatalog) {
      return ModelSelector.unconfirmed();
    }

    const blocked: ModelAvailability = {
      usable: false,
      degraded: resolved.degraded,
      reasonCode: resolved.reason,
      hint: ModelSelector.reasonText(resolved.reason),
    };
    return blocked;
  }

  private static unconfirmed(): ModelAvailability {
    const degraded: ModelAvailability = {
      usable: true,
      degraded: true,
      reasonCode: 'CAPABILITY_UNCONFIRMED',
      hint: ModelSelector.reasonText('CAPABILITY_UNCONFIRMED'),
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
