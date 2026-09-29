/**
 * ModelSelector.ets — 模型选择业务
 *
 * 路径: entry/src/main/ets/services/ModelSelector.ets
 * 职责: 模型状态读取 + 显示名格式化 (后续接入选择 UI)
 * 依赖: common (LlmConfig)
 *
 * 当前阶段: 仅格式化模型名供 Chip 显示, 不含选择交互
 * 后续扩展: 选择器弹窗 / 模型列表 / 切换回调
 *
 * 用法:
 *   import { ModelSelector } from '../services/ModelSelector';
 *   ModelSelector.currentLabel()  // → "DeepSeek-V4-Pro"
 */

import { LlmConfig } from 'common';

/**
 * 模型显示名映射表
 * 原始 ID (LlmConfig 内部) → 用户可见标签 (UI Chip 显示)
 */
const LABEL_MAP: Record<string, string> = {
  'deepseek-v4-pro': 'DeepSeek-V4-Pro',
};

/**
 * 默认显示名 (未匹配或未配置时)
 */
const DEFAULT_LABEL: string = 'DeepSeek-V4-Pro';

export class ModelSelector {
  /**
   * 当前模型的显示标签 (供 UI 显示)
   * 读取 LlmConfig, 经 LABEL_MAP 映射, 失败回退默认
   */
  static currentLabel(): string {
    const raw: string = LlmConfig.getInstance().getModel().trim();
    const mapped: string | undefined = LABEL_MAP[raw];
    if (mapped !== undefined) {
      return mapped;
    }
    return raw.length > 0 ? raw : DEFAULT_LABEL;
  }

  /**
   * 当前模型的原始 ID (供后续选择器 UI 列表展示/匹配)
   */
  static currentRaw(): string {
    return LlmConfig.getInstance().getModel().trim();
  }
}
