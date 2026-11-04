/**
 * A2AIngestHandler.ets — 小艺端A2A 的整理与计划推进
 *
 * 路径: entry/src/main/ets/services/A2AIngestHandler.ets
 * 职责: 文本整理的批处理、90s deadline、多题计划（继续/第 N 题/全部/取消）、
 *       入队兜底与回执记录
 * 依赖: ./IngestGateway、A2APlanStore、A2AConversationStore、common
 *
 * 数据流:
 *   A2AController.handle → 本处理器 → IngestGateway(INLINE) → 单帧回话
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
import { DOMAIN, INGEST_DEADLINE_MS, TAG } from './A2AConstants';
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

export interface IA2AIngestHost {
  ingestContext(): common.Context;
  sendIngestAnswer(taskId: string, text: string, requestStartedAt: number): void;
}

export class A2AIngestHandler {
  private readonly host: IA2AIngestHost;

  constructor(host: IA2AIngestHost) {
    this.host = host;
  }

  handleTextPlanMessage(taskId: string, request: AgentIngestRequest): void {
    A2APlanStore.load(this.host.ingestContext(), taskId)
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
          A2APlanStore.save(this.host.ingestContext(), plan.taskId, plan)
            .then((): void => {
              this.host.sendIngestAnswer(taskId, formatA2APlanSummary(plan), 0);
            })
            .catch((e: Error): void => {
              hilog.warn(DOMAIN, TAG, 'PLAN_SAVE_FAILED %{public}s', e.message);
              this.host.sendIngestAnswer(taskId, formatA2APlanSummary(plan), 0);
            });
          return;
        }
        this.dispatchTextBatch(taskId, request);
      })
      .catch((e: Error): void => {
        hilog.error(DOMAIN, TAG, 'PLAN_LOAD_FAILED %{public}s', e.message);
        this.enqueueForIngest(taskId, request.text);
      });
  }

  /** 有未完成计划时：解析「继续 / 第 N 题 / 全部 / 取消」，逐题推进。 */
  handlePlanTurn(taskId: string, query: string, plan: A2APlan): void {
    const command: A2APlanCommand = parseA2APlanCommand(query);
    if (command.kind === PLAN_CMD_CANCEL) {
      A2APlanStore.clear(this.host.ingestContext(), taskId).catch((): void => {});
      this.host.sendIngestAnswer(taskId, '已取消这次整理计划，没有写入新笔记。', 0);
      return;
    }
    if (command.kind === PLAN_CMD_ALL) {
      const pendingItems: A2APlanItem[] = [];
      for (let i = 0; i < plan.items.length; i += 1) {
        if (plan.done.indexOf(plan.items[i].index) < 0) {
          pendingItems.push(plan.items[i]);
        }
      }
      A2APlanStore.clear(this.host.ingestContext(), taskId).catch((): void => {});
      this.ingestPendingItemsSequentially(taskId, pendingItems);
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
        this.host.sendIngestAnswer(taskId, '没有第 ' + command.index.toString() + ' 题，当前共 '
          + plan.items.length.toString() + ' 题。', 0);
        return;
      }
    } else if (command.kind === PLAN_CMD_START) {
      item = nextPlanItem(plan);
    }
    if (item === undefined) {
      if (remainingPlanCount(plan) === 0) {
        A2APlanStore.clear(this.host.ingestContext(), taskId).catch((): void => {});
        this.host.sendIngestAnswer(taskId, '这次计划里的题都整理完了 ✅', 0);
        return;
      }
      this.host.sendIngestAnswer(taskId, '当前有整理计划（共 ' + plan.items.length.toString() + ' 题，已完成 '
        + plan.done.length.toString() + ' 题）。回复「继续」/「第 N 题」/「全部」/「取消」。', 0);
      return;
    }
    this.ingestPlanItem(taskId, plan, item);
  }

  /** 单题入库 deadline：超时抛 INGEST_DEADLINE，由调用方转待整理队列。 */
  private ingestWithDeadline(text: string): Promise<NoteOutcome> {
    return new Promise<NoteOutcome>((resolve: (value: NoteOutcome) => void,
      reject: (reason: Error) => void): void => {
      let settled: boolean = false;
      const timer: number = setTimeout((): void => {
        if (settled) {
          return;
        }
        settled = true;
        hilog.warn(DOMAIN, TAG, 'INGEST_DEADLINE exceeded ms=%{public}d', INGEST_DEADLINE_MS);
        reject(new Error('INGEST_DEADLINE: ' + INGEST_DEADLINE_MS.toString() + 'ms'));
      }, INGEST_DEADLINE_MS);
      IngestGateway.ingestText(this.host.ingestContext(), text, INGEST_SOURCE_XIAOYI, INGEST_MODE_INLINE)
        .then((result: IngestBatchResult): void => {
          if (settled) {
            return;
          }
          if (result.outcomes.length === 0) {
            settled = true;
            clearTimeout(timer);
            reject(new Error('INGEST_EMPTY_OUTCOME'));
            return;
          }
          settled = true;
          clearTimeout(timer);
          resolve(result.outcomes[0]);
        })
        .catch((error: Error): void => {
          if (settled) {
            return;
          }
          settled = true;
          clearTimeout(timer);
          reject(error);
        });
    });
  }

  /** 整理计划中的一道题：按 ADR-0024 §2.7 在扩展进程内联执行；超时/失败回退 inbox。 */
  private ingestPlanItem(taskId: string, plan: A2APlan, item: A2APlanItem): void {
    // 用户逐题确认后：直接在小艺里内联整理（无需打开 App）；超时/失败回退 inbox。
    this.ingestPlanItemNow(taskId, plan, item);
  }
  private ingestPlanItemNow(taskId: string, plan: A2APlan, item: A2APlanItem): void {
    hilog.info(DOMAIN, TAG, 'PLAN_INGEST item=%{public}d chars=%{public}d',
      item.index, item.text.length);
    this.ingestWithDeadline(item.text)
      .then((outcome: NoteOutcome): void => {
        if (outcome.kind === 'committed') {
          const unit: KnowledgeUnit | undefined = outcome.unit;
          plan.done.push(item.index);
          A2APlanStore.save(this.host.ingestContext(), plan.taskId, plan).catch((): void => {});
          this.recordA2aIngestReceipt();
          const title: string = unit !== undefined ? unit.title : '已存在的笔记';
          const subject: string = unit !== undefined ? unit.subject : '';
          this.host.sendIngestAnswer(taskId, formatA2APlanProgress(plan, item, title, subject), 0);
          return;
        }
        hilog.error(DOMAIN, TAG, 'PLAN_INGEST failed kind=%{public}s', outcome.kind);
        this.host.sendIngestAnswer(taskId, '第 ' + (item.index + 1).toString()
          + ' 题这次没整理成，回复「继续」重试，或「取消」。', 0);
      })
      .catch((e: Error): void => {
        hilog.error(DOMAIN, TAG, 'PLAN_INGEST exception %{public}s', e.message);
        if (e.message.indexOf('INGEST_DEADLINE') >= 0) {
          this.enqueueTexts([item.text]);
          this.host.sendIngestAnswer(taskId, a2aErrorText('A2A_INGEST_TIMEOUT'), 0);
          return;
        }
        this.host.sendIngestAnswer(taskId, '第 ' + (item.index + 1).toString()
          + ' 题这次没整理成，回复「继续」重试，或「取消」。', 0);
      });
  }

  /** 处理「文字多题」结果：第 1 题同步回执，剩余题入待整理队列（app 前台补跑）。 */
  private handleTextBatch(taskId: string, request: AgentIngestRequest, batch: IngestBatchResult): void {
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
        this.host.sendIngestAnswer(taskId,
          '已整理入库：' + unit.title + '（' + unit.subject + '）。本次识别 ' + batch.totalProblems.toString()
            + ' 道题，已入第 1 道；其余 ' + batch.queuedTexts.length.toString()
            + ' 道已转待整理，打开 MindTrace 会自动补齐。', 0);
        return;
      }
      this.host.sendIngestAnswer(taskId,
        '已整理入库：' + unit.title + '（' + unit.subject + '）· 本次整理 1 条', 0);
      return;
    }
    if (outcome.kind === 'committed') {
      // 幂等复用可能只回 noteId（没有 unit）；committed 就是成功，不能报失败。
      const noteId: string = outcome.noteId !== undefined ? outcome.noteId : '';
      hilog.info(DOMAIN, TAG, 'INGEST_TEXT reused noteId=%{public}s', noteId);
      this.recordA2aIngestReceipt();
      if (batch.totalProblems > 1) {
        this.enqueueTexts(batch.queuedTexts);
        this.host.sendIngestAnswer(taskId,
          '已整理过：这条内容已在知识库里（笔记 ' + noteId + '）。本次识别 ' + batch.totalProblems.toString()
            + ' 道题，已入第 1 道；其余 ' + batch.queuedTexts.length.toString()
            + ' 道已转待整理，打开 MindTrace 会自动补齐。', 0);
        return;
      }
      this.host.sendIngestAnswer(taskId, '已整理过：这条内容已在知识库里（笔记 ' + noteId + '）· 本次整理 1 条', 0);
      return;
    }
    if (outcome.kind === 'cancelled') {
      const cancelledText: string = outcome.committed === true
        ? '这次整理已落库，但随后被取消了；笔记已保存，可在应用里查看。'
        : '这次整理已取消，没有写入笔记。';
      this.host.sendIngestAnswer(taskId, cancelledText, 0);
      return;
    }
    const code: string = outcome.code !== undefined ? outcome.code : 'INGEST_FAILED';
    if (outcome.retryable === true) {
      this.enqueueTexts(batch.totalProblems > 1 ? batch.queuedTexts : [request.text]);
      this.enqueueForIngest(taskId, request.text);
      return;
    }
    this.host.sendIngestAnswer(taskId, a2aErrorText('A2A_INGEST_FAILED', code), 0);
  }

  /** 「全部」：在小艺里逐题内联整理，每题一条进度回执（无需打开 App）。 */
  ingestTextBatchNow(taskId: string, request: AgentIngestRequest): void {
    this.ingestBatchWithDeadline(request)
      .then((batch: IngestBatchResult): void => {
        this.handleTextBatch(taskId, request, batch);
      })
      .catch((e: Error): void => {
        hilog.error(DOMAIN, TAG, 'INGEST_TEXT_BATCH failed %{public}s', e.message);
        if (e.message.indexOf('INGEST_DEADLINE') >= 0) {
          this.enqueueTexts([request.text]);
          this.host.sendIngestAnswer(taskId, a2aErrorText('A2A_INGEST_TIMEOUT'), 0);
          return;
        }
        this.enqueueForIngest(taskId, request.text);
      });
  }

  /**
   * 文本批量整理 deadline：provider 挂起时不再让用户无限等；超时转待整理。
   * 底层请求不取消（IngestGateway 未暴露 token），但其结果会被 settled 守卫丢弃；
   * 随后入库的同一文本由输入指纹/commitKey 幂等去重。
   */
  private ingestBatchWithDeadline(request: AgentIngestRequest): Promise<IngestBatchResult> {
    return new Promise<IngestBatchResult>((resolve: (value: IngestBatchResult) => void,
      reject: (reason: Error) => void): void => {
      let settled: boolean = false;
      const timer: number = setTimeout((): void => {
        if (settled) {
          return;
        }
        settled = true;
        hilog.warn(DOMAIN, TAG, 'INGEST_TEXT_DEADLINE exceeded ms=%{public}d', INGEST_DEADLINE_MS);
        reject(new Error('INGEST_DEADLINE: ' + INGEST_DEADLINE_MS.toString() + 'ms'));
      }, INGEST_DEADLINE_MS);
      IngestGateway.ingest(this.host.ingestContext(), request, INGEST_MODE_INLINE)
        .then((result: IngestBatchResult): void => {
          if (settled) {
            return;
          }
          settled = true;
          clearTimeout(timer);
          resolve(result);
        })
        .catch((error: Error): void => {
          if (settled) {
            return;
          }
          settled = true;
          clearTimeout(timer);
          reject(error);
        });
    });
  }
  private dispatchTextBatch(taskId: string, request: AgentIngestRequest): void {
    // 用户有整理意图：在扩展进程内联完成（无需打开 App）；超时/失败仍回退 inbox/持久队列。
    this.ingestTextBatchNow(taskId, request);
  }
  private ingestPendingItemsSequentially(taskId: string, items: A2APlanItem[]): void {
    if (items.length === 0) {
      this.host.sendIngestAnswer(taskId, '这次计划里的题都整理完了 ✅', 0);
      return;
    }
    this.host.sendIngestAnswer(taskId, '开始逐题整理，共 ' + items.length.toString()
      + ' 题（在小艺里直接完成，可随时回复「取消」）。', 0);
    const runNext = (index: number): void => {
      if (index >= items.length) {
        this.host.sendIngestAnswer(taskId, '剩余 ' + items.length.toString() + ' 题已全部整理完成 ✅', 0);
        return;
      }
      const item: A2APlanItem = items[index];
      this.ingestWithDeadline(item.text)
        .then((outcome: NoteOutcome): void => {
          if (outcome.kind === 'committed') {
            const unit: KnowledgeUnit | undefined = outcome.unit;
            this.recordA2aIngestReceipt();
            const summary: string = unit !== undefined
              ? unit.title + '（' + unit.subject + '）' : '已存在的笔记';
            this.host.sendIngestAnswer(taskId, '（' + (index + 1).toString() + '/' + items.length.toString()
              + '）已整理：' + summary, 0);
          } else {
            this.enqueueTexts([item.text]);
            this.host.sendIngestAnswer(taskId, '（' + (index + 1).toString() + '/' + items.length.toString()
              + '）这题没整理成，已转待整理。', 0);
          }
          runNext(index + 1);
        })
        .catch((): void => {
          this.enqueueTexts([item.text]);
          this.host.sendIngestAnswer(taskId, '（' + (index + 1).toString() + '/' + items.length.toString()
            + '）超时，已转待整理。', 0);
          runNext(index + 1);
        });
    };
    runNext(0);
  }

  /** 剩余题逐条追加待整理队列（尽力而为，失败只记日志）。 */
  private enqueueTexts(texts: string[]): void {
    for (let i = 0; i < texts.length; i += 1) {
      AgentInboxQueue.append(this.host.ingestContext(), buildInboxItem(texts[i], Date.now() + i))
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
    CaptureReceiptStore.read(this.host.ingestContext()).then((prev: CaptureReceipt | null): void => {
      const receipt: CaptureReceipt = {
        done: (prev !== null ? prev.done : 0) + 1,
        failed: prev !== null ? prev.failed : 0,
        total: (prev !== null ? prev.total : 0) + 1,
        at: Date.now(),
        source: 'a2a',
      };
      CaptureReceiptStore.save(this.host.ingestContext(), receipt).catch((e: Error): void => {
        hilog.warn(DOMAIN, TAG, 'RECEIPT_SAVE_FAILED %{public}s', e.message);
      });
    }).catch((e: Error): void => {
      hilog.warn(DOMAIN, TAG, 'RECEIPT_READ_FAILED %{public}s', e.message);
    });
  }
  private enqueueForIngest(taskId: string, query: string): void {
    const item: AgentInboxItem = buildInboxItem(query, Date.now());
    AgentInboxQueue.append(this.host.ingestContext(), item)
      .then((pending: number): void => {
        hilog.info(DOMAIN, TAG, 'INBOX_ENQUEUED pending=%{public}d chars=%{public}d',
          pending, item.text.length);
        this.host.sendIngestAnswer(taskId,
          '模型这次没通，已记为待整理（第 ' + pending.toString() + ' 条）。打开 MindTrace 会自动补上。', 0);
      })
      .catch((e: Error): void => {
        hilog.error(DOMAIN, TAG, 'INBOX_ENQUEUE_FAILED %{public}s', e.message);
        this.host.sendIngestAnswer(taskId, '这条笔记没排上队，再发一次？', 0);
      });
  }

  /** 从 onData 拿到有效 query 开始计时：4s 配置 + 25s 模型 + 6s 余量 = 35s。 */
}
