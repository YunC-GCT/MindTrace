/**
 * OnDeviceLlm.ets — 端侧生成式模型的接入点与可用性判定
 *
 * 路径: common/src/main/ets/llm/OnDeviceLlm.ets
 * 职责: 定义端侧推理的统一契约；当前实现为「未就绪」占位，
 *       只有沙箱内存在可用的 MindSpore Lite 模型文件时才视为可用。
 * 依赖: @ohos.file.fs (可用性探测)
 *
 * 背景（2026-10-24 核实）:
 *   HarmonyOS API 26 未开放系统级生成式模型 API，SDK 中无 generateText / chatCompletion；
 *   唯一可用的端侧推理运行时是 @ohos.ai.mindSporeLite，需要自带 .ms 模型与配套 tokenizer。
 *   因此这里只判断「模型文件是否就位」，就位前一律视为不可用，由 ModelRouter 走降级。
 */
import fs from '@ohos.file.fs';

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

  /** 端侧是否可用：只认「模型文件存在」这一个事实，不做虚假承诺 */
  checkAvailability(): OnDeviceAvailability {
    try {
      const exists: boolean = fs.accessSync(this.modelPath);
      if (exists) {
        return { available: true, reason: 'model present', modelPath: this.modelPath };
      }
      return { available: false, reason: 'model file not found', modelPath: this.modelPath };
    } catch (e) {
      return { available: false, reason: 'access failed: ' + (e as Error).message, modelPath: this.modelPath };
    }
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
