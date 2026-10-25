/**
 * AgentExtAbility.ets - 端 A2A Agent 扩展入口（手写 JSON-RPC 2.0 单帧快照）
 *
 * 路径: entry/src/main/ets/agentextability/AgentExtAbility.ets
 * 职责: 接收小艺的 SendStreamingMessage，自己手写 JSON-RPC 请求解析与应答
 *       -> ReplyService 取回答 -> 经 hostProxy.sendData 回一条 result.task 快照。
 * 为什么手写: SDK 的自动应答封装会先发一帧 TASK_STATE_SUBMITTED（带 history），
 *       再发 artifactUpdate；小艺在这种序列下只渲染开头一两个词。历史实测「单帧 result.task
 *       一次给全 artifacts + COMPLETED」能完整渲染长文本，故回到手写。
 * 依赖: @kit.AbilityKit、@kit.PerformanceAnalysisKit、common.LlmConfig、
 *       ./services/ReplyService、./services/IntentClassifier、./services/CaptureReceipt、./TaskSnapshot
 *
 * 进程约束（重要）: 扩展跑在独立进程 <bundle>:agent，模块加载失败表现为 exit 254 /
 *   Reason:SyntaxError 且 onCreate 一行日志都打不出来（错误发生在 import 图求值阶段）。
 *   因此本文件禁止 import ModelRouter / OnDeviceLlm（及其依赖链）；端侧路由只在 UI 进程
 *   （ConversationWorkflowPorts）使用。
 *
 * 数据流:
 *   onData(proxy, data) -> JSON.parse 取 id / params.message.parts[] 第一段 string text
 *     -> 解析失败：回一条错误快照（不崩）
 *     -> query 为空：回「没收到问题内容」
 *     -> 回执意图命中：读 last-capture.json -> formatReceipt -> sendAnswer（不等配置、不调模型）
 *     -> 异步：等配置（≤4s）-> isConfigured -> ReplyService.complete（≤60s）
 *     -> sendAnswer(taskId, text)：buildTaskSnapshot 拼单帧 task 快照，artifacts 内是完整文本
 */
import { AgentExtensionAbility, common, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LlmConfig } from 'common';
import { IntentClassifier, ReplyContext } from '../services/IntentClassifier';
import { ReplyService } from '../services/ReplyService';
import {
  CaptureReceipt,
  CaptureReceiptStore,
  formatReceipt,
  matchesReceiptIntent,
} from '../services/CaptureReceipt';
import { buildTaskSnapshot } from './TaskSnapshot';

const TAG: string = 'MindTraceA2A';
/** 回复链路兜底超时：判配置 + 调模型整段限时 */
const REPLY_TIMEOUT_MS: number = 60000;

/** 端侧模型未就绪且未配置云端模型时的如实回复：不调模型，也不假装回答 */
const MODEL_NOT_READY: string =
  '端侧模型未就绪（model file not found），请先在 MindTrace 设置里配置模型';

/** 请求解析失败时的错误快照文案：宁可回一句错，也不要让扩展崩掉 */
const PARSE_ERROR: string = '请求解析失败，请重试。';

/** 扩展进程内的模型配置初始化（只做一次），handleQuery 前必须等它 */
let configReady: Promise<void> | null = null;
const DOMAIN: number = 0xA2A0;

// 小艺发来的 JSON-RPC 请求（proto-JSON）：parts 只有 mediaType + text，没有 kind/type
interface A2ATextSegment {
  mediaType?: string;
  text?: string;
}

interface A2AMessage {
  parts?: A2ATextSegment[];
}

interface A2AParams {
  message?: A2AMessage;
  /** 请求若带 task id，优先用它回填快照，保证 artifactId 稳定 */
  taskId?: string;
}

interface A2ARequest {
  id?: string | number;
  params?: A2AParams;
}

export default class AgentExtAbility extends AgentExtensionAbility {
  /** onData 收到的宿主代理，最终 task 快照直接由它发出 */
  private hostProxy: common.AgentHostProxy | null = null;
  /** 当前请求的 jsonrpc id：回复快照必须回填同一个 id，否则小艺不认这一帧 */
  private lastRequestId: string = '';

  onCreate(want: Want): void {
    const abilityName: string = want.abilityName ?? 'unknown';
    hilog.info(DOMAIN, TAG, 'onCreate: 扩展被拉起 ability=%{public}s（手写单帧快照模式）', abilityName);
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
  }

  onData(proxy: common.AgentHostProxy, data: string): void {
    hilog.info(DOMAIN, TAG, 'onData 收到 %{public}d 字节', data.length);
    this.hostProxy = proxy;

    // 解析失败（JSON 非法 / 顶层不是对象）统一回错误快照，绝不让异常冒出去
    const request: A2ARequest | null = this.parseRequest(data);
    if (request === null) {
      this.lastRequestId = '';
      this.sendAnswer('', PARSE_ERROR);
      return;
    }

    this.lastRequestId = this.readRequestId(request.id);
    const query: string = this.readQuery(request);
    const taskId: string = this.readTaskId(request);
    hilog.info(DOMAIN, TAG, 'id=%{public}s taskId=%{public}s query=%{public}s',
      this.lastRequestId, taskId.length > 0 ? taskId : 'none', query);

    if (query.length === 0) {
      this.sendAnswer(taskId, '没收到问题内容，再说一次？');
      return;
    }
    // onData 必须立刻返回：模型链路异步跑，结果回来再自己发快照
    this.handleQuery(taskId, query);
  }

  /** 手写解析：JSON.parse 失败或结果为 null 都返回 null，由 onData 回错误快照 */
  private parseRequest(data: string): A2ARequest | null {
    try {
      return JSON.parse(data) as A2ARequest;
    } catch (e) {
      hilog.error(DOMAIN, TAG, '请求 JSON 解析失败: %{public}s', (e as Error).message);
      return null;
    }
  }

  onDestroy(): void {
    this.hostProxy = null;
    hilog.info(DOMAIN, TAG, 'onDestroy');
  }

  /** jsonrpc id 可能是字符串或数字，统一转成字符串供回填 */
  private readRequestId(id: string | number | undefined): string {
    if (typeof id === 'string') {
      return id as string;
    }
    if (typeof id === 'number') {
      return (id as number).toString();
    }
    return '';
  }

  /** 小艺的 parts 只有 mediaType + text：取第一个 text 为 string 的 part */
  private readQuery(request: A2ARequest): string {
    const params: A2AParams | undefined = request.params;
    if (params === undefined) {
      return '';
    }
    const message: A2AMessage | undefined = params.message;
    if (message === undefined) {
      return '';
    }
    const parts: A2ATextSegment[] | undefined = message.parts;
    if (parts === undefined) {
      return '';
    }
    for (const part of parts) {
      const text: string | undefined = part.text;
      if (text !== undefined && typeof text === 'string') {
        return text as string;
      }
    }
    return '';
  }

  /** 请求里带 task id 就用它（保证 artifactId 稳定），没带则由 sendAnswer 生成 */
  private readTaskId(request: A2ARequest): string {
    const params: A2AParams | undefined = request.params;
    if (params === undefined) {
      return '';
    }
    const tid: string | undefined = params.taskId;
    if (tid !== undefined && tid.length > 0) {
      return tid;
    }
    return '';
  }

  /** 异步跑模型：先等配置（最多 4 秒），再整段限时 60 秒 */
  private async handleQuery(taskId: string, query: string): Promise<void> {
    const replyContext: ReplyContext = {
      memoryContext: '',
      learnerProfileContext: '',
      userContent: query,
      evidenceContext: '',
    };
    // 回执意图本地判定：命中就读落盘事实，不等待 configReady、不调 ReplyService、不判 LlmConfig
    if (matchesReceiptIntent(query)) {
      const receipt: CaptureReceipt | null = await CaptureReceiptStore.read(this.context);
      hilog.info(DOMAIN, TAG,
        '[Receipt] hit=true receipt=%{public}s done=%{public}d failed=%{public}d total=%{public}d',
        receipt !== null ? 'true' : 'false',
        receipt !== null ? receipt.done : 0,
        receipt !== null ? receipt.failed : 0,
        receipt !== null ? receipt.total : 0);
      this.sendAnswer(taskId, formatReceipt(receipt, Date.now()));
      return;
    }
    // 扩展进程里 preferences 可能迟迟不返回，最多等 4 秒，避免整个回复挂死
    const fallback: Promise<void> = new Promise<void>((resolve: (v: void) => void): void => {
      setTimeout((): void => {
        hilog.warn(DOMAIN, TAG, 'LlmConfig 等待超时 4000 ms，按当前配置继续');
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

  /**
   * 单帧 result.task 快照：一次给全 artifacts + TASK_STATE_COMPLETED。
   * 不拆 statusUpdate / artifactUpdate —— 小艺对增量帧只渲染开头几个词。
   * 报文拼装由 TaskSnapshot.buildTaskSnapshot（纯函数）负责，这里只选 taskId 并发送。
   */
  private sendAnswer(taskId: string, text: string): void {
    const finalTaskId: string = taskId.length > 0 ? taskId : 'task-' + Date.now().toString();
    const payload: string = buildTaskSnapshot(this.lastRequestId, finalTaskId, text);
    if (this.hostProxy === null) {
      hilog.error(DOMAIN, TAG, 'hostProxy 为空，无法发送 task 快照');
      return;
    }
    try {
      this.hostProxy.sendData(payload);
      hilog.info(DOMAIN, TAG, 'task snapshot sent %{public}d 字节, task=%{public}s completed',
        payload.length, finalTaskId);
    } catch (error) {
      hilog.error(DOMAIN, TAG, '发送 task 快照失败: %{public}s', (error as Error).message);
    }
  }
}
