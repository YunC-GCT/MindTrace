/**
 * A2AController.ets — 小艺端 A2A 请求编排（从 AgentExtAbility 抽出）
 *
 * 路径: entry/src/main/ets/services/A2AController.ets
 * 职责: 承接 A2A 请求的策略与编排：意图路由、整理计划、内联整理、会话记忆、回执与对话回复；
 *       协议解析、part 形状判定与 task 快照发送留在 AgentExtAbility，经 A2AReplyPort 回话。
 * 依赖: common.DatabaseHelper/LlmConfig/OcrService、A2A* 服务、AgentIngestService、ReplyService。
 * 数据流: AgentExtAbility.onData → A2AController.handle(A2ARequestInput) → A2AReplyPort.send()
 *
 * 边界: 不解析 JSON-RPC、不持有 hostProxy、不拼快照；因此本类可在 Node 契约测试里按源码守卫。
 * 写库模式（ADR-0024 §2.1/§2.7）: A2A 单次整理在 :agent 内联执行；文本批量 90s deadline，
 *   超时/失败/溢出回退 inbox/agent_job。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { A2AIngestHandler } from './A2AIngestHandler';
import { A2AAnswerHandler } from './A2AAnswerHandler';
import type { IA2AAnswerHost } from './A2AAnswerHandler';
import type { A2ARequestSession } from './A2ASession';
import { A2A_POLICY, DOMAIN, INGEST_DEADLINE_MS, TAG, a2aAttempts, a2aBudgetMs } from './A2AConstants';
import type { IA2AIngestHost } from './A2AIngestHandler';
import type { common } from '@kit.AbilityKit';
import {
  CancellationToken,
  DatabaseHelper,
  getProviderCatalog,
  KnowledgeUnit,
  LlmConfig,
  LlmError,
  resolveModel,
} from 'common';
import type { NoteOutcome, ProviderCatalog, ResolvedModel } from 'common';

import { CaptureReceipt, CaptureReceiptStore, formatReceipt, matchesReceiptIntent } from './CaptureReceipt';
import { AgentInboxItem, buildInboxItem } from './AgentInboxModels';
import { AgentInboxQueue } from './AgentInboxQueue';
import { AgentIngestRequest, buildIngestRequest, INGEST_SOURCE_XIAOYI } from './AgentIngestRequest';
import type { IngestBatchResult } from './AgentIngestRequest';
import { a2aErrorText } from './A2AErrorTaxonomy';
import type { A2AErrorCode } from './A2AErrorTaxonomy';
import { IngestGateway, INGEST_MODE_INLINE } from './IngestGateway';
import { A2AConversationStore, matchesRememberIntent } from './A2AConversationStore';
import type { A2AConversationTurn } from './A2AConversationStore';
import { A2AContextCleanup } from './A2AContextCleanup';
import { A2AImageContextStore } from './A2AImageContextStore';
import type { A2AImageMaterial } from './A2AImageContextStore';
import { hasIngestIntent } from './A2AIntentRouter';
import {
  A2APlan,
  A2APlanCommand,
  A2APlanItem,
  PLAN_CMD_ALL,
  PLAN_CMD_CANCEL,
  PLAN_CMD_INDEX,
  PLAN_CMD_START,
  buildA2APlanItems,
  formatA2APlanProgress,
  formatA2APlanSummary,
  nextPlanItem,
  parseA2APlanCommand,
  remainingPlanCount,
  reviewCountOf,
} from './A2APlanModels';
import { A2APlanStore } from './A2APlanStore';
import {
  A2AIntent,
  INTENT_EMPTY,
  INTENT_IMAGE_QA,
  INTENT_OCR,
  INTENT_PICK_CARD,
  INTENT_PLAN_CONTINUE,
  INTENT_PLAN_WAITING,
  INTENT_PROBE,
  INTENT_TEXT_INGEST,
  routeA2AIntent,
} from './A2AIntentRouter';
import { AgentImagePart, AgentPart, collectImageParts, joinTextParts } from './AgentImageParts';
import { OcrService } from './OcrService';
import { A2AChatContext, A2AChatContextResult } from './A2AChatContext';
import type { NoteEvidenceContext } from 'common';
import { IntentClassifier, ReplyContext, ReplyService } from 'agents/src/main/ets/chat/Index';
import type { LlmCallPolicy, ReplyStyle } from 'agents/src/main/ets/chat/Index';



/** 错误码/分类/文案统一在 A2AErrorTaxonomy；这里只保留入库 deadline。 */

/** 单次请求的预算与状态：保证 deadline 只取消一次、timeout 只发一次 */

/** 扩展适配器交给控制器的请求形状（协议字段已解析完）。 */
export interface A2ARequestInput {
  requestId: string;
  taskId: string;
  contextId: string;
  query: string;
  parts: AgentPart[];
}

/** 控制器回话端口：由 AgentExtAbility 实现，负责拼单帧快照并 sendData。 */
export interface A2AReplyPort {
  send(taskId: string, text: string, requestStartedAt: number): void;
}

/** 扩展进程内的模型配置初始化（只做一次），runQuery 前必须等它 */
let configReady: Promise<void> | null = null;

export class A2AController {
  private readonly context: common.Context;
  private readonly reply: A2AReplyPort;
  /** 当前请求的 jsonrpc id，仅用于 settle 日志（快照回填由 AgentExtAbility 负责） */
  private currentRequestIdValue: string = '';
  /** 当前在跑的请求：新请求重入或 onDestroy 时用它取消 token / 清 deadline */
  private activeSession: A2ARequestSession | null = null;
  private readonly ingestHandler: A2AIngestHandler;
  private readonly answerHandler: A2AAnswerHandler;

  constructor(context: common.Context, reply: A2AReplyPort) {
    this.context = context;
    this.reply = reply;
    this.ingestHandler = new A2AIngestHandler(this);
    this.answerHandler = new A2AAnswerHandler(this);
  }

  ingestContext(): common.Context {
    return this.context;
  }

  answerContext(): common.Context {
    return this.context;
  }

  finishSession(session: A2ARequestSession, code: A2AErrorCode, text: string, reason: string): void {
    this.settle(session, code, text, reason);
  }

  failSession(session: A2ARequestSession, e: Error): void {
    this.handleFailure(session, e);
  }

  currentRequestId(): string {
    return this.currentRequestIdValue;
  }

  configReady(): Promise<void> | null {
    return configReady;
  }

  sendIngestAnswer(taskId: string, text: string, requestStartedAt: number): void {
    this.sendAnswer(taskId, text, requestStartedAt);
  }

  /** 组合根调用：日志策略、初始化 DB 与 LlmConfig；不安装 OCR（那是 AgentExtAbility 的职责）。 */
  prepare(): void {
    hilog.info(DOMAIN, TAG,
      'A2A policy config=%{public}d attempts=%{public}d inner=%{public}d backoff=%{public}d margin=%{public}d deadline=%{public}d budget=%{public}d taskNeed=%{public}d',
      A2A_POLICY.configTimeoutMs, a2aAttempts(), A2A_POLICY.requestTimeoutMs, A2A_POLICY.backoffMs,
      A2A_POLICY.marginMs, A2A_POLICY.deadlineMs, a2aBudgetMs(), A2A_POLICY.taskNeedTokens);
    if (a2aBudgetMs() !== A2A_POLICY.deadlineMs) {
      hilog.warn(DOMAIN, TAG, 'A2A budget mismatch budget=%{public}d deadline=%{public}d',
        a2aBudgetMs(), A2A_POLICY.deadlineMs);
    }
    // 扩展进程独立于 UI 进程，模型配置必须在这里重新初始化，否则会用默认 endpoint
    // 扩展进程初始化同一个 DB：聊天证据（RAG）与内联整理都需要，否则 A2A_EVIDENCE 恒为 store-not-ready。
    DatabaseHelper.init(this.context).catch((e: Error) => {
      hilog.warn(DOMAIN, TAG, 'DB init failed %{public}s', e.message);
    });
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
    // R6：A2A 会话 / 图片 / 计划文件按 7 天保留，避免 contextId 维度无限增长。
    A2AContextCleanup.run(this.context);
  }

  /**
   * 作废当前在途请求：先标记已应答，再取消 token。
   * LlmClient 的 onCancel 监听会 httpRequest.destroy()，不会留下后台僵尸请求。
   */
  cancelActive(): void {
    const session: A2ARequestSession | null = this.activeSession;
    if (session === null) {
      return;
    }
    session.responded = true;
    clearTimeout(session.deadlineTimer);
    session.token.cancel();
    this.activeSession = null;
  }

  /** 请求入口：取消上一轮 → 解析图片/文本 → 读计划 → 意图路由 → 分派。 */
  handle(input: A2ARequestInput): void {
    this.cancelActive();
    this.currentRequestIdValue = input.requestId;
    const parts: AgentPart[] = input.parts;
    const images: AgentImagePart[] = collectImageParts(parts);
    const query: string = input.query;
    const text: string = query.length > 0 ? query : joinTextParts(parts);
    const ingest: AgentIngestRequest = buildIngestRequest(INGEST_SOURCE_XIAOYI, text, images);
    const conversationKey: string = A2AConversationStore.keyOf(input.taskId, input.contextId);
    hilog.info(DOMAIN, TAG, 'id=%{public}s taskId=%{public}s ctxKey=%{public}s query=%{public}s',
      input.requestId, input.taskId.length > 0 ? input.taskId : 'none', conversationKey, query);

    A2APlanStore.load(this.context, input.taskId)
      .then((plan: A2APlan | null): void => {
        const intent: A2AIntent = routeA2AIntent(text, images.length > 0, plan !== null);
        hilog.info(DOMAIN, TAG, 'INTENT kind=%{public}s reason=%{public}s',
          intent.kind, intent.reason);
        if (intent.kind === INTENT_PROBE) {
          OcrService.probe(this.context).then((r: string): void => {
            this.sendAnswer(input.taskId, 'OCR 探针：' + r, 0);
          });
          return;
        }
        if (intent.kind === INTENT_PLAN_CONTINUE && plan !== null) {
          this.ingestHandler.handlePlanTurn(input.taskId, text, plan);
          return;
        }
        if (intent.kind === INTENT_PLAN_WAITING && plan !== null) {
          this.sendAnswer(input.taskId, '当前有整理计划（共 ' + plan.items.length.toString() + ' 题，已完成 '
            + plan.done.length.toString() + ' 题）。回复「继续」/「第 N 题」/「全部」/「取消」。', 0);
          return;
        }
        if (intent.kind === INTENT_OCR) {
          this.handleOcrCheckpoint(input.taskId, ingest);
          return;
        }
        if (intent.kind === INTENT_IMAGE_QA) {
          this.handleImageQuestion(input.taskId, ingest, conversationKey);
          return;
        }
        if (intent.kind === INTENT_PICK_CARD || intent.kind === INTENT_EMPTY) {
          if (intent.kind === INTENT_EMPTY || intent.reason === 'ingest-without-content'
            || hasIngestIntent(text)) {
            this.answerWithLastImageMaterial(input.taskId, conversationKey);
            return;
          }
          this.sendAnswer(input.taskId, '直接把题目图片或文字发我即可；说「整理成笔记」我会在小艺里直接整理，不需要打开 App。', 0);
          return;
        }
        if (intent.kind === INTENT_TEXT_INGEST) {
          this.ingestHandler.handleTextPlanMessage(input.taskId, ingest);
          return;
        }
        this.runQuery(input.taskId, query, conversationKey);
      })
      .catch((e: Error): void => {
        hilog.error(DOMAIN, TAG, 'INTENT_ROUTE_FAILED %{public}s', e.message);
        this.runQuery(input.taskId, query, conversationKey);
      });
  }

  /** 图片问答：OCR 识别图片文字后直接回答用户问题，不入库（整理意图仍走 OCR/计划）。 */
  private handleImageQuestion(taskId: string, request: AgentIngestRequest, conversationKey: string): void {
    hilog.info(DOMAIN, TAG, 'IMAGE_QA start images=%{public}d chars=%{public}d',
      request.images.length, request.text.length);
    this.recognizeImages(request.images)
      .then((recognized: string): void => {
        const text: string = recognized.trim();
        if (text.length === 0) {
          this.sendAnswer(taskId, '图片里没识别到文字，换清晰点的图，或直接把题目文字发我。', 0);
          return;
        }
        A2AImageContextStore.save(this.context, conversationKey, text).catch((): void => {});
        const excerpt: string = text.length > 2000 ? text.substring(0, 2000) : text;
        const question: string = request.text.trim().length > 0
          ? request.text.trim() : '请回答图片中的题目';
        const prompt: string = '用户发来一张图片，OCR 识别到的文字如下：\n'
          + excerpt + '\n\n用户的问题：' + question
          + '\n\n请直接回答用户的问题（讲解思路/答案/易错点）。'
          + '不要输出笔记整理模板；如果用户需要整理成笔记，可以回复「整理成笔记」。';
        hilog.info(DOMAIN, TAG, 'IMAGE_QA ocrChars=%{public}d', text.length);
        this.runQuery(taskId, prompt, conversationKey);
      })
      .catch((e: Error): void => {
        hilog.error(DOMAIN, TAG, 'IMAGE_QA failed %{public}s', e.message);
        this.sendAnswer(taskId, '图片识别失败，换清晰点的图，或直接把题目文字发我。', 0);
      });
  }

  /** 依次 OCR 图片（最多 3 张），返回拼接文字。 */
  private async recognizeImages(images: AgentImagePart[]): Promise<string> {
    const texts: string[] = [];
    const limit: number = images.length > 3 ? 3 : images.length;
    for (let i = 0; i < limit; i += 1) {
      const image: AgentImagePart = images[i];
      let text: string = '';
      if (image.kind === 'uri') {
        text = await OcrService.recognizeUri(image.value);
      } else {
        text = await OcrService.recognizeBase64(image.value);
      }
      if (text.trim().length > 0) {
        texts.push(text.trim());
      }
    }
    return texts.join('\n');
  }

  /** 意图=OCR：先用文字识别工具把图转文字并按题规划，回 checkpoint 摘要；用户「继续」才入库。 */
  private handleOcrCheckpoint(taskId: string, request: AgentIngestRequest): void {
    hilog.info(DOMAIN, TAG, 'OCR_CHECKPOINT start images=%{public}d chars=%{public}d',
      request.images.length, request.text.length);
    IngestGateway.plan(request)
      .then((items: A2APlanItem[] | null): void => {
        if (items === null || items.length === 0) {
          this.sendAnswer(taskId, '这几张图没识别出文字，换清晰点的，或直接把题目文字发我。', 0);
          return;
        }
        const plan: A2APlan = { taskId: taskId, createdAt: Date.now(), items: items, done: [] };
        hilog.info(DOMAIN, TAG, 'OCR_CHECKPOINT items=%{public}d', items.length);
        A2APlanStore.save(this.context, plan.taskId, plan)
          .then((): void => {
            this.sendAnswer(taskId, formatA2APlanSummary(plan), 0);
          })
          .catch((e: Error): void => {
            hilog.warn(DOMAIN, TAG, 'PLAN_SAVE_FAILED %{public}s', e.message);
            this.sendAnswer(taskId, formatA2APlanSummary(plan), 0);
          });
      })
      .catch((e: Error): void => {
        hilog.error(DOMAIN, TAG, 'OCR_CHECKPOINT failed %{public}s', e.message);
        this.sendAnswer(taskId, '图片识别失败，换清晰点的图，或直接把题目文字发我。', 0);
      });
  }

  /** 文本整理入口：持久化开启 → 入队并回执已受理；否则走原有同步 ingestTextBatch。 */
  private runQuery(taskId: string, query: string, conversationKey: string = 'default'): void {
    // 回执意图本地判定：命中就读落盘事实，不等待 configReady、不调 ReplyService、不判 LlmConfig
    if (matchesReceiptIntent(query)) {
      this.answerFromReceipt(taskId);
      return;
    }
    // 「上一条说了什么」类问题：直接读会话记忆确定性回答（模型偶尔会忽略 memoryContext）。
    if (matchesRememberIntent(query)) {
      this.answerFromConversationMemory(taskId, conversationKey);
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
      conversationKey: conversationKey,
    };
    this.activeSession = session;

    session.deadlineTimer = setTimeout((): void => {
      if (session.responded) {
        return;
      }
      // 同一个 token 贯穿 ReplyService → LlmGuard → LlmClient；
      // LlmClient 的 onCancel 监听会 request.destroy()，不留后台僵尸请求。
      session.token.cancel();
      this.settle(session, 'A2A_DEADLINE_EXCEEDED', a2aErrorText('A2A_DEADLINE_EXCEEDED'),
        'deadline ' + A2A_POLICY.deadlineMs.toString() + 'ms');
    }, A2A_POLICY.deadlineMs);

    // P0-1：复用 App 对话同款 RAG——先检索本机笔记证据，再交给 ReplyService（超时降级为空）。
    A2AConversationStore.loadWithFallback(this.context, conversationKey)
      .then((turns: A2AConversationTurn[]): Promise<A2AChatContextResult> => {
        const memory: string = A2AConversationStore.format(turns);
        hilog.info(DOMAIN, TAG, 'A2A_MEMORY key=%{public}s turns=%{public}d chars=%{public}d',
          conversationKey, turns.length, memory.length);
        return A2AChatContext.build(query, memory);
      })
      .then((built: A2AChatContextResult): void => {
        session.evidence = built.evidence;
        hilog.info(DOMAIN, TAG, 'A2A_EVIDENCE citations=%{public}d degraded=%{public}d reason=%{public}s',
          built.citations, built.degraded ? 1 : 0, built.reason);
        if (session.responded) {
          return;
        }
        this.answerHandler.awaitConfig()
          .then((ready: boolean): void => {
            if (session.responded) {
              return;
            }
            if (!ready) {
              // 配置没能读到，用当前缓存值（可能是默认值）尽量补齐审计字段。
              this.answerHandler.fillModelFieldsFromCachedConfig(session);
              this.settle(session, 'A2A_CONFIG_READ_TIMEOUT',
                a2aErrorText('A2A_CONFIG_READ_TIMEOUT', A2A_POLICY.configTimeoutMs.toString()),
                'config wait exceeded ' + A2A_POLICY.configTimeoutMs.toString() + 'ms');
              return;
            }
            this.answerHandler.answerWithResolvedModel(session, built.replyContext);
          })
          .catch((e: Error): void => {
            if (session.responded) {
              return;
            }
            this.handleFailure(session, e);
          });
      })
      .catch((e: Error): void => {
        if (session.responded) {
          return;
        }
        this.handleFailure(session, e);
      });
  }

  /** 确定性回答「上一轮」：直接读最近一轮，不调模型，避免模型说“看不到上下文”。 */
  private answerFromConversationMemory(taskId: string, conversationKey: string): void {
    A2AConversationStore.loadWithFallback(this.context, conversationKey)
      .then((turns: A2AConversationTurn[]): void => {
        if (turns.length === 0) {
          this.sendAnswer(taskId, '我这边还没有上一轮对话的记录。你可以先发一道题或问题，我再记住。', 0);
          return;
        }
        const last: A2AConversationTurn = turns[turns.length - 1];
        const userText: string = last.user.length > 160 ? last.user.substring(0, 160) + '…' : last.user;
        const answerText: string = last.assistant.length > 240
          ? last.assistant.substring(0, 240) + '…' : last.assistant;
        this.sendAnswer(taskId,
          '你上一条消息是：「' + userText + '」。\n\n我当时回答的是：「' + answerText + '」。', 0);
      })
      .catch((e: Error): void => {
        hilog.warn(DOMAIN, TAG, 'A2A_MEMORY_RECALL_FAILED %{public}s', e.message);
        this.sendAnswer(taskId, '读取上一轮对话失败，请重试。', 0);
      });
  }

  /** 「整理成笔记」但本条没带图：用最近一张图的 OCR 文本直接内联整理（无需打开 App）。 */
  private answerWithLastImageMaterial(taskId: string, conversationKey: string): void {
    A2AImageContextStore.load(this.context, conversationKey)
      .then((material: A2AImageMaterial | null): void => {
        if (material === null) {
          this.sendAnswer(taskId,
            '我在小艺里收不到图片本身（小艺不会把图片转给智能体）。'
              + '你可以直接把题目文字发我；如果小艺已经识别出图片文字，把那段文字引用/粘贴过来并说「整理笔记」，我就能整理入库。', 0);
          return;
        }
        hilog.info(DOMAIN, TAG, 'IMAGE_RECALL ingest chars=%{public}d', material.text.length);
        const ingest: AgentIngestRequest = buildIngestRequest(INGEST_SOURCE_XIAOYI, material.text, []);
        this.ingestHandler.ingestTextBatchNow(taskId, ingest);
      })
      .catch((e: Error): void => {
        hilog.warn(DOMAIN, TAG, 'IMAGE_RECALL failed %{public}s', e.message);
        this.sendAnswer(taskId, '读取上次图片内容失败，请重发图片。', 0);
      });
  }

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
  private handleFailure(session: A2ARequestSession, e: Error): void {
    const reason: string = e instanceof Error && e.message.length > 0 ? e.message : String(e);
    if (session.token.isCancelled() || reason === 'CONVERSATION_CANCELLED') {
      // deadline 定时器通常已经 settle；这里兜底仍只发一次。
      this.settle(session, 'A2A_DEADLINE_EXCEEDED', a2aErrorText('A2A_DEADLINE_EXCEEDED'), 'cancelled: ' + reason);
      return;
    }
    // 单次模型调用的 25s 连接/读取超时：平台可能报 TIMEOUT，也可能包成 NETWORK_ERROR。
    const modelElapsed: number = session.requestStartedAt > 0
      ? Date.now() - session.requestStartedAt : 0;
    const timedOut: boolean = e instanceof LlmError
      && (e.kind === 'TIMEOUT' || e.kind === 'STREAM_FAILED'
        || (e.kind === 'NETWORK_ERROR' && modelElapsed >= A2A_POLICY.requestTimeoutMs));
    if (timedOut) {
      this.settle(session, 'A2A_LLM_TIMEOUT', a2aErrorText('A2A_LLM_TIMEOUT'), reason);
      return;
    }
    hilog.error(DOMAIN, TAG, 'LLM 调用失败: %{public}s', reason);
    this.settle(session, 'A2A_LLM_FAILED', a2aErrorText('A2A_LLM_FAILED', reason), reason);
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
      code, this.currentRequestIdValue, session.taskId, session.requestedModel, session.canonicalModel,
      reason, session.attempts, elapsedMs);
    this.sendAnswer(session.taskId, text, session.requestStartedAt);
  }

  /** 控制器唯一回话出口：交给扩展适配器拼快照并发送。 */
  private sendAnswer(taskId: string, text: string, requestStartedAt: number): void {
    this.reply.send(taskId, text, requestStartedAt);
  }
}
