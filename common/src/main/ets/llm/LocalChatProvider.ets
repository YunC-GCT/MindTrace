/**
 * LocalChatProvider.ets — 系统端侧问答模型（Data Augmentation Kit）适配层
 *
 * 路径: common/src/main/ets/llm/LocalChatProvider.ets
 * 职责: 封装 localChatModel.init() / chat()，把回调式结果收敛为完整文本（非流式）或增量回调（流式）
 * 依赖: @kit.DataAugmentationKit (localChatModel), @kit.BasicServicesKit (AsyncCallback/BusinessError), ../utils/logger
 *
 * 数据流:
 *   init() -> localChatModel.init() -> initialized
 *   ask(content) -> questionId 自增 -> chat(isStream=false) -> 拼收到 isFinished=true 的帧 -> 完整文本
 *   askStream(content, onDelta) -> questionId 自增 -> chat(isStream=true) -> 每个非空增量回调 onDelta -> 完整文本
 *
 * 约束:
 *   - questionId 取值 [0, 65535]；同一进程内必须唯一，用静态计数器跨实例共享
 *   - isStream=false 仍按增量帧拼接，避免实现依赖「只回调一次」的假设
 *   - 官方 d.ts 对 isFinished=false 明说返回增量；isFinished=true 未说明是末段增量还是累计全文，
 *     流式实现主路径按增量拼接，并用 extractDelta 兼容「某些机型返回累计全文」的情况
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

  /**
   * 流式提问：isStream=true，每个非空增量通过 onDelta(chunk, finished) 回调，返回完整文本。
   *
   * 增量 vs 累计：本机 SDK 的 @hms.data.localChatModel.d.ts 在 isFinished=false 的注释里
   * 明说 "the current callback returns incremental content"（增量）；但它没有说明
   * isFinished=true 那一帧的 content 是最后一段增量还是累计全文。因此主路径按增量拼接，
   * 同时兼容累计机型——若新 content 以已累计文本开头，取后缀差集再追加，
   * 否则把新 content 整体当作增量。该判断是启发式的：只有当某帧增量恰好
   * 以已累计文本开头时才会被误判为累计，正常续写从新 token 开始，概率极低。
   *
   * 未初始化直接抛错；推理失败通过 Promise reject 上抛，由调用方（工作流）
   * 统一决定 fallback 与标注，provider 自己不兜底。
   */
  async askStream(
    content: string,
    onDelta: (chunk: string, finished: boolean) => void,
  ): Promise<string> {
    if (!this.initialized) {
      throw new Error('local chat model unavailable');
    }

    const questionId: number = LocalChatProvider.allocateQuestionId();
    const info: localChatModel.QuestionInfo = {
      questionId: questionId,
      content: content,
    };
    const config: localChatModel.Config = {
      isStream: true,
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
            localChatLog.error('askStream failed questionId=' + questionId.toString()
              + ' elapsedMs=' + elapsed.toString() + ' ' + failure);
            reject(new Error('local chat stream failed (' + failure + ')'));
            return;
          }
          if (answer === undefined || answer === null) {
            return;
          }
          if (answer.questionId !== questionId) {
            localChatLog.warn('ignored stream answer questionId=' + answer.questionId.toString()
              + ' expected=' + questionId.toString());
            return;
          }
          const incoming: string = answer.content === undefined || answer.content === null
            ? ''
            : answer.content;
          if (incoming.length > 0) {
            const delta: string = LocalChatProvider.extractDelta(answerText, incoming);
            if (delta.length > 0) {
              answerText += delta;
              onDelta(delta, answer.isFinished);
            }
          }
          if (answer.isFinished) {
            settled = true;
            const elapsed: number = Date.now() - startedAt;
            localChatLog.info('askStream ok questionId=' + questionId.toString()
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
        localChatLog.error('askStream rejected questionId=' + questionId.toString()
          + ' elapsedMs=' + elapsed.toString() + ' ' + failure);
        reject(new Error('local chat stream failed (' + failure + ')'));
      });
    });
  }

  /**
   * 从一帧 content 中提取真正的增量。
   * - 累计机型：incoming 以 accumulated 开头 -> 返回后缀差集（可能为空串）
   * - 增量机型：incoming 与 accumulated 无前缀关系 -> 整体作为新增量
   */
  private static extractDelta(accumulated: string, incoming: string): string {
    if (accumulated.length === 0) {
      return incoming;
    }
    if (incoming === accumulated) {
      return '';
    }
    if (incoming.length > accumulated.length && incoming.startsWith(accumulated)) {
      return incoming.substring(accumulated.length);
    }
    return incoming;
  }
}
