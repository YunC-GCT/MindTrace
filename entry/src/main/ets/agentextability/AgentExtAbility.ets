/**
 * AgentExtAbility.ets - 端 A2A Agent 扩展入口（手写 JSON-RPC 2.0 单帧快照）
 *
 * 路径: entry/src/main/ets/agentextability/AgentExtAbility.ets
 * 职责: 接收小艺的 SendStreamingMessage，自己手写 JSON-RPC 请求解析与应答
 *       -> ReplyService 取回答 -> 经 hostProxy.sendData 回一条 result.task 快照。
 * 为什么手写: SDK 的自动应答封装会先发一帧 TASK_STATE_SUBMITTED（带 history），
 *       再发 artifactUpdate；小艺在这种序列下只渲染开头一两个词。历史实测「单帧 result.task
 *       一次给全 artifacts + COMPLETED」能完整渲染长文本，故回到手写。
 * 依赖: @kit.AbilityKit、@kit.PerformanceAnalysisKit、common.LlmConfig/OcrRecognizerRegistry、
 *       ./services/ReplyService、./services/IntentClassifier、./services/CaptureReceipt、./TaskSnapshot、
 *       ./services/CoreVisionOcrRecognizer
 *
 * 进程约束（重要）: 扩展跑在独立进程 <bundle>:agent，模块加载失败表现为 exit 254 /
 *   Reason:SyntaxError 且 onCreate 一行日志都打不出来（错误发生在 import 图求值阶段）。
 *   因此本文件禁止 import ModelRouter / OnDeviceLlm（及其依赖链）；端侧路由只在 UI 进程
 *   （ConversationWorkflowPorts）使用。
 *
 * 数据流:
 *   onCreate -> 组合根安装 OCR 能力（OcrRecognizerRegistry.install(CoreVisionOcrRecognizer)）
 *   onData(proxy, data) -> JSON.parse 取 id / params.message.parts[] 第一段 string text
 *     -> 解析失败：回一条错误快照（不崩）
 *     -> query 为空：回「没收到问题内容」
 *     -> 回执意图命中：读 last-capture.json -> formatReceipt -> sendAnswer（不等配置、不调模型）
 *     -> 异步：等配置（≤4s）-> isConfigured -> ReplyService.complete（25s / 0 retry）
 *     -> 35s deadline 到点：取消同一个 token（LlmClient 内 destroy 底层 HTTP），只回一次 timeout
 *     -> sendAnswer(taskId, text, query)：命中拍题/选图意图时用 buildTaskSnapshotWithCard
 *        追加一个官方 uiExtensionCard part；否则是逐字节不变的纯文本单帧快照
 */
import { AgentExtensionAbility, common, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CancellationToken, getProviderCatalog, KnowledgeUnit, LlmConfig, LlmError, OcrRecognizerRegistry, resolveModel } from 'common';
import type { NoteOutcome, ProviderCatalog, ResolvedModel } from 'common';
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
import { AgentInboxItem, buildInboxItem, shouldEnqueue } from '../services/AgentInboxModels';
import { AgentInboxQueue } from '../services/AgentInboxQueue';
import { AgentIngestService, AgentTextBatchResult } from '../services/AgentIngestService';
import {
  A2APlan,
  A2APlanCommand,
  A2APlanItem,
  PLAN_CMD_ALL,
  PLAN_CMD_CANCEL,
  PLAN_CMD_INDEX,
  PLAN_CMD_NONE,
  PLAN_CMD_START,
  buildA2APlanItems,
  formatA2APlanProgress,
  formatA2APlanSummary,
  nextPlanItem,
  parseA2APlanCommand,
  remainingPlanCount,
  reviewCountOf,
} from '../services/A2APlanModels';
import { A2APlanStore } from '../services/A2APlanStore';
import { AgentIngestRequest, buildIngestRequest, hasIngestPayload, INGEST_SOURCE_XIAOYI } from '../services/AgentIngestRequest';
import { AgentImagePart, AgentPart, collectImageParts, joinTextParts, mediaTypeOf } from '../services/AgentImageParts';
import { OcrService } from '../services/OcrService';
import { CoreVisionOcrRecognizer } from '../services/CoreVisionOcrRecognizer';
import { buildTaskSnapshotWithCard, unicodeCharCount, utf8ByteLength } from './TaskSnapshot';
import { buildPickCardPartJson, CARD_ID, wantsPickCard } from './A2AUiCard';

const TAG: string = 'MindTraceA2A';

/**
 * 官方 UI 卡片开关。真机出现 1011 start_ability_fail 或每秒重试时改 false 并重建，
 * 立刻退回纯文本（buildTaskSnapshotWithCard 的空卡片路径与旧输出逐字节一致）。
 */
const UI_CARD_ENABLED: boolean = true;

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
  /** 本轮原始 query：回执据此决定是否附带「拍题/选图」卡片 part */
  query: string;
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

// 小艺发来的 JSON-RPC 请求（proto-JSON）：文本 part 只有 mediaType + text，没有 kind/type；
// 图片/文件 part 用 raw（base64）或 url（file:// 等）+ mediaType（image/png…）承载。
// part 的形状判定与图片提取集中在 services/AgentImageParts（纯函数，可单测），这里只做透传。
interface A2AMessage {
  parts?: AgentPart[];
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
    // 组合根：:agent 进程自己安装 OCR 实现。主进程由 EntryAbility.onCreate 安装同一份实现。
    if (!OcrRecognizerRegistry.isInstalled()) {
      OcrRecognizerRegistry.install(new CoreVisionOcrRecognizer());
      hilog.info(DOMAIN, TAG, 'OCR 能力已安装（:agent 组合根）');
    }
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
    // 诊断：把原始报文前 1200 字打进日志。小艺侧“发了图但 parts 里没有图”的判定只能靠它，
    // 否则看不到客户端到底往报文里塞了什么（file 形状、metadata.fileInfos 等）。
    hilog.info(DOMAIN, TAG, 'raw=%{public}s', data.substring(0, Math.min(data.length, 1200)));
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
    this.logParts(request);
    const query: string = this.readQuery(request);
    const taskId: string = this.readTaskId(request);
    hilog.info(DOMAIN, TAG, 'id=%{public}s taskId=%{public}s query=%{public}s',
      this.lastRequestId, taskId.length > 0 ? taskId : 'none', query);

    if (query.indexOf('识别探针') >= 0) {
      OcrService.probe(this.context).then((r: string): void => {
        this.sendAnswer(taskId, 'OCR 探针：' + r, 0);
      });
      return;
    }
    // 协议 → 数据契约：文字和图片都折成同一个 AgentIngestRequest，后面的整理链路只认它。
    // 图片 part 存在时以「识别 + 整理」为主；只发图不打字也要能跑。
    const parts: AgentPart[] = this.readParts(request);
    const images: AgentImagePart[] = collectImageParts(parts);
    const text: string = query.length > 0 ? query : joinTextParts(parts);
    const ingest: AgentIngestRequest = buildIngestRequest(INGEST_SOURCE_XIAOYI, text, images);
    if (images.length > 0) {
      this.ingestDirectly(taskId, ingest);
      return;
    }
    if (!hasIngestPayload(ingest)) {
      // 实测（2026-10-29，小艺 11.7.8，平台照片开关已开、客户端也把图传到了 OBS）：
      // 扩展收到的仍然只有 1 个空 part —— {"parts":[{"mediaType":"text/plain"}]}，
      // 既没有 url 也没有 file，说明图是在小艺组装报文那一步被丢掉的，不是应用侧解析漏字段。
      // 应用侧已按协议兼容 url / raw / file.uri 三种图片载体（AgentImageParts）。
      // 空 payload 无法从 query 判意图，直接给卡片：点一下就能进应用选图。
      this.sendAnswerWithPickCard(taskId, '点下面的卡片去选图，或直接说『存笔记：…』');
      return;
    }
    // 「存笔记」走文字；有图片 part 时无论带不带文字都直接整理。
    // 原文在这里就地整理入库，用户不用回到应用（失败才退回队列，等应用前台补）。
    if (ingest.images.length > 0 || shouldEnqueue(query)) {
      this.ingestDirectly(taskId, ingest);
      return;
    }
    // onData 必须立刻返回：模型链路异步跑，结果回来再自己发快照
    this.runQuery(taskId, query);
  }

  /**
   * 就地整理：扩展进程自己初始化同一个 MindTrace.db，跑完整链路并落库，直接在小艺里回执。
   * 图片请求会先经过 OcrService（端侧识别）再落库；任何一步失败（模型、库、超时）
   * 都退回队列，保证原文不丢。
   */
  private ingestDirectly(taskId: string, request: AgentIngestRequest): void {
    hilog.info(DOMAIN, TAG, 'INGEST_DIRECT start source=%{public}s chars=%{public}d images=%{public}d',
      request.source, request.text.length, request.images.length);
    // 图片识别后的文字：多题时先回「识别摘要 + 整理规划」，再按用户指令一题一题整理。
    if (request.images.length === 0) {
      this.handleTextPlanMessage(taskId, request);
      return;
    }
    // A3d：A2A 回执直接消费 NoteOutcome（committed / failed / cancelled），不再靠异常文本判断。
    AgentIngestService.ingestOutcome(this.context, request)
      .then((outcome: NoteOutcome): void => {
        if (outcome.kind === 'committed' && outcome.unit !== undefined) {
          const unit: KnowledgeUnit = outcome.unit;
          hilog.info(DOMAIN, TAG, 'INGEST_DIRECT done subject=%{public}s title=%{public}s',
            unit.subject, unit.title);
          this.recordA2aIngestReceipt();
          this.sendAnswer(taskId,
            '已整理入库：' + unit.title + '（' + unit.subject + '）· 本次整理 1 条', 0,
            request.text);
          return;
        }
        if (outcome.kind === 'cancelled') {
          hilog.info(DOMAIN, TAG, 'INGEST_DIRECT cancelled committed=%{public}s',
            outcome.committed === true ? 'true' : 'false');
          const cancelledText: string = outcome.committed === true
            ? '这次整理已落库，但随后被取消了；笔记已保存，可在应用里查看。'
            : '这次整理已取消，没有写入笔记。';
          this.sendAnswer(taskId, cancelledText, 0);
          return;
        }
        const code: string = outcome.code !== undefined ? outcome.code : 'INGEST_FAILED';
        const retryable: boolean = outcome.retryable === true;
        hilog.error(DOMAIN, TAG, 'INGEST_DIRECT failed code=%{public}s retryable=%{public}s',
          code, retryable ? 'true' : 'false');
        if (request.images.length > 0) {
          // 队列只存文本；图片识别失败就把提示原样排进队列，至少留下用户意图
          this.sendAnswer(taskId, '这几张图没认出文字，换张清晰点的，或直接把题目文字发我。', 0);
          return;
        }
        if (!retryable) {
          this.sendAnswer(taskId, '这次没整理成（' + code + '），换个说法再发一次试试。', 0);
          return;
        }
        this.enqueueForIngest(taskId, request.text);
      })
      .catch((e: Error): void => {
        hilog.error(DOMAIN, TAG, 'INGEST_DIRECT failed %{public}s', e.message);
        if (request.images.length > 0) {
          this.sendAnswer(taskId, '这几张图没认出文字，换张清晰点的，或直接把题目文字发我。', 0);
          return;
        }
        this.enqueueForIngest(taskId, request.text);
      });
  }

  /** 文本入口：有未完成计划 → 推进计划；否则切题——多题先回规划，单题直接整理。 */
  private handleTextPlanMessage(taskId: string, request: AgentIngestRequest): void {
    A2APlanStore.load(this.context)
      .then((existing: A2APlan | null): void => {
        if (existing !== null) {
          this.handlePlanTurn(taskId, request.text, existing);
          return;
        }
        const items: A2APlanItem[] = buildA2APlanItems(request.text);
        hilog.info(DOMAIN, TAG, 'TEXT_PLAN items=%{public}d review=%{public}d',
          items.length, reviewCountOf(items));
        if (items.length > 1) {
          const plan: A2APlan = { taskId: taskId, createdAt: Date.now(), items: items, done: [] };
          A2APlanStore.save(this.context, plan)
            .then((): void => {
              this.sendAnswer(taskId, formatA2APlanSummary(plan), 0);
            })
            .catch((e: Error): void => {
              hilog.warn(DOMAIN, TAG, 'PLAN_SAVE_FAILED %{public}s', e.message);
              this.sendAnswer(taskId, formatA2APlanSummary(plan), 0);
            });
          return;
        }
        AgentIngestService.ingestTextBatch(this.context, request.text)
          .then((batch: AgentTextBatchResult): void => {
            this.handleTextBatch(taskId, request, batch);
          })
          .catch((e: Error): void => {
            hilog.error(DOMAIN, TAG, 'INGEST_TEXT_BATCH failed %{public}s', e.message);
            this.enqueueForIngest(taskId, request.text);
          });
      })
      .catch((e: Error): void => {
        hilog.error(DOMAIN, TAG, 'PLAN_LOAD_FAILED %{public}s', e.message);
        this.enqueueForIngest(taskId, request.text);
      });
  }

  /** 有未完成计划时：解析「继续 / 第 N 题 / 全部 / 取消」，逐题推进。 */
  private handlePlanTurn(taskId: string, query: string, plan: A2APlan): void {
    const command: A2APlanCommand = parseA2APlanCommand(query);
    if (command.kind === PLAN_CMD_CANCEL) {
      A2APlanStore.clear(this.context).catch((): void => {});
      this.sendAnswer(taskId, '已取消这次整理计划，没有写入新笔记。', 0);
      return;
    }
    if (command.kind === PLAN_CMD_ALL) {
      const pending: string[] = [];
      for (let i = 0; i < plan.items.length; i += 1) {
        if (plan.done.indexOf(plan.items[i].index) < 0) {
          pending.push(plan.items[i].text);
        }
      }
      this.enqueueTexts(pending);
      A2APlanStore.clear(this.context).catch((): void => {});
      this.sendAnswer(taskId, '已把剩余 ' + pending.length.toString()
        + ' 道题转待整理，打开 MindTrace 会自动补齐。', 0);
      return;
    }
    let item: A2APlanItem | undefined = undefined;
    if (command.kind === PLAN_CMD_INDEX) {
      for (let i = 0; i < plan.items.length; i += 1) {
        if (i + 1 === command.index) {
          item = plan.items[i];
          break;
        }
      }
      if (item === undefined) {
        this.sendAnswer(taskId, '没有第 ' + command.index.toString() + ' 题，当前共 '
          + plan.items.length.toString() + ' 题。', 0);
        return;
      }
    } else if (command.kind === PLAN_CMD_START) {
      item = nextPlanItem(plan);
    }
    if (item === undefined) {
      if (remainingPlanCount(plan) === 0) {
        A2APlanStore.clear(this.context).catch((): void => {});
        this.sendAnswer(taskId, '这次计划里的题都整理完了 ✅', 0);
        return;
      }
      this.sendAnswer(taskId, '当前有整理计划（共 ' + plan.items.length.toString() + ' 题，已完成 '
        + plan.done.length.toString() + ' 题）。回复「继续」/「第 N 题」/「全部」/「取消」。', 0);
      return;
    }
    this.ingestPlanItem(taskId, plan, item);
  }

  /** 整理计划中的一道题；完成后更新进度并回执。 */
  private ingestPlanItem(taskId: string, plan: A2APlan, item: A2APlanItem): void {
    hilog.info(DOMAIN, TAG, 'PLAN_INGEST item=%{public}d chars=%{public}d',
      item.index, item.text.length);
    AgentIngestService.ingestSingleText(this.context, item.text)
      .then((outcome: NoteOutcome): void => {
        if (outcome.kind === 'committed' && outcome.unit !== undefined) {
          const unit: KnowledgeUnit = outcome.unit;
          plan.done.push(item.index);
          A2APlanStore.save(this.context, plan).catch((): void => {});
          this.recordA2aIngestReceipt();
          this.sendAnswer(taskId, formatA2APlanProgress(plan, item, unit.title, unit.subject), 0);
          return;
        }
        hilog.error(DOMAIN, TAG, 'PLAN_INGEST failed kind=%{public}s', outcome.kind);
        this.sendAnswer(taskId, '第 ' + (item.index + 1).toString()
          + ' 题这次没整理成，回复「继续」重试，或「取消」。', 0);
      })
      .catch((e: Error): void => {
        hilog.error(DOMAIN, TAG, 'PLAN_INGEST exception %{public}s', e.message);
        this.sendAnswer(taskId, '第 ' + (item.index + 1).toString()
          + ' 题这次没整理成，回复「继续」重试，或「取消」。', 0);
      });
  }

  /** 处理「文字多题」结果：第 1 题同步回执，剩余题入待整理队列（app 前台补跑）。 */
  private handleTextBatch(taskId: string, request: AgentIngestRequest, batch: AgentTextBatchResult): void {
    if (batch.outcomes.length === 0) {
      this.enqueueForIngest(taskId, request.text);
      return;
    }
    const outcome: NoteOutcome = batch.outcomes[0];
    if (outcome.kind === 'committed' && outcome.unit !== undefined) {
      const unit: KnowledgeUnit = outcome.unit;
      hilog.info(DOMAIN, TAG, 'INGEST_TEXT done problems=%{public}d title=%{public}s',
        batch.totalProblems, unit.title);
      this.recordA2aIngestReceipt();
      if (batch.totalProblems > 1) {
        this.enqueueTexts(batch.queuedTexts);
        this.sendAnswer(taskId,
          '已整理入库：' + unit.title + '（' + unit.subject + '）。本次识别 ' + batch.totalProblems.toString()
            + ' 道题，已入第 1 道；其余 ' + batch.queuedTexts.length.toString()
            + ' 道已转待整理，打开 MindTrace 会自动补齐。', 0);
        return;
      }
      this.sendAnswer(taskId,
        '已整理入库：' + unit.title + '（' + unit.subject + '）· 本次整理 1 条', 0, request.text);
      return;
    }
    if (outcome.kind === 'cancelled') {
      const cancelledText: string = outcome.committed === true
        ? '这次整理已落库，但随后被取消了；笔记已保存，可在应用里查看。'
        : '这次整理已取消，没有写入笔记。';
      this.sendAnswer(taskId, cancelledText, 0);
      return;
    }
    const code: string = outcome.code !== undefined ? outcome.code : 'INGEST_FAILED';
    if (outcome.retryable === true) {
      this.enqueueTexts(batch.totalProblems > 1 ? batch.queuedTexts : [request.text]);
      this.enqueueForIngest(taskId, request.text);
      return;
    }
    this.sendAnswer(taskId, '这次没整理成（' + code + '），换个说法再发一次试试。', 0);
  }

  /** 剩余题逐条追加待整理队列（尽力而为，失败只记日志）。 */
  private enqueueTexts(texts: string[]): void {
    for (let i = 0; i < texts.length; i += 1) {
      AgentInboxQueue.append(this.context, buildInboxItem(texts[i], Date.now() + i))
        .then((pending: number): void => {
          hilog.info(DOMAIN, TAG, 'INBOX_ENQUEUED_BATCH pending=%{public}d', pending);
        })
        .catch((e: Error): void => {
          hilog.warn(DOMAIN, TAG, 'INBOX_ENQUEUE_BATCH_FAILED %{public}s', e.message);
        });
    }
  }

  /**
   * P4 结果回执：A2A 就地入库也计入最近一次整理回执（小艺问「整理了几条」能给真实数字）。
   * 尽力而为：读写失败只记日志，不影响本次回复。
   */
  private recordA2aIngestReceipt(): void {
    CaptureReceiptStore.read(this.context).then((prev: CaptureReceipt | null): void => {
      const receipt: CaptureReceipt = {
        done: (prev !== null ? prev.done : 0) + 1,
        failed: prev !== null ? prev.failed : 0,
        total: (prev !== null ? prev.total : 0) + 1,
        at: Date.now(),
        source: 'a2a',
      };
      CaptureReceiptStore.save(this.context, receipt).catch((e: Error): void => {
        hilog.warn(DOMAIN, TAG, 'RECEIPT_SAVE_FAILED %{public}s', e.message);
      });
    }).catch((e: Error): void => {
      hilog.warn(DOMAIN, TAG, 'RECEIPT_READ_FAILED %{public}s', e.message);
    });
  }

  private enqueueForIngest(taskId: string, query: string): void {
    const item: AgentInboxItem = buildInboxItem(query, Date.now());
    AgentInboxQueue.append(this.context, item)
      .then((pending: number): void => {
        hilog.info(DOMAIN, TAG, 'INBOX_ENQUEUED pending=%{public}d chars=%{public}d',
          pending, item.text.length);
        this.sendAnswer(taskId,
          '模型这次没通，已记为待整理（第 ' + pending.toString() + ' 条）。打开 MindTrace 会自动补上。', 0);
      })
      .catch((e: Error): void => {
        hilog.error(DOMAIN, TAG, 'INBOX_ENQUEUE_FAILED %{public}s', e.message);
        this.sendAnswer(taskId, '这条笔记没排上队，再发一次？', 0);
      });
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

  /** 取出所有 parts（文本 + 图片/文件），解析层与诊断日志共用 */
  private readParts(request: A2ARequest): AgentPart[] {
    const params: A2AParams | undefined = request.params;
    if (params === undefined) {
      return [];
    }
    const message: A2AMessage | undefined = params.message;
    if (message === undefined) {
      return [];
    }
    const parts: AgentPart[] | undefined = message.parts;
    if (parts === undefined) {
      return [];
    }
    return parts;
  }

  /** 诊断：把每个 part 的形状打进日志（媒体类型 + 各字段长度），确认小艺到底发了什么 */
  private logParts(request: A2ARequest): void {
    const parts: AgentPart[] = this.readParts(request);
    hilog.info(DOMAIN, TAG, 'parts=%{public}d', parts.length);
    let i: number = 0;
    for (const part of parts) {
      const media: string = mediaTypeOf(part);
      const textLen: number = (part.text ?? '').length;
      const rawLen: number = (part.raw ?? '').length;
      const url: string = part.url ?? '';
      const fileUri: string = part.file !== undefined && part.file.uri !== undefined ? part.file.uri : '';
      const dataKind: string = part.data === undefined ? 'none' : typeof part.data;
      hilog.info(DOMAIN, TAG,
        'part[%{public}d] media=%{public}s text=%{public}d raw=%{public}d data=%{public}s url=%{public}s file=%{public}s',
        i, media, textLen, rawLen, dataKind, url.length > 0 ? url : 'none',
        fileUri.length > 0 ? fileUri : 'none');
      i = i + 1;
    }
  }

  /** 统计图片 part 数量：mediaType（或 file.mimeType）以 image/ 开头 */
  private countImageParts(request: A2ARequest): number {
    const parts: AgentPart[] = this.readParts(request);
    let count: number = 0;
    for (const part of parts) {
      const media: string = mediaTypeOf(part);
      if (media.startsWith('image/')) {
        count = count + 1;
      }
    }
    return count;
  }

  /** 小艺的 parts 只有 mediaType + text：取第一个 text 为 string 的 part */
  private readQuery(request: A2ARequest): string {
    const parts: AgentPart[] = this.readParts(request);
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
      query: query,
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
    this.sendAnswer(session.taskId, text, session.requestStartedAt, session.query);
  }

  /**
   * 单帧 result.task 快照：一次给全 artifacts + TASK_STATE_COMPLETED。
   * 不拆 statusUpdate / artifactUpdate —— 小艺对增量帧只渲染开头几个词。
   * 报文拼装由 TaskSnapshot（纯函数）负责，这里只选 taskId 并发送。
   *
   * 卡片 part：query 命中「拍题/选图」意图且 UI_CARD_ENABLED 时追加一个
   * buildPickCardPartJson(query)；每个 task 只发一帧快照，卡片 part 最多一个。
   *
   * #234 可观测性: 发送成功后只打计数摘要（chars/字节/特殊符号/耗时），
   * 不打印正文、正文前缀或哈希（AGENTS 红线）。requestStartedAt 由调用方传入
   * 当前 session 的模型调用起点；无 session 的分支传 0，elapsedMs 记 0。
   */
  private sendAnswer(taskId: string, text: string, requestStartedAt: number, cardQuery: string = ''): void {
    const cardPartJson: string = UI_CARD_ENABLED && wantsPickCard(cardQuery)
      ? buildPickCardPartJson(cardQuery) : '';
    this.sendSnapshot(taskId, text, requestStartedAt, cardPartJson);
  }

  /**
   * 空 payload 分支专用：没有 query 可判意图，直接带一张卡片。
   * 文案与 sendAnswer 分开，避免把「没有内容」说成「已整理」。
   */
  private sendAnswerWithPickCard(taskId: string, text: string): void {
    const cardPartJson: string = UI_CARD_ENABLED ? buildPickCardPartJson('') : '';
    this.sendSnapshot(taskId, text, 0, cardPartJson);
  }

  /** 唯一发帧出口：拼快照 + 发一帧 + 计数日志。 */
  private sendSnapshot(taskId: string, text: string, requestStartedAt: number, cardPartJson: string): void {
    const finalTaskId: string = taskId.length > 0 ? taskId : 'task-' + Date.now().toString();
    const payload: string = buildTaskSnapshotWithCard(this.lastRequestId, finalTaskId, text, cardPartJson);
    if (this.hostProxy === null) {
      hilog.error(DOMAIN, TAG, 'hostProxy 为空，无法发送 task 快照');
      return;
    }
    try {
      this.hostProxy.sendData(payload);
      if (cardPartJson.length > 0) {
        hilog.info(DOMAIN, TAG, 'A2A_UI_CARD sent cardId=%{public}s chars=%{public}d',
          CARD_ID, cardPartJson.length);
      }
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
