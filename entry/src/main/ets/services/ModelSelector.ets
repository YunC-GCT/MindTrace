/**
 * ModelSelector.ets — 模型选择业务
 *
 * 路径: entry/src/main/ets/services/ModelSelector.ets
 * 职责: 模型状态读取 + 显示名格式化 (后续接入选择 UI)
 * 依赖: common (LlmConfig + model-resolver)
 *
 * 当前阶段: 仅格式化模型名供 Chip 显示, 不含选择交互
 * 后续扩展: 选择器弹窗 / 模型列表 / 切换回调
 *
 * 用法:
 *   import { ModelSelector } from '../services/ModelSelector';
 *   ModelSelector.currentLabel()  // → "DeepSeek-V4-Pro"
 */

import { LlmConfig, resolveModel } from 'common';
import type { ResolvedModel } from 'common';

export class ModelSelector {
  /**
   * 当前模型的显示标签 (供 UI 显示)
   * 读取 LlmConfig 的 vendor + model, 由 catalog/别名解析出 listing;
   * 清单里没有该 ID 时原样返回 ID, 绝不换成别的型号。
   */
  static currentLabel(): string {
    const config: LlmConfig = LlmConfig.getInstance();
    const vendorId: string = config.getVendorId().trim();
    const id: string = config.getModel().trim();
    const resolved: ResolvedModel = resolveModel(vendorId, id);
    if (resolved.listing !== null) {
      return resolved.listing.displayName;
    }
    return id;
  }

  /**
   * 当前模型的原始 ID (供后续选择器 UI 列表展示/匹配)
   */
  static currentRaw(): string {
    return LlmConfig.getInstance().getModel().trim();
  }
}
