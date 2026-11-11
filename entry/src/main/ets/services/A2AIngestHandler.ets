/**
 * A2AIngestHandler.ets — 小艺端A2A 的整理与计划推进
 *
 * 路径: entry/src/main/ets/services/A2AIngestHandler.ets
 * 职责: 文本整理的批处理、30s deadline、多题计划（继续/第 N 题/全部/取消）、
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
 * 写库模式（ADR-0024 §2.1/§2.7）: A2A 单次整理在 :agent 内联执行；文本批量 30s deadline，
 *   超时/失败/溢出回退 inbox/agent_job。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { A2A_DRAFT_SLOW_MS, A2A_DRAFT_TIMEOUT_MS, DOMAIN, INGEST_DEADLINE_MS, TAG } from './A2AConstants';
import type { common } from '@kit.AbilityKit';
import {
  CancellationToken,
  DatabaseHelper,
  getProviderCatalog,
  KnowledgeUnit,
  LlmConfig,
  LlmError,
  resolveModel,
  sourceFingerprint,
} from 'common';
import type { NoteDraftReadyEvent, NoteOutcome, ProviderCatalog, ResolvedModel, SourceFragment } from 'common';

import { AiService } from './AiService';
import { A2ADraftStore } from './A2ADraftStore';
import { formatA2ADraftReply } from './A2ADraftModels';
import type { A2ADraftRefine, A2APendingDraft } from './A2ADraftModels';

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

const DEFAULT_DRAFT_INSTRUCTION: string = '整理成数学笔记草稿：只整理内容本身，不要复述「存笔记」这类指令。'
  + '按题型使用标准章节（定理：陈述/条件/结论/证明思路/应用；概念：定义/性质/示例/相关概念；'
  + '公式：表达式/参数/适用范围/推导/备注；证明题：命题/已知/证明过程/关键思路/结论；'
  + '计算题：问题/步骤/答案/方法总结/常见错误）。';

export interface IA2AIngestHost {
  ingestContext(): common.Context;
  sendIngestAnswer(taskId: string, text: string, requestStartedAt: number): void;
  /** 长回复分块发送（artifactUpdate）；短回复仍走单帧。 */
  sendStreamingAnswer(taskId: string, text: string): void;
}

export class A2AIngestHandler {
  private readonly host: IA2AIngestHost;

  constructor(host: IA2AIngestHost) {
    this.host = host;
  }

  handleTextPlanMessage(taskId: string, request: AgentIngestRequest, conversationKey: string): void {
    A2APlanStore.load(this.host.ingestContext(), taskId)
      .then((existing: A2APlan | null): void => {
        if (existing !== null) {
          this.handlePlanTurn(taskId, request.text, existing, conversationKey);
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
        // 单题：先生成草稿，等用户「确认」再入库；不再直接写库。
        this.beginDraftCheckpoint(taskId, conversationKey, request);
      })
      .catch((e: Error): void => {
        hilog.error(DOMAIN, TAG, 'PLAN_LOAD_FAILED %{public}s', e.message);
        this.enqueueForIngest(taskId, request.text);
      });
  }

  /** 单题草稿：generateNoteDraft(light) → 质量门 → 落盘 → 返回标题/摘要/章节 + 确认提示。 */
  beginDraftCheckpoint(taskId: string, conversationKey: string, request: AgentIngestRequest,
    planTaskId?: string, planItemIndex?: number): void {
    const runId: string = 'a2a-draft-' + Date.now().toString() + '-'
      + Math.floor(Math.random() * 1000).toString();
    const token: CancellationToken = new CancellationToken();
    const sourceText: string = A2AIngestHandler.cleanDraftSource(request.text);
    hilog.info(DOMAIN, TAG, 'A2A_DRAFT begin key=%{public}s chars=%{public}d',
      conversationKey, sourceText.length);
    let historySources: SourceFragment[] = [];
    A2AConversationStore.load(this.host.ingestContext(), conversationKey)
      .then((turns: A2AConversationTurn[]): Promise<NoteDraftReadyEvent> => {
        // 计划项是自包含的题目文本，不混入对话历史，避免被旧笔记带偏。
        historySources = planItemIndex !== undefined
          ? [] : A2AIngestHandler.historySources(turns, conversationKey);
        hilog.info(DOMAIN, TAG, 'A2A_DRAFT history turns=%{public}d fragments=%{public}d',
          turns.length, historySources.length);
        return this.draftWithDeadline(runId, sourceText, historySources, token);
      })
      .then((event: NoteDraftReadyEvent): void => {
        if (!A2AIngestHandler.draftUseful(event, sourceText)) {
          throw new Error('draft-empty');
        }
        const draft: A2APendingDraft = {
          conversationKey: conversationKey,
          createdAt: Date.now(),
          event: event,
          sourceText: sourceText,
        };
        if (planItemIndex !== undefined) {
          // taskId 可能为空（计划文件按 default 落盘），空串也必须保存，否则确认时找不到计划。
          draft.planTaskId = planTaskId === undefined ? '' : planTaskId;
          draft.planItemIndex = planItemIndex;
        }
        A2ADraftStore.save(this.host.ingestContext(), draft).catch((): void => {});
        hilog.info(DOMAIN, TAG, 'A2A_DRAFT ready title=%{public}s runId=%{public}s',
          event.candidate.title, event.runId);
        this.host.sendIngestAnswer(taskId, formatA2ADraftReply(event), 0);
      })
      .catch((e: Error): void => {
        hilog.error(DOMAIN, TAG, 'A2A_DRAFT failed %{public}s', e.message);
        const reply: string = e.message.indexOf('A2A_DRAFT_TIMEOUT') >= 0
          ? a2aErrorText('A2A_INGEST_TIMEOUT') : a2aErrorText('A2A_INGEST_FAILED', e.message);
        this.enqueueForIngest(taskId, request.text, reply);
      });
  }

  /** 计划里的单题：先生成草稿，确认后保存并回写 plan.done。 */
  beginPlanDraftCheckpoint(taskId: string, conversationKey: string, plan: A2APlan,
    item: A2APlanItem): void {
    const request: AgentIngestRequest = buildIngestRequest(INGEST_SOURCE_XIAOYI, item.text, []);
    this.beginDraftCheckpoint(taskId, conversationKey, request, plan.taskId, item.index);
  }

  /** 草稿生成 deadline：LLM 挂起时 25s 内回执并转待整理，不无限等。 */
  private draftWithDeadline(runId: string, sourceText: string, history: SourceFragment[],
    token: CancellationToken, instruction: string = DEFAULT_DRAFT_INSTRUCTION,
    preferStandard: boolean = false): Promise<NoteDraftReadyEvent> {
    return new Promise<NoteDraftReadyEvent>((resolve: (value: NoteDraftReadyEvent) => void,
      reject: (reason: Error) => void): void => {
      let settled: boolean = false;
      const slowTimer: number = setTimeout((): void => {
        if (!settled) {
          hilog.warn(DOMAIN, TAG, 'A2A_DRAFT_SLOW ms=%{public}d runId=%{public}s',
            A2A_DRAFT_SLOW_MS, runId);
        }
      }, A2A_DRAFT_SLOW_MS);
      const timer: number = setTimeout((): void => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(slowTimer);
        token.cancel();
        hilog.warn(DOMAIN, TAG, 'A2A_DRAFT_TIMEOUT ms=%{public}d', A2A_DRAFT_TIMEOUT_MS);
        reject(new Error('A2A_DRAFT_TIMEOUT: ' + A2A_DRAFT_TIMEOUT_MS.toString() + 'ms'));
      }, A2A_DRAFT_TIMEOUT_MS);
      this.createDraftWithFallback(runId, sourceText, history, token, instruction, preferStandard)
        .then((event: NoteDraftReadyEvent): void => {
          if (settled) {
            return;
          }
          settled = true;
          clearTimeout(slowTimer);
          clearTimeout(timer);
          resolve(event);
        })
        .catch((e: Error): void => {
          if (settled) {
            return;
          }
          settled = true;
          clearTimeout(slowTimer);
          clearTimeout(timer);
          reject(e);
        });
    });
  }

  /** 先走 light（快）；草稿内容为空/复述原文时取消并改用 standard 重试。 */
  private async createDraftWithFallback(runId: string, sourceText: string,
    history: SourceFragment[], token: CancellationToken,
    instruction: string = DEFAULT_DRAFT_INSTRUCTION,
    preferStandard: boolean = false): Promise<NoteDraftReadyEvent> {
    const service: AiService = new AiService(this.host.ingestContext(), false);
    if (preferStandard) {
      // 「详细一点」直接走 standard；失败就保留旧草稿，不降级成更短版本。
      return await service.generateNoteDraftWithSources(
        runId + '-std', instruction, sourceText, history, token, undefined, undefined, 'standard');
    }
    const light: NoteDraftReadyEvent = await service.generateNoteDraftWithSources(
      runId, instruction, sourceText, history, token, undefined, undefined, 'light');
    if (A2AIngestHandler.draftUseful(light, sourceText)) {
      return light;
    }
    hilog.warn(DOMAIN, TAG, 'A2A_DRAFT light-empty retry=standard runId=%{public}s', runId);
    try {
      await service.cancelDraft(light.runId);
    } catch (e) {
      // 取消失败不阻塞重试；坏 run 只留在生成记录里。
    }
    return await service.generateNoteDraftWithSources(
      runId + '-std', instruction, sourceText, history, token, undefined, undefined, 'standard');
  }

  /** 至少有一节正文既不是空串、也不是原文复述，才算可用草稿。 */
  private static draftUseful(event: NoteDraftReadyEvent, sourceText: string): boolean {
    const draft = event.result.draft;
    if (draft === undefined) {
      return false;
    }
    const source: string = A2AIngestHandler.normalizeComparable(sourceText);
    let useful: number = 0;
    for (let i = 0; i < draft.sections.length; i += 1) {
      const text: string = A2AIngestHandler.normalizeComparable(draft.sections[i].content);
      if (text.length < 12) {
        continue;
      }
      if (source.length > 0 && text.indexOf(source) >= 0 && text.length <= source.length + 20) {
        continue;
      }
      useful += 1;
    }
    return useful > 0;
  }

  private static normalizeComparable(text: string): string {
    return text.replace(/\s+/g, '').replace(/[。，、；：]/g, '');
  }

  /** 「存笔记：」是入口指令，不是笔记内容；计划项前面的「1. 」也先剥掉。 */
  private static cleanDraftSource(text: string): string {
    const cleaned: string = text
      .replace(/^\s*(\d{1,2}\s*[.、)）]\s*)?/, '')
      .replace(/^\s*(存笔记|整理笔记|记笔记|整理成笔记)\s*[:：]?\s*/, '')
      .trim();
    return cleaned.length > 0 ? cleaned : text.trim();
  }

  /** 最近 3 轮对话作为生成资料；助手文本是模型生成，只作上下文，不当原始证据。 */
  private static historySources(turns: A2AConversationTurn[], conversationKey: string): SourceFragment[] {
    const sources: SourceFragment[] = [];
    const start: number = turns.length > 3 ? turns.length - 3 : 0;
    let sequence: number = 0;
    for (let i = start; i < turns.length; i += 1) {
      const turn: A2AConversationTurn = turns[i];
      const text: string = A2AIngestHandler.clipHistory(
        '用户：' + turn.user + '\n助手：' + turn.assistant, 1200);
      if (text.trim().length === 0) {
        continue;
      }
      sources.push({
        id: 'a2a-history-' + conversationKey + '-' + i.toString(),
        kind: 'conversation',
        originId: conversationKey,
        sequence: sequence,
        fingerprint: sourceFingerprint(text),
        text: text,
      });
      sequence += 1;
    }
    return sources;
  }

  private static clipHistory(text: string, limit: number): string {
    return text.length > limit ? text.substring(0, limit) : text;
  }

  /** 用户确认：把落盘草稿走正式 confirmDraft 入库。 */
  confirmPendingDraft(taskId: string, conversationKey: string, draft: A2APendingDraft): void {
    hilog.info(DOMAIN, TAG, 'A2A_DRAFT confirm key=%{public}s runId=%{public}s',
      conversationKey, draft.event.runId);
    const service: AiService = new AiService(this.host.ingestContext(), false);
    service.confirmDraft(draft.event, draft.event.candidate)
      .then((unit: KnowledgeUnit): void => {
        A2ADraftStore.clear(this.host.ingestContext(), conversationKey).catch((): void => {});
        this.recordA2aIngestReceipt();
        const reused: boolean = unit.id !== draft.event.candidate.id;
        if (draft.planTaskId !== undefined && draft.planItemIndex !== undefined) {
          this.completePlanDraftItem(taskId, draft.planTaskId, draft.planItemIndex, unit, reused);
          return;
        }
        this.host.sendIngestAnswer(taskId,
          (reused ? '已保存（检测到相同笔记，已复用）：' : '已保存：')
            + unit.title + '（' + unit.subject + '）', 0);
      })
      .catch((e: Error): void => {
        hilog.error(DOMAIN, TAG, 'A2A_DRAFT confirm failed %{public}s', e.message);
        this.host.sendIngestAnswer(taskId, '保存失败：' + e.message + '。可回复「确认」重试，或「取消」放弃。', 0);
      });
  }

  /** 用户取消：丢弃草稿；若属于计划，同时结束计划，不写库。 */
  cancelPendingDraft(taskId: string, conversationKey: string, draft: A2APendingDraft): void {    A2ADraftStore.clear(this.host.ingestContext(), conversationKey).catch((): void => {});
    if (draft.planTaskId !== undefined) {
      A2APlanStore.clear(this.host.ingestContext(), draft.planTaskId).catch((): void => {});
    }
    hilog.info(DOMAIN, TAG, 'A2A_DRAFT cancel key=%{public}s', conversationKey);
    this.host.sendIngestAnswer(taskId,
      draft.planTaskId !== undefined ? '已取消这次整理计划，没有写入新笔记。' : '已取消，这次没有写入笔记。', 0);
  }

  /** 草稿二次操作：详细一点 / 简洁一点 / 重新生成；失败保留旧草稿。 */
  refinePendingDraft(taskId: string, conversationKey: string, draft: A2APendingDraft,
    mode: A2ADraftRefine): void {
    const sourceText: string = draft.sourceText !== undefined && draft.sourceText.length > 0
      ? draft.sourceText : draft.event.candidate.content;
    const runId: string = 'a2a-draft-refine-' + Date.now().toString() + '-'
      + Math.floor(Math.random() * 1000).toString();
    const token: CancellationToken = new CancellationToken();
    let instruction: string = DEFAULT_DRAFT_INSTRUCTION;
    if (mode === 'more') {
      instruction = '把这段数学内容整理得更详细：保留标准字段，补充条件、推导步骤和易错点；'
        + '不要编造源材料之外的事实。';
    } else if (mode === 'less') {
      instruction = '把这段数学内容整理得更简洁：每个字段最多一句话，只保留核心定义与结论。';
    }
    hilog.info(DOMAIN, TAG, 'A2A_DRAFT refine mode=%{public}s key=%{public}s', mode, conversationKey);
    this.draftWithDeadline(runId, sourceText, [], token, instruction, mode === 'more')
      .then((event: NoteDraftReadyEvent): void => {
        if (!A2AIngestHandler.draftUseful(event, sourceText)) {
          throw new Error('draft-empty');
        }
        const next: A2APendingDraft = {
          conversationKey: conversationKey,
          createdAt: Date.now(),
          event: event,
          sourceText: sourceText,
        };
        if (draft.planTaskId !== undefined) {
          next.planTaskId = draft.planTaskId;
          next.planItemIndex = draft.planItemIndex;
        }
        A2ADraftStore.save(this.host.ingestContext(), next).catch((): void => {});
        new AiService(this.host.ingestContext(), false).cancelDraft(draft.event.runId).catch((): void => {});
        this.host.sendIngestAnswer(taskId, formatA2ADraftReply(event), 0);
      })
      .catch((e: Error): void => {
        hilog.warn(DOMAIN, TAG, 'A2A_DRAFT refine failed %{public}s', e.message);
        this.host.sendIngestAnswer(taskId,
          '这次调整没成功：' + e.message + '。可以回复「确认」保存原草稿，或「取消」。', 0);
      });
  }

  /** 计划草稿确认后：回写 done，提示下一题；全部完成则清掉计划。 */
  private completePlanDraftItem(taskId: string, planTaskId: string, itemIndex: number,
    unit: KnowledgeUnit, reused: boolean): void {
    A2APlanStore.load(this.host.ingestContext(), planTaskId)
      .then((plan: A2APlan | null): void => {
        const title: string = unit.title;
        if (plan === null) {
          this.host.sendIngestAnswer(taskId, (reused ? '已保存（复用）：' : '已保存：')
            + title + '（' + unit.subject + '）', 0);
          return;
        }
        if (plan.done.indexOf(itemIndex) < 0) {
          plan.done.push(itemIndex);
        }
        const remaining: number = remainingPlanCount(plan);
        if (remaining === 0) {
          A2APlanStore.clear(this.host.ingestContext(), planTaskId).catch((): void => {});
          this.host.sendIngestAnswer(taskId, (reused ? '已保存（复用）：' : '已保存：')
            + title + '（' + unit.subject + '）。这次计划全部完成。', 0);
          return;
        }
        A2APlanStore.save(this.host.ingestContext(), planTaskId, plan)
          .then((): void => {
            this.host.sendIngestAnswer(taskId, (reused ? '已保存（复用）：' : '已保存：')
              + title + '（' + unit.subject + '）。进度 ' + plan.done.length.toString()
              + '/' + plan.items.length.toString() + '，回复「继续」整理下一题，或「取消」结束计划。', 0);
          })
          .catch((e: Error): void => {
            hilog.warn(DOMAIN, TAG, 'PLAN_SAVE_FAILED %{public}s', e.message);
            this.host.sendIngestAnswer(taskId, (reused ? '已保存（复用）：' : '已保存：')
              + title + '（' + unit.subject + '）。', 0);
          });
      })
      .catch((e: Error): void => {
        hilog.warn(DOMAIN, TAG, 'PLAN_LOAD_FAILED %{public}s', e.message);
        this.host.sendIngestAnswer(taskId, (reused ? '已保存（复用）：' : '已保存：')
          + unit.title + '（' + unit.subject + '）', 0);
      });
  }

  /** 有未完成计划时：解析「继续 / 第 N 题 / 全部 / 取消」，先出草稿再确认。 */
  handlePlanTurn(taskId: string, query: string, plan: A2APlan, conversationKey: string): void {
    const command: A2APlanCommand = parseA2APlanCommand(query);
    if (command.kind === PLAN_CMD_CANCEL) {
      A2APlanStore.clear(this.host.ingestContext(), taskId).catch((): void => {});
      A2ADraftStore.clear(this.host.ingestContext(), conversationKey).catch((): void => {});
      this.host.sendIngestAnswer(taskId, '已取消这次整理计划，没有写入新笔记。', 0);
      return;
    }
    let item: A2APlanItem | undefined = undefined;
    if (command.kind === PLAN_CMD_ALL) {
      // 「全部」也从第一题开始预览；确认一题后再「继续」下一题。
      item = nextPlanItem(plan);
    } else if (command.kind === PLAN_CMD_INDEX) {
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
    this.beginPlanDraftCheckpoint(taskId, conversationKey, plan, item);
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

  /** 整理计划中的一道题：先生成草稿，确认后才入库。 */
  private ingestPlanItem(taskId: string, plan: A2APlan, item: A2APlanItem,
    conversationKey: string): void {
    this.beginPlanDraftCheckpoint(taskId, conversationKey, plan, item);
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
      if (batch.totalProblems > 1) {
        // queuedTexts 只含第 2..N 题；第 1 题由 enqueueForIngest 入队并回执。
        this.enqueueTexts(batch.queuedTexts);
      }
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
  /** 入队并只回一条回执；调用方不应再单独回话，避免小艺里出现两条。 */
  private enqueueForIngest(taskId: string, query: string, replyText?: string): void {
    const item: AgentInboxItem = buildInboxItem(query, Date.now());
    AgentInboxQueue.append(this.host.ingestContext(), item)
      .then((pending: number): void => {
        hilog.info(DOMAIN, TAG, 'INBOX_ENQUEUED pending=%{public}d chars=%{public}d',
          pending, item.text.length);
        const text: string = replyText === undefined
          ? '模型这次没通，已记为待整理（第 ' + pending.toString() + ' 条）。打开 MindTrace 会自动补上。'
          : replyText;
        this.host.sendIngestAnswer(taskId, text, 0);
      })
      .catch((e: Error): void => {
        hilog.error(DOMAIN, TAG, 'INBOX_ENQUEUE_FAILED %{public}s', e.message);
        this.host.sendIngestAnswer(taskId, '这条笔记没排上队，再发一次？', 0);
      });
  }

  /** 从 onData 拿到有效 query 开始计时：4s 配置 + 25s 模型 + 6s 余量 = 35s。 */
}
