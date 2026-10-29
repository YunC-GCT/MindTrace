/**
 * OnDeviceLlm.ets — 端侧生成式模型的接入点与可用性判定
 *
 * 路径: common/src/main/ets/llm/OnDeviceLlm.ets
 * 职责: 定义端侧推理的统一契约；v1 不内置端侧模型，可用性恒为不可用。
 * 依赖: 无（纯 ArkTS，不访问文件系统）
 *
 * v1 决策:
 *   v1 不内置端侧模型，文件检查留到接入 `.ms` 模型时再实现。
 *   因此这里不做磁盘探测，checkAvailability() 恒定返回不可用，由 ModelRouter 走降级；
 *   同时移除了对 @ohos.file.fs 的静态导入，避免启动期在 common HSP 内解析文件系统模块。
 *
 * 背景（2026-10-24 核实）:
 *   HarmonyOS API 26 未开放系统级生成式模型 API，SDK 中无 generateText / chatCompletion；
 *   唯一可用的端侧推理运行时是 @ohos.ai.mindSporeLite，需要自带 .ms 模型与配套 tokenizer。
 *   就位前一律视为不可用。
 */

export interface OnDeviceReply {
  text: string;
}

export interface OnDeviceAvailability {
  available: boolean;
  reason: string;
  modelPath: string;
}

/** 端侧模型约定的存放位置（沙箱 files 目录） */
export const ON_DEVICE_MODEL_DIR: string = 'models';
export const ON_DEVICE_MODEL_FILE: string = 'mindtrace-lite.ms';

export class OnDeviceLlm {
  private readonly modelPath: string;

  constructor(filesDir: string) {
    this.modelPath = filesDir + '/' + ON_DEVICE_MODEL_DIR + '/' + ON_DEVICE_MODEL_FILE;
  }

  /**
   * 端侧是否可用。v1 不内置端侧模型，不访问磁盘，恒为不可用；
   * 文件检查留到接入 `.ms` 模型时再实现。
   */
  checkAvailability(): OnDeviceAvailability {
    return {
      available: false,
      reason: 'on-device model is not provisioned in this build',
      modelPath: this.modelPath,
    };
  }

  /**
   * 端侧生成。当前阶段不实现推理循环：
   * 只有接入具体 .ms 模型（含 tokenizer 与采样策略）后才在这里落地，
   * 在那之前直接抛错，让上层明确走降级而不是拿到假结果。
   */
  async generate(prompt: string): Promise<OnDeviceReply> {
    const availability: OnDeviceAvailability = this.checkAvailability();
    if (!availability.available) {
      throw new Error('on-device model unavailable: ' + availability.reason);
    }
    throw new Error('on-device inference adapter not implemented for ' + availability.modelPath);
  }
}
