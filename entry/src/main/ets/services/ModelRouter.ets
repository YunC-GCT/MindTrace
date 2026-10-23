/**
 * ModelRouter.ets — 模型路由：端侧优先，用户配置的模型是显式例外，回退必须标注
 *
 * 路径: entry/src/main/ets/services/ModelRouter.ets
 * 职责: 按硬规则决定这一轮由谁回答
 *       1) 用户配置了模型 -> 用配置的模型（这是显式例外，不算降级）
 *       2) 未配置 -> 端侧；端侧不可用则明确报错，不静默走别的
 *       3) 端侧就绪但推理失败，且用户配置了模型 -> 云端 + 标记「已降级」
 * 依赖: OnDeviceLlm、ReplyService、LlmConfig
 */
import { LlmConfig, OnDeviceLlm } from 'common';
import type { OnDeviceAvailability } from 'common';
import type { ReplyContext } from './IntentClassifier';
import type { ReplyService } from './ReplyService';

export type ModelSource = 'on_device' | 'remote' | 'none';

export interface RoutedReply {
  text: string;
  source: ModelSource;
  degraded: boolean;
  reason: string;
}

export class ModelRouter {
  private readonly filesDir: string;
  private readonly replyService: ReplyService;

  constructor(filesDir: string, replyService: ReplyService) {
    this.filesDir = filesDir;
    this.replyService = replyService;
  }

  async answer(context: ReplyContext): Promise<RoutedReply> {
    const onDevice: OnDeviceLlm = new OnDeviceLlm(this.filesDir);
    const availability: OnDeviceAvailability = onDevice.checkAvailability();
    const configured: boolean = await LlmConfig.getInstance().isConfigured();

    // 1) 显式例外：用户自己配了模型，就用它，不属于降级
    if (configured) {
      if (availability.available) {
        try {
          const reply = await onDevice.generate(context.userContent);
          return { text: reply.text, source: 'on_device', degraded: false, reason: 'on-device model' };
        } catch (e) {
          const text: string = await this.replyService.complete(context);
          return {
            text: text,
            source: 'remote',
            degraded: true,
            reason: 'on-device inference failed: ' + (e as Error).message,
          };
        }
      }
      const text: string = await this.replyService.complete(context);
      return { text: text, source: 'remote', degraded: false, reason: 'user-configured model' };
    }

    // 2) 未配置：只应走端侧；端侧不可用就说清楚，不偷偷调云端
    if (availability.available) {
      const reply = await onDevice.generate(context.userContent);
      return { text: reply.text, source: 'on_device', degraded: false, reason: 'on-device model' };
    }
    throw new Error('端侧模型未就绪（' + availability.reason + '），且没有配置云端模型；请到设置里配置模型');
  }
}
