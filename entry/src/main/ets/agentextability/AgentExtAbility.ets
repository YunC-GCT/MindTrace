/**
 * AgentExtAbility.ets - 端 A2A Agent 扩展入口（API 26 / AgentFrameworkKit）
 *
 * 路径: entry/src/main/ets/agentextability/AgentExtAbility.ets
 * 职责: 用 @kit.AgentFrameworkKit 的 createA2AServer 承载端A2A 协议：
 *       小艺消息 -> Server.onMessage -> onData 回调 -> addArtifact(文本)
 *       -> updateStatus(COMPLETED)
 * 依赖: @kit.AbilityKit、@kit.AgentFrameworkKit、@kit.PerformanceAnalysisKit、
 *       common.LlmConfig、./services/ReplyService、./services/IntentClassifier
 *
 * 进程约束（重要）: 扩展跑在独立进程 <bundle>:agent，模块加载失败表现为 exit 254 /
 *   Reason:SyntaxError 且 onCreate 一行日志都打不出来（错误发生在 import 图求值阶段）。
 *   因此本文件禁止 import ModelRouter / OnDeviceLlm（及其依赖链）；端侧路由只在 UI 进程
 *   （ConversationWorkflowPorts）使用。
 *
 * 数据流:
 *   onData(proxy, data) -> server.onMessage(data, sender=proxy.sendData)
 *     -> onDataCallback(method, ctx) -> getUserInput() -> 组装 Part[]
 *     -> isConfigured()=false -> 直接回「端侧模型未就绪」文案（不调模型）
 *     -> isConfigured()=true  -> new ReplyService().complete -> addArtifact(taskId, 文本)
 *     -> server.updateStatus(taskId, { state: COMPLETED })
 */
import { AgentExtensionAbility, common, Want } from '@kit.AbilityKit';
import {
  createA2AServer,
  Part,
  RequestContext,
  Server,
  TaskArtifactParam,
  TaskState,
  TaskStatus,
} from '@kit.AgentFrameworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LlmConfig } from 'common';
import { ReplyContext } from '../services/IntentClassifier';
import { ReplyService } from '../services/ReplyService';
import { IntentClassifier } from '../services/IntentClassifier';

const TAG: string = 'MindTraceA2A';
/** 回复链路兜底超时：判配置 + 调模型整段限时 */
const REPLY_TIMEOUT_MS: number = 60000;

/** 端侧模型未就绪且未配置云端模型时的如实回复：不调模型，也不假装回答 */
const MODEL_NOT_READY: string =
  '端侧模型未就绪（model file not found），请先在 MindTrace 设置里配置模型';

/** 扩展进程内的模型配置初始化（只做一次），handleRequest 前必须等它 */
let configReady: Promise<void> | null = null;
const DOMAIN: number = 0xA2A0;

// 与本应用聊天一致的回复链路：LlmGuard → LlmClient → 远程/用户配置模型
interface CardPayload {
  title: string;
  description: string;
  query: string;
  action: string;
}

interface UiCardBody {
  bundleName: string;
  moduleName: string;
  abilityName: string;
  payload: CardPayload;
}

interface UiCardDirective {
  uiExtensionCard: UiCardBody;
}

export default class AgentExtAbility extends AgentExtensionAbility {
  private server: Server | null = null;

  onCreate(want: Want): void {
    hilog.info(DOMAIN, TAG, 'onCreate: 扩展被拉起，初始化 A2A Server');
    // 扩展进程独立于 UI 进程，模型配置必须在这里重新初始化，否则会用默认 endpoint
    configReady = LlmConfig.getInstance().init(this.context)
      .then((): void => {
        const cfg: LlmConfig = LlmConfig.getInstance();
        const keys: Record<string, string> = cfg.getAllVendorApiKeys();
        let keyCount: number = 0;
        for (const k of Object.keys(keys)) {
          if (keys[k].length > 0) {
            keyCount += 1;
          }
        }
        hilog.info(DOMAIN, TAG, 'LlmConfig 就绪 vendor=%{public}s model=%{public}s keys=%{public}d',
          cfg.getVendorId(), cfg.getModel(), keyCount);
      })
      .catch((e: Error): void => {
        hilog.error(DOMAIN, TAG, 'LlmConfig 初始化失败: %{public}s', e.message);
      });
    try {
      this.server = createA2AServer(this.context.agentCard, (method: string, ctx: RequestContext): void => {
        this.handleRequest(method, ctx);
      }, want);
      this.server.start();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'createA2AServer 失败: %{public}s', (error as Error).message);
    }
  }

  onData(proxy: common.AgentHostProxy, data: string): void {
    hilog.info(DOMAIN, TAG, 'onData 收到 %{public}d 字节', data.length);
    if (this.server === null) {
      hilog.error(DOMAIN, TAG, 'server 未初始化，忽略本次请求');
      return;
    }
    try {
      this.server.onMessage(data, (payload: string): void => {
        hilog.info(DOMAIN, TAG, 'sendData %{public}d 字节', payload.length);
        proxy.sendData(payload);
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'onMessage 失败: %{public}s', (error as Error).message);
    }
  }

  onDestroy(): void {
    if (this.server !== null) {
      this.server.stop();
      this.server = null;
    }
    hilog.info(DOMAIN, TAG, 'onDestroy');
  }

  private handleRequest(method: string, ctx: RequestContext): void {
    const query: string = ctx.getUserInput();
    const taskId: string | undefined = ctx.getTaskId();
    hilog.info(DOMAIN, TAG, 'method=%{public}s taskId=%{public}s query=%{public}s',
      method, taskId ?? 'none', query);

    if (taskId === undefined) {
      hilog.warn(DOMAIN, TAG, 'taskId 为空，跳过回复');
      return;
    }
    if (query.length === 0) {
      this.sendAnswer(taskId, '没收到问题内容，再说一次？');
      return;
    }

    // 真模型回答：与小艺对话同一条链路（LlmGuard → LlmClient）
    const replyContext: ReplyContext = {
      memoryContext: '',
      learnerProfileContext: '',
      userContent: query,
      evidenceContext: '',
    };
    // 扩展进程里 preferences 可能迟迟不返回，最多等 4 秒，避免整个回复挂死
    const fallback: Promise<void> = new Promise<void>((resolve: (v: void) => void): void => {
      setTimeout((): void => {
        resolve();
      }, 4000);
    });
    const ready: Promise<void> = configReady !== null
      ? Promise.race([configReady, fallback])
      : fallback;
    ready.then((): Promise<string> => {
      // 先判配置：未就绪时不调模型，如实回一句，而不是把 60 秒等成超时文案
      return this.answerWithinTimeout(replyContext);
    })
      .then((answer: string): void => {
        this.sendAnswer(taskId, answer);
      })
      .catch((e: Error): void => {
        hilog.error(DOMAIN, TAG, 'LLM 调用失败: %{public}s', e.message);
        this.sendAnswer(taskId, '模型暂时不可用：' + e.message);
      });
  }

  /** 60 秒兜底：把「判配置 + 调模型」整段限时，避免 await 挂住后小艺一直空转 */
  private answerWithinTimeout(context: ReplyContext): Promise<string> {
    const timeout: Promise<string> = new Promise<string>((resolve: (v: string) => void): void => {
      setTimeout((): void => {
        hilog.warn(DOMAIN, TAG, 'LLM 超时 %{public}d ms', REPLY_TIMEOUT_MS);
        resolve('模型响应超时，稍后再试。');
      }, REPLY_TIMEOUT_MS);
    });
    return Promise.race([this.answerIfConfigured(context), timeout]);
  }

  /**
   * 配置就绪 -> 走 ReplyService（与 UI 聊天同一条链路，明确不经过 ModelRouter）；
   * 未就绪 -> 不调模型，直接返回未就绪文案。
   */
  private async answerIfConfigured(context: ReplyContext): Promise<string> {
    const configured: boolean = await LlmConfig.getInstance().isConfigured();
    if (!configured) {
      hilog.info(DOMAIN, TAG, 'LlmConfig 未配置（端侧模型未就绪），跳过模型调用');
      return MODEL_NOT_READY;
    }
    const start: number = Date.now();
    hilog.info(DOMAIN, TAG, 'LLM 调用开始');
    const raw: string = await new ReplyService(new IntentClassifier()).complete(context);
    const elapsed: number = Date.now() - start;
    const text: string = raw.length > 0 ? raw : '模型没有返回内容，换个问法试试。';
    hilog.info(DOMAIN, TAG, 'LLM 返回 %{public}d 字，耗时 %{public}d ms', text.length, elapsed);
    return text;
  }

  private sendAnswer(taskId: string, text: string): void {
    const textPart: Part = { text: text, mediaType: 'text/plain' };
    const artifact: TaskArtifactParam = { parts: [textPart], lastChunk: true };
    try {
      this.server?.addArtifact(taskId, artifact);
      const status: TaskStatus = { state: TaskState.COMPLETED };
      this.server?.updateStatus(taskId, status);
      hilog.info(DOMAIN, TAG, 'artifact sent, task completed');
    } catch (error) {
      hilog.error(DOMAIN, TAG, '发送 artifact 失败: %{public}s', (error as Error).message);
    }
  }
}
