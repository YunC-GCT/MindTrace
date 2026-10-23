/**
 * LocalChatProvider.ets — 系统端侧问答模型（Data Augmentation Kit）适配层
 *
 * 路径: common/src/main/ets/llm/LocalChatProvider.ets
 * 职责: 封装 localChatModel.init() / chat()，把回调式结果收敛为一次性完整文本
 * 依赖: @kit.DataAugmentationKit (localChatModel), @kit.BasicServicesKit (AsyncCallback/BusinessError), ../utils/logger
 *
 * 数据流:
 *   init() -> localChatModel.init() -> initialized
 *   ask(content) -> questionId 自增 -> chat(isStream=false) -> 拼收到 isFinished=true 的帧 -> 完整文本
 *
 * 约束:
 *   - questionId 取值 [0, 65535]；同一进程内必须唯一，用静态计数器跨实例共享
 *   - isStream=false 仍按增量帧拼接，避免实现依赖「只回调一次」的假设
 *   - 错误信息统一带 BusinessError.code（1021900001..0005），便于 hilog 定位
 *
 * ArkTS 1.1 strict 适配:
 *   - catch 参数不标注类型，BusinessError 通过 as 断言读取 code
 *   - Promise executor / AsyncCallback 参数显式标注函数类型
 *   - 对象字面量先声明 localChatModel.QuestionInfo / Config 类型
 */
import { AsyncCallback, BusinessError } from '@kit.BasicServicesKit';
import { localChatModel } from '@kit.DataAugmentationKit';
import { Logger } from '../utils/logger';

const localChatLog: Logger = new Logger('LocalChatProvider');

/** questionId 合法上界为 65535，计数器按 65536 取模循环 */
const QUESTION_ID_MODULUS: number = 65536;

const describeFailure = (e: Object): string => {
  const error: Error = e as Error;
  const businessError: BusinessError = e as BusinessError;
  const code: string = businessError.code === undefined ? 'n/a' : businessError.code.toString();
  const message: string = error.message === undefined ? 'unknown error' : error.message;
  return 'code=' + code + ' message=' + message;
};

export class LocalChatProvider {
  private static nextQuestionId: number = 0;
  private initialized: boolean = false;

  /** 静态自增，保证同一进程内多个 provider 实例也不会撞 questionId */
  private static allocateQuestionId(): number {
    const current: number = LocalChatProvider.nextQuestionId;
    LocalChatProvider.nextQuestionId = (current + 1) % QUESTION_ID_MODULUS;
    return current;
  }

  /**
   * 初始化系统端侧问答模型。成功一次后 isReady() 恒为 true。
   * 失败不抛出，返回 false 并记录原因。
   */
  async init(): Promise<boolean> {
    if (this.initialized) {
      return true;
    }
    const startedAt: number = Date.now();
    try {
      const ok: boolean = await localChatModel.init();
      this.initialized = ok;
      const elapsed: number = Date.now() - startedAt;
      if (ok) {
        localChatLog.info('init ok elapsedMs=' + elapsed.toString());
      } else {
        localChatLog.error('init returned false elapsedMs=' + elapsed.toString());
      }
      return ok;
    } catch (e) {
      this.initialized = false;
      const elapsed: number = Date.now() - startedAt;
      localChatLog.error('init failed elapsedMs=' + elapsed.toString() + ' ' + describeFailure(e));
      return false;
    }
  }

  isReady(): boolean {
    return this.initialized;
  }

  /**
   * 非流式提问，等待 isFinished=true 的帧后返回完整 content。
   * 未初始化时直接抛错，由 ModelRouter 决定回退或明确报错。
   */
  async ask(content: string): Promise<string> {
    if (!this.initialized) {
      throw new Error('local chat model unavailable');
    }

    const questionId: number = LocalChatProvider.allocateQuestionId();
    const info: localChatModel.QuestionInfo = {
      questionId: questionId,
      content: content,
    };
    const config: localChatModel.Config = {
      isStream: false,
    };
    const startedAt: number = Date.now();

    return await new Promise<string>((resolve: (value: string) => void,
      reject: (reason: Error) => void): void => {
      let answerText: string = '';
      let settled: boolean = false;

      const onAnswer: AsyncCallback<localChatModel.Answer> =
        (err: BusinessError, answer: localChatModel.Answer): void => {
          if (settled) {
            return;
          }
          if (err) {
            settled = true;
            const elapsed: number = Date.now() - startedAt;
            const failure: string = describeFailure(err);
            localChatLog.error('ask failed questionId=' + questionId.toString()
              + ' elapsedMs=' + elapsed.toString() + ' ' + failure);
            reject(new Error('local chat request failed (' + failure + ')'));
            return;
          }
          if (answer === undefined || answer === null) {
            return;
          }
          if (answer.questionId !== questionId) {
            localChatLog.warn('ignored answer questionId=' + answer.questionId.toString()
              + ' expected=' + questionId.toString());
            return;
          }
          if (answer.content !== undefined && answer.content.length > 0) {
            answerText += answer.content;
          }
          if (answer.isFinished) {
            settled = true;
            const elapsed: number = Date.now() - startedAt;
            localChatLog.info('ask ok questionId=' + questionId.toString()
              + ' elapsedMs=' + elapsed.toString() + ' chars=' + answerText.length.toString());
            resolve(answerText);
          }
        };

      localChatModel.chat(info, config, onAnswer).catch((e: BusinessError): void => {
        if (settled) {
          return;
        }
        settled = true;
        const elapsed: number = Date.now() - startedAt;
        const failure: string = describeFailure(e);
        localChatLog.error('ask rejected questionId=' + questionId.toString()
          + ' elapsedMs=' + elapsed.toString() + ' ' + failure);
        reject(new Error('local chat request failed (' + failure + ')'));
      });
    });
  }
}
