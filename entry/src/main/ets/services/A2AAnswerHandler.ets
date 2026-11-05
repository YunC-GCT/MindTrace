/**
 * A2AAnswerHandler.ets — 模型配置与回答调用
 *
 * 路径: entry/src/main/ets/services/A2AAnswerHandler.ets
 * 职责: 等待模型配置就绪、解析请求模型、构建 ReplyContext 并调用 ReplyService，
 *       把结果交回控制器落终态
 * 依赖: common（LlmConfig / ReplyContext）、./A2AErrorTaxonomy
 *
 * 数据流:
 *   A2AController.runQuery → 本处理器 → ReplyService → settle
 */
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
import type { A2ARequestSession } from './A2ASession';
import { A2A_POLICY, A2A_REPLY_STYLE, a2aAttempts, unicodeCharCount } from './A2AConstants';
import { A2AIngestHandler } from './A2AIngestHandler';
import { DOMAIN, INGEST_DEADLINE_MS, TAG } from './A2AConstants';
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

export interface IA2AAnswerHost {
  answerContext(): common.Context;
  configReady(): Promise<void> | null;
  finishSession(session: A2ARequestSession, code: A2AErrorCode, text: string, reason: string): void;
  failSession(session: A2ARequestSession, e: Error): void;
  currentRequestId(): string;
}

export class A2AAnswerHandler {
  private readonly host: IA2AAnswerHost;

  constructor(host: IA2AAnswerHost) {
    this.host = host;
  }

  awaitConfig(): Promise<boolean> {
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
      const ready: Promise<void> | null = this.host.configReady();
      if (ready === null) {
        // onCreate 还没跑：让 4s 计时器给出 A2A_CONFIG_READ_TIMEOUT。
        return;
      }
      ready.then((): void => {
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
  fillModelFieldsFromCachedConfig(session: A2ARequestSession): void {
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
  answerWithResolvedModel(session: A2ARequestSession, context: ReplyContext): void {
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
          this.host.finishSession(session, 'A2A_MODEL_ID_UNRESOLVED',
            a2aErrorText('A2A_MODEL_ID_UNRESOLVED', session.canonicalModel + '（' + resolved.reason + '）'),
            resolved.reason);
          return;
        }
        // 清单有该条目但不可用：显式降级到同 provider catalog 默认，并在回复里标注。
        const fallbackResolved: ResolvedModel = resolveModel(vendorId, catalog.defaultModelId);
        if (!fallbackResolved.usable) {
          this.host.finishSession(session, 'A2A_MODEL_UNUSABLE',
            a2aErrorText('A2A_MODEL_UNUSABLE', session.canonicalModel + '（' + resolved.reason + '）'),
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
        const safeAnswer: string = A2AChatContext.sanitize(session.evidence, answer);
        A2AConversationStore.append(this.host.answerContext(), session.conversationKey, session.query, safeAnswer)
          .then((): void => {
            hilog.info(DOMAIN, TAG, 'A2A_MEMORY_SAVED key=%{public}s', session.conversationKey);
          })
          .catch((e: Error): void => {
            hilog.warn(DOMAIN, TAG, 'A2A_MEMORY_SAVE_FAILED key=%{public}s err=%{public}s',
              session.conversationKey, e.message);
          });
        if (session.conversationKey !== 'default') {
          A2AConversationStore.append(this.host.answerContext(), 'default', session.query, safeAnswer)
            .catch((): void => {});
        }
        this.host.finishSession(session, 'A2A_REPLY_SENT', safeAnswer, reason);
      })
      .catch((e: Error): void => {
        if (session.responded) {
          return;
        }
        this.host.failSession(session, e);
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
      return a2aErrorText('A2A_MODEL_NOT_READY');
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
}
