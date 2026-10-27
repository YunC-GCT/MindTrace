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
 *     -> 异步：等配置（≤4s）-> isConfigured -> ReplyService.complete（25s / 0 retry）
 *     -> 35s deadline 到点：取消同一个 token（LlmClient 内 destroy 底层 HTTP），只回一次 timeout
 *     -> sendAnswer(taskId, text)：buildTaskSnapshot 拼单帧 task 快照，artifacts 内是完整文本
 */
import { AgentExtensionAbility, common, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CancellationToken, getProviderCatalog, LlmConfig, LlmError, resolveModel } from 'common';
import type { ProviderCatalog, ResolvedModel } from 'common';
import { IntentClassifier, ReplyContext } from '../services/IntentClassifier';
import { ReplyService } from '../services/ReplyService';
import type { LlmCallPolicy } from '../services/ReplyService';
import type { ReplyStyle } from '../services/ReplyStyleRules';
import {
  CaptureReceipt,
  CaptureReceiptStore,
  formatReceipt,
  matchesReceiptIntent,
} from '../services/CaptureReceipt';
import { buildTaskSnapshot, unicodeCharCount, utf8ByteLength } from './TaskSnapshot';

const TAG: string = 'MindTraceA2A';

/**
 * A2A 单次回复预算（计划 §4.1–§4.3）——超时/重试/输出预算的数字只在这里定义。
 * 自洽关系：35000 >= 4000 + 1 * (25000 + 0) + 6000。
 * task_need = 4096；LlmClient 会再按清单取 min(4096, listing.maxOutputTokens)，
 * 清单未知时保持 4096。
 */
export interface A2APolicy {
  configTimeoutMs: number;
  maxRetries: number;
  requestTimeoutMs: number;
  backoffMs: number;
  marginMs: number;
  deadlineMs: number;
  taskNeedTokens: number;
}

export const A2A_POLICY: A2APolicy = {
  configTimeoutMs: 4000,
  maxRetries: 0,
  requestTimeoutMs: 25000,
  backoffMs: 0,
  marginMs: 6000,
  deadlineMs: 35000,
  taskNeedTokens: 4096,
};

/**
 * A2A 回复风格（#234）：小艺渲染层会吞掉 $...$ / LaTeX，扩展通道只发纯文本数学。
 * App 内聊天走 ReplyService 默认的 'markdown'，公式渲染不受影响。
 * 回退只需改成 'markdown' 并重建（小艺会重新出现公式被吞的现象）。
 */
const A2A_REPLY_STYLE: ReplyStyle = 'plain_text_math';

function a2aAttempts(): number {
  return A2A_POLICY.maxRetries + 1;
}

/** config + attempts * (inner + backoff) + margin，启动时自检 35000 是否自洽。 */
function a2aBudgetMs(): number {
  return A2A_POLICY.configTimeoutMs
    + a2aAttempts() * (A2A_POLICY.requestTimeoutMs + A2A_POLICY.backoffMs)
    + A2A_POLICY.marginMs;
}

/**
 * 稳定日志 code（计划 §4.3）。A2A_LLM_FAILED 只兜底非超时类错误
 * （API_ERROR / NO_API_KEY 等），不与表内超时语义混用。
 */
type A2AErrorCode =
  | 'A2A_CONFIG_READ_TIMEOUT'
  | 'A2A_MODEL_UNUSABLE'
  | 'A2A_MODEL_ID_UNRESOLVED'
  | 'A2A_LLM_TIMEOUT'
  | 'A2A_DEADLINE_EXCEEDED'
  | 'A2A_REPLY_SENT'
  | 'A2A_LLM_FAILED';

const A2A_TIMEOUT_TEXT: string = '模型响应超时，稍后再试。';
const A2A_CONFIG_TIMEOUT_TEXT: string = '模型配置读取超时（'
  + A2A_POLICY.configTimeoutMs.toString() + ' ms），请稍后再试。';

/** 端侧模型未就绪且未配置云端模型时的如实回复：不调模型，也不假装回答 */
const MODEL_NOT_READY: string =
  '端侧模型未就绪（model file not found），请先在 MindTrace 设置里配置模型';

/** 请求解析失败时的错误快照文案：宁可回一句错，也不要让扩展崩掉 */
const PARSE_ERROR: string = '请求解析失败，请重试。';

/** 单次请求的预算与状态：保证 deadline 只取消一次、timeout 只发一次 */
interface A2ARequestSession {
  taskId: string;
  token: CancellationToken;
  startedAt: number;
  /** 实际发起模型调用的时刻；0 表示尚未调用 */
  requestStartedAt: number;
  deadlineTimer: number;
  responded: boolean;
  requestedModel: string;
  canonicalModel: string;
  attempts: number;
}

/** 扩展进程内的模型配置初始化（只做一次），runQuery 前必须等它 */
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
  /** 当前在跑的请求：onData 重入或 onDestroy 时用它取消 token / 清 deadline */
  private activeSession: A2ARequestSession | null = null;

  onCreate(want: Want): void {
    const abilityName: string = want.abilityName ?? 'unknown';
    hilog.info(DOMAIN, TAG, 'onCreate: 扩展被拉起 ability=%{public}s（手写单帧快照模式）', abilityName);
    hilog.info(DOMAIN, TAG,
      'A2A policy config=%{public}d attempts=%{public}d inner=%{public}d backoff=%{public}d margin=%{public}d deadline=%{public}d budget=%{public}d taskNeed=%{public}d',
      A2A_POLICY.configTimeoutMs, a2aAttempts(), A2A_POLICY.requestTimeoutMs, A2A_POLICY.backoffMs,
      A2A_POLICY.marginMs, A2A_POLICY.deadlineMs, a2aBudgetMs(), A2A_POLICY.taskNeedTokens);
    if (a2aBudgetMs() !== A2A_POLICY.deadlineMs) {
      hilog.warn(DOMAIN, TAG, 'A2A budget mismatch budget=%{public}d deadline=%{public}d',
        a2aBudgetMs(), A2A_POLICY.deadlineMs);
    }
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
    // 新请求一到达就作废上一条在途请求（含后面的 parse-error / 空 query 分支），
    // 避免旧 session 晚到的回复套用新 requestId 发出去。
    this.cancelActiveSession();

    // 解析失败（JSON 非法 / 顶层不是对象）统一回错误快照，绝不让异常冒出去
    const request: A2ARequest | null = this.parseRequest(data);
    if (request === null) {
      this.lastRequestId = '';
      this.sendAnswer('', PARSE_ERROR, 0);
      return;
    }

    this.lastRequestId = this.readRequestId(request.id);
    const query: string = this.readQuery(request);
    const taskId: string = this.readTaskId(request);
    hilog.info(DOMAIN, TAG, 'id=%{public}s taskId=%{public}s query=%{public}s',
      this.lastRequestId, taskId.length > 0 ? taskId : 'none', query);

    if (query.length === 0) {
      this.sendAnswer(taskId, '没收到问题内容，再说一次？', 0);
      return;
    }
    // onData 必须立刻返回：模型链路异步跑，结果回来再自己发快照
    this.runQuery(taskId, query);
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

  /**
   * 作废当前在途请求：先标记已应答，再取消 token。
   * LlmClient 的 onCancel 监听会 httpRequest.destroy()，不会留下后台僵尸请求。
   */
  private cancelActiveSession(): void {
    const session: A2ARequestSession | null = this.activeSession;
    if (session === null) {
      return;
    }
    session.responded = true;
    clearTimeout(session.deadlineTimer);
    session.token.cancel();
    this.activeSession = null;
  }

  onDestroy(): void {
    // 扩展销毁时取消在途请求。
    this.cancelActiveSession();
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

  /** 从 onData 拿到有效 query 开始计时：4s 配置 + 25s 模型 + 6s 余量 = 35s。 */
  private runQuery(taskId: string, query: string): void {
    // 回执意图本地判定：命中就读落盘事实，不等待 configReady、不调 ReplyService、不判 LlmConfig
    if (matchesReceiptIntent(query)) {
      this.answerFromReceipt(taskId);
      return;
    }
    const startedAt: number = Date.now();
    const token: CancellationToken = new CancellationToken();
    const session: A2ARequestSession = {
      taskId: taskId,
      token: token,
      startedAt: startedAt,
      requestStartedAt: 0,
      deadlineTimer: 0,
      responded: false,
      requestedModel: '',
      canonicalModel: '',
      attempts: 0,
    };
    this.activeSession = session;

    session.deadlineTimer = setTimeout((): void => {
      if (session.responded) {
        return;
      }
      // 同一个 token 贯穿 ReplyService → LlmGuard → LlmClient；
      // LlmClient 的 onCancel 监听会 request.destroy()，不留后台僵尸请求。
      session.token.cancel();
      this.settle(session, 'A2A_DEADLINE_EXCEEDED', A2A_TIMEOUT_TEXT,
        'deadline ' + A2A_POLICY.deadlineMs.toString() + 'ms');
    }, A2A_POLICY.deadlineMs);

    const replyContext: ReplyContext = {
      memoryContext: '',
      learnerProfileContext: '',
      userContent: query,
      evidenceContext: '',
    };
    this.awaitConfig()
      .then((ready: boolean): void => {
        if (session.responded) {
          return;
        }
        if (!ready) {
          // 配置没能读到，用当前缓存值（可能是默认值）尽量补齐审计字段。
          this.fillModelFieldsFromCachedConfig(session);
          this.settle(session, 'A2A_CONFIG_READ_TIMEOUT', A2A_CONFIG_TIMEOUT_TEXT,
            'config wait exceeded ' + A2A_POLICY.configTimeoutMs.toString() + 'ms');
          return;
        }
        this.answerWithResolvedModel(session, replyContext);
      })
      .catch((e: Error): void => {
        if (session.responded) {
          return;
        }
        this.handleFailure(session, e);
      });
  }

  /**
   * 回执直接读文件回答：不建 session、不占 deadline 预算、不碰 LlmConfig。
   * 读写失败都只影响这一条答复（read 内部已把异常收敛成 null）。
   */
  private async answerFromReceipt(taskId: string): Promise<void> {
    const receipt: CaptureReceipt | null = await CaptureReceiptStore.read(this.context);
    hilog.info(DOMAIN, TAG,
      '[Receipt] hit=true receipt=%{public}s done=%{public}d failed=%{public}d total=%{public}d',
      receipt !== null ? 'true' : 'false',
      receipt !== null ? receipt.done : 0,
      receipt !== null ? receipt.failed : 0,
      receipt !== null ? receipt.total : 0);
    this.sendAnswer(taskId, formatReceipt(receipt, Date.now()), 0);
  }

  /** 配置读取最多等 T_config；超时返回 false，由调用方回配置超时 task。 */
  private awaitConfig(): Promise<boolean> {
    return new Promise<boolean>((resolve: (ready: boolean) => void): void => {
      let done: boolean = false;
      let timer: number = 0;
      const finish = (ready: boolean): void => {
        if (done) {
          return;
        }
        done = true;
        clearTimeout(timer);
        resolve(ready);
      };
      timer = setTimeout((): void => {
        finish(false);
      }, A2A_POLICY.configTimeoutMs);
      if (configReady === null) {
        // onCreate 还没跑：让 4s 计时器给出 A2A_CONFIG_READ_TIMEOUT。
        return;
      }
      configReady.then((): void => {
        finish(true);
      }).catch((): void => {
        // init 内部已记录错误；按“配置可用”继续，由 isConfigured 决定是否调模型。
        finish(true);
      });
    });
  }

  /**
   * 审计用的 requestedModel：优先用户显式写入的原始 ID（可能是旧别名），
   * 没有显式选择时回落到 getModel() 的生效值。canonicalModel 由 resolver 给出。
   */
  private readRequestedModel(config: LlmConfig, vendorId: string): string {
    const activeModels: Record<string, string> = config.getAllActiveVendorModels();
    const activeModel: string | undefined = activeModels[vendorId];
    if (activeModel !== undefined && activeModel.trim().length > 0) {
      return activeModel.trim();
    }
    return config.getModel();
  }

  /** 配置等待超时时，用当前缓存（可能是默认值）尽量补齐日志里的模型字段。 */
  private fillModelFieldsFromCachedConfig(session: A2ARequestSession): void {
    try {
      const config: LlmConfig = LlmConfig.getInstance();
      const vendorId: string = config.getVendorId();
      const requestedModel: string = this.readRequestedModel(config, vendorId);
      const resolved: ResolvedModel = resolveModel(vendorId, requestedModel);
      session.requestedModel = requestedModel;
      session.canonicalModel = resolved.canonicalId.length > 0 ? resolved.canonicalId : requestedModel;
    } catch (_e) {
      // 配置完全不可读时保留空字段；reason 已说明是 config wait。
    }
  }

  /**
   * 解析本次实际请求的模型，再走配置检查 + ReplyService。
   * 未知 ID：不静默替换，回 ID + 解析原因。
   * 清单已知但条目不可用：显式降级到同 provider catalog 默认，并在回复里标注。
   * 清单为空（Phase 1 只覆盖 deepseek）：按 deferred 语义继续用原 ID，只记 code。
   */
  private answerWithResolvedModel(session: A2ARequestSession, context: ReplyContext): void {
    const config: LlmConfig = LlmConfig.getInstance();
    const vendorId: string = config.getVendorId();
    const requestedModel: string = this.readRequestedModel(config, vendorId);
    const resolved: ResolvedModel = resolveModel(vendorId, requestedModel);
    session.requestedModel = requestedModel;
    session.canonicalModel = resolved.canonicalId.length > 0 ? resolved.canonicalId : requestedModel;
    let modelOverride: string = '';
    let degradedNote: string = '';
    const catalog: ProviderCatalog | null = getProviderCatalog(vendorId);
    if (!resolved.usable) {
      if (catalog !== null && catalog.models.length > 0) {
        if (resolved.reason === 'MODEL_ID_UNRESOLVED') {
          // 未知 ID 不静默换成另一个型号。
          this.settle(session, 'A2A_MODEL_ID_UNRESOLVED',
            '模型不可用：' + session.canonicalModel + '（' + resolved.reason + '）',
            resolved.reason);
          return;
        }
        // 清单有该条目但不可用：显式降级到同 provider catalog 默认，并在回复里标注。
        const fallbackResolved: ResolvedModel = resolveModel(vendorId, catalog.defaultModelId);
        if (!fallbackResolved.usable) {
          this.settle(session, 'A2A_MODEL_UNUSABLE',
            '模型不可用：' + session.canonicalModel + '（' + resolved.reason + '）',
            resolved.reason);
          return;
        }
        modelOverride = fallbackResolved.canonicalId;
        session.canonicalModel = modelOverride;
        degradedNote = '\n\n已降级：' + requestedModel + ' / ' + resolved.reason;
        hilog.warn(DOMAIN, TAG,
          'A2A_MODEL_UNUSABLE requestedModel=%{public}s canonicalModel=%{public}s reason=%{public}s attempts=%{public}d',
          session.requestedModel, session.canonicalModel, resolved.reason, session.attempts);
      } else {
        // 其它 vendor 暂无 catalog：这是 deferred 读取，不是“模型被替换”。
        hilog.warn(DOMAIN, TAG,
          'A2A_MODEL_ID_UNRESOLVED requestedModel=%{public}s canonicalModel=%{public}s reason=%{public}s attempts=%{public}d',
          session.requestedModel, session.canonicalModel, resolved.reason, session.attempts);
      }
    }
    this.answerAndSettle(session, context, resolved.reason, modelOverride, degradedNote);
  }

  private answerAndSettle(
    session: A2ARequestSession,
    context: ReplyContext,
    resolveReason: string,
    modelOverride: string,
    degradedNote: string,
  ): void {
    this.answerIfConfigured(session, context, modelOverride, degradedNote)
      .then((answer: string): void => {
        if (session.responded) {
          return;
        }
        const reason: string = resolveReason.length > 0 ? resolveReason : 'OK';
        this.settle(session, 'A2A_REPLY_SENT', answer, reason);
      })
      .catch((e: Error): void => {
        if (session.responded) {
          return;
        }
        this.handleFailure(session, e);
      });
  }

  /**
   * 配置就绪 -> 走 ReplyService（与 UI 聊天同一条链路，明确不经过 ModelRouter）；
   * 未就绪 -> 不调模型，直接返回未就绪文案。
   */
  private async answerIfConfigured(
    session: A2ARequestSession,
    context: ReplyContext,
    modelOverride: string,
    degradedNote: string,
  ): Promise<string> {
    if (session.responded) {
      return '';
    }
    const configured: boolean = await LlmConfig.getInstance().isConfigured();
    if (session.responded || session.token.isCancelled()) {
      // deadline 已经回过 timeout；不要再发第二次。
      return '';
    }
    if (!configured) {
      hilog.info(DOMAIN, TAG, 'LlmConfig 未配置（端侧模型未就绪），跳过模型调用');
      return MODEL_NOT_READY;
    }
    const policy: LlmCallPolicy = {
      // LlmClient 会再按清单取 min(4096, listing.maxOutputTokens)。
      maxTokens: A2A_POLICY.taskNeedTokens,
      timeoutMs: A2A_POLICY.requestTimeoutMs,
      maxRetries: A2A_POLICY.maxRetries,
      model: modelOverride,
    };
    session.attempts = a2aAttempts();
    session.requestStartedAt = Date.now();
    hilog.info(DOMAIN, TAG,
      'A2A LLM call requestedModel=%{public}s canonicalModel=%{public}s attempts=%{public}d timeoutMs=%{public}d maxTokens=%{public}d',
      session.requestedModel, session.canonicalModel, session.attempts,
      policy.timeoutMs, policy.maxTokens);
    const raw: string = await new ReplyService(new IntentClassifier())
      .complete(context, session.token, policy, A2A_REPLY_STYLE);
    const elapsed: number = Date.now() - session.requestStartedAt;
    const text: string = raw.length > 0 ? raw : '模型没有返回内容，换个问法试试。';
    const withNote: string = degradedNote.length > 0 ? text + degradedNote : text;
    hilog.info(DOMAIN, TAG, 'LLM 返回 %{public}d 字，耗时 %{public}d ms',
      unicodeCharCount(withNote), elapsed);
    return withNote;
  }

  private handleFailure(session: A2ARequestSession, e: Error): void {
    const reason: string = e instanceof Error && e.message.length > 0 ? e.message : String(e);
    if (session.token.isCancelled() || reason === 'CONVERSATION_CANCELLED') {
      // deadline 定时器通常已经 settle；这里兜底仍只发一次。
      this.settle(session, 'A2A_DEADLINE_EXCEEDED', A2A_TIMEOUT_TEXT, 'cancelled: ' + reason);
      return;
    }
    // 单次模型调用的 25s 连接/读取超时：平台可能报 TIMEOUT，也可能包成 NETWORK_ERROR。
    const modelElapsed: number = session.requestStartedAt > 0
      ? Date.now() - session.requestStartedAt : 0;
    const timedOut: boolean = e instanceof LlmError
      && (e.kind === 'TIMEOUT' || e.kind === 'STREAM_FAILED'
        || (e.kind === 'NETWORK_ERROR' && modelElapsed >= A2A_POLICY.requestTimeoutMs));
    if (timedOut) {
      this.settle(session, 'A2A_LLM_TIMEOUT', A2A_TIMEOUT_TEXT, reason);
      return;
    }
    hilog.error(DOMAIN, TAG, 'LLM 调用失败: %{public}s', reason);
    this.settle(session, 'A2A_LLM_FAILED', '模型暂时不可用：' + reason, reason);
  }

  /** 单次应答出口：responded 守卫保证 timeout/reply 只发一帧。 */
  private settle(session: A2ARequestSession, code: A2AErrorCode, text: string, reason: string): void {
    if (session.responded) {
      return;
    }
    session.responded = true;
    clearTimeout(session.deadlineTimer);
    if (this.activeSession === session) {
      this.activeSession = null;
    }
    const elapsedMs: number = Date.now() - session.startedAt;
    hilog.info(DOMAIN, TAG,
      '%{public}s requestId=%{public}s taskId=%{public}s requestedModel=%{public}s canonicalModel=%{public}s reason=%{public}s attempts=%{public}d elapsedMs=%{public}d',
      code, this.lastRequestId, session.taskId, session.requestedModel, session.canonicalModel,
      reason, session.attempts, elapsedMs);
    this.sendAnswer(session.taskId, text, session.requestStartedAt);
  }

  /**
   * 单帧 result.task 快照：一次给全 artifacts + TASK_STATE_COMPLETED。
   * 不拆 statusUpdate / artifactUpdate —— 小艺对增量帧只渲染开头几个词。
   * 报文拼装由 TaskSnapshot.buildTaskSnapshot（纯函数）负责，这里只选 taskId 并发送。
   *
   * #234 可观测性: 发送成功后只打计数摘要（chars/字节/特殊符号/耗时），
   * 不打印正文、正文前缀或哈希（AGENTS 红线）。requestStartedAt 由调用方传入
   * 当前 session 的模型调用起点；无 session 的分支传 0，elapsedMs 记 0。
   */
  private sendAnswer(taskId: string, text: string, requestStartedAt: number): void {
    const finalTaskId: string = taskId.length > 0 ? taskId : 'task-' + Date.now().toString();
    const payload: string = buildTaskSnapshot(this.lastRequestId, finalTaskId, text);
    if (this.hostProxy === null) {
      hilog.error(DOMAIN, TAG, 'hostProxy 为空，无法发送 task 快照');
      return;
    }
    try {
      this.hostProxy.sendData(payload);
      const elapsedMs: number = requestStartedAt > 0 ? Date.now() - requestStartedAt : 0;
      hilog.info(DOMAIN, TAG,
        'A2A_REPLY_SENT chars=%{public}d utf8Bytes=%{public}d snapshotBytes=%{public}d dollar=%{public}d backslash=%{public}d zeroWidth=%{public}d sqrt=%{public}d ge=%{public}d elapsedMs=%{public}d taskId=%{public}s',
        unicodeCharCount(text), utf8ByteLength(text), utf8ByteLength(payload),
        this.countOccurrences(text, '$'), this.countOccurrences(text, '\\'),
        this.countZeroWidth(text), text.indexOf('√') >= 0 ? 1 : 0,
        text.indexOf('≥') >= 0 ? 1 : 0, elapsedMs, finalTaskId);
    } catch (error) {
      hilog.error(DOMAIN, TAG, '发送 task 快照失败: %{public}s', (error as Error).message);
    }
  }

  /** 统计子串出现次数：只把计数写日志，永远不写正文。 */
  private countOccurrences(text: string, needle: string): number {
    if (needle.length === 0) {
      return 0;
    }
    let count: number = 0;
    let index: number = text.indexOf(needle);
    while (index >= 0) {
      count += 1;
      index = text.indexOf(needle, index + needle.length);
    }
    return count;
  }

  /** 零宽字符计数（U+200B/200C/200D/FEFF）：小艺吞公式时会留下 U+200B 占位。 */
  private countZeroWidth(text: string): number {
    let count: number = 0;
    for (let i = 0; i < text.length; i++) {
      const code: number = text.charCodeAt(i);
      if (code === 0x200B || code === 0x200C || code === 0x200D || code === 0xFEFF) {
        count += 1;
      }
    }
    return count;
  }
}
