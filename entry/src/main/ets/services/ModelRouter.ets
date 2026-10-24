/**
 * ModelRouter.ets — 模型路由：端侧优先，用户配置的模型是显式例外，回退必须标注
 *
 * 路径: entry/src/main/ets/services/ModelRouter.ets
 * 职责: 按硬规则决定这一轮由谁回答
 *       1) 系统端侧问答模型已就绪 -> 端侧，不降级
 *       2) 端侧未就绪、用户配置了模型 -> 用配置的模型（这是显式例外，不算降级）
 *       3) 端侧推理失败、且用户配置了模型 -> 云端 + 标记「已降级」
 *       4) 端侧未就绪且没有配置 -> 明确报错，不静默走别的
 * 依赖: LlmConfig、LocalChatProvider、ReplyService
 */
import { LlmConfig } from 'common';
import { LocalChatProvider } from './LocalChatProvider';
import type { ReplyContext } from './IntentClassifier';
import type { ReplyService } from './ReplyService';

export interface RoutedReply {
  text: string;
  source: 'on_device' | 'remote' | 'none';
  degraded: boolean;
  reason: string;
}

export class ModelRouter {
  /** 保留构造签名兼容旧调用；端侧可用性已改由 LocalChatProvider.isReady() 判定 */
  private readonly filesDir: string;
  private readonly replyService: ReplyService;
  private readonly localChat?: LocalChatProvider;

  constructor(filesDir: string, replyService: ReplyService, localChat?: LocalChatProvider) {
    this.filesDir = filesDir;
    this.replyService = replyService;
    this.localChat = localChat;
  }

  async answer(context: ReplyContext): Promise<RoutedReply> {
    const configured: boolean = await LlmConfig.getInstance().isConfigured();
    const localChat: LocalChatProvider | undefined = this.localChat;

    // 1) 端侧就绪：优先端侧
    if (localChat !== undefined && localChat.isReady()) {
      try {
        const text: string = await localChat.ask(context.userContent);
        return { text: text, source: 'on_device', degraded: false, reason: 'local chat model' };
      } catch (e) {
        const detail: string = (e as Error).message;
        if (configured) {
          const text: string = await this.replyService.complete(context);
          return {
            text: text,
            source: 'remote',
            degraded: true,
            reason: 'local chat failed: ' + detail,
          };
        }
        throw new Error('端侧模型推理失败（' + detail + '），且没有配置云端模型；请到设置里配置模型');
      }
    }

    // 2) 显式例外：用户自己配了模型，就用它，不属于降级
    if (configured) {
      const text: string = await this.replyService.complete(context);
      return { text: text, source: 'remote', degraded: false, reason: 'user-configured model' };
    }

    // 3) 都没配：明确报错，不偷偷调云端
    throw new Error('端侧模型未就绪（local chat model unavailable），且没有配置云端模型；请到设置里配置模型');
  }
}
