/**
 * ModelRouter.ets — 模型路由：端侧优先，用户配置的模型为显式例外，回退必须标注
 *
 * 路径: entry/src/main/ets/services/ModelRouter.ets
 * 职责: 按既定硬规则决定这一轮由谁回答
 *       1) 端侧模型就绪 -> 端侧
 *       2) 端侧不可用且用户配置了模型 -> 云端，并标记「已降级」
 *       3) 两者都不可用 -> 抛出明确错误，不返回假内容
 * 依赖: OnDeviceLlm、ReplyService、IntentClassifier
 */
import { OnDeviceAvailability, OnDeviceLlm } from 'common';
import { ReplyContext } from './IntentClassifier';
import { ReplyService } from './ReplyService';

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

    if (availability.available) {
      try {
        const reply = await onDevice.generate(context.userContent);
        return { text: reply.text, source: 'on_device', degraded: false, reason: 'on-device model' };
      } catch (e) {
        // 端侧就绪但推理失败，同样降级，并把原因带回上层
        const text: string = await this.replyService.complete(context);
        return {
          text: text,
          source: 'remote',
          degraded: true,
          reason: 'on-device inference failed: ' + (e as Error).message,
        };
      }
    }

    // 端侧未就绪：走用户配置的模型，必须在回答里标注已降级
    const text: string = await this.replyService.complete(context);
    return {
      text: text,
      source: 'remote',
      degraded: true,
      reason: 'on-device unavailable: ' + availability.reason,
    };
  }
}
