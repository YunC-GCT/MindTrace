/**
 * AgentIngestService.ets — 所有入口的整理端口（唯一写入口）。
 *
 * 路径: entry/src/main/ets/services/AgentIngestService.ets
 * 职责: 收一个 AgentIngestRequest（文字 + 可选图片），需要时先调 OcrService 把图变成文本，
 *       再走 DatabaseHelper.init → AiService.ingestText → Dispatcher → 结构化 → KnowledgeUnitWriteService。
 * 依赖: common (DatabaseHelper / KnowledgeUnit)、services/AiService、services/OcrService
 *
 * 为什么这么分层：
 *   入口层（小艺 extension / 应用内选图 / 分享）只负责「把外部协议翻译成 AgentIngestRequest」，
 *   传输差异到此为止；识别是共享能力（OcrService），编排与落库也是共享的（CommandExecutor + 写路径）。
 *   新入口 = 新 adapter，不需要复制任何整理逻辑。
 *
 * 进程约束：扩展进程（:agent）没有 UIAbilityContext，副作用必须关掉
 *   （AiService 第二个参数 includeUiEffects = false），卡片刷新由主进程注册。
 *
 * 写库模式（ADR-0024 §2.1/§2.7）:
 *   - ingestTextBatch / ingestOutcome / ingestSingleTextDirect 直接执行，不经过 WriteJobScheduler；
 *   - ingestSingleText 仅在 flag 开启（UI 进程）时经调度器；扩展进程 flag 恒为 false；
 *   - 因此 A2A 单次整理是扩展进程内联；队列只承接兜底/恢复。
 */

import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseHelper, KnowledgeUnit } from 'common';
import type { NoteOutcome } from 'common';
import { AiService } from './AiService';
import { planCaptureSet } from 'agents';
import type { PlannedProblem, SetImageText, SetPlan } from 'agents';
import { AgentImagePart } from './AgentImageParts';
import { AgentIngestRequest } from './AgentIngestRequest';
import { WriteJobFlags, WriteJobScheduler } from './WriteJobScheduler';
import { A2APlanItem, buildA2APlanItemsFromPages } from './A2APlanModels';
import { OcrService } from './OcrService';

const DOMAIN: number = 0xA2A0;
const TAG: string = 'AgentIngest';

/** 一次最多识别几张图：小艺/分享单条消息很少超过 3 张，多则截断 */
const MAX_IMAGES: number = 3;
const NEWLINE: string = String.fromCharCode(10);

export interface AgentTextBatchResult {
  /** 同步提交的结果（多题时只含第 1 题）。 */
  outcomes: NoteOutcome[];
  /** planner 切分出的总题数。 */
  totalProblems: number;
  /** 多题时剩余题目文本（调用方转入待整理队列）。 */
  queuedTexts: string[];
}

export class AgentIngestService {
  /** 端口入口（旧适配器）：失败向上抛，由调用方决定是否退回队列。 */
  static async ingest(context: common.Context, request: AgentIngestRequest): Promise<KnowledgeUnit> {
    const outcome: NoteOutcome = await AgentIngestService.ingestOutcome(context, request);
    if (outcome.kind !== 'committed' || outcome.unit === undefined) {
      const code: string = outcome.code !== undefined ? outcome.code : 'INGEST_FAILED';
      const message: string = outcome.message !== undefined
        ? outcome.message : (outcome.reason !== undefined ? outcome.reason : 'ingest failed');
      throw new Error(code + ': ' + message);
    }
    return outcome.unit;
  }

  /**
   * 图片入口：OCR（文字识别工具）→ 按题规划项（不写库）。返回 null 表示没有可识别文字。
   * A2A 只在「意图=ocr」时调用，识别完先给 checkpoint 摘要，用户回复「继续」才逐题入库。
   */
  static async planItemsFromRequest(request: AgentIngestRequest): Promise<A2APlanItem[] | null> {
    if (request.images.length === 0) {
      return null;
    }
    const total: number = request.images.length > MAX_IMAGES ? MAX_IMAGES : request.images.length;
    const pages: SetImageText[] = [];
    for (let i = 0; i < total; i += 1) {
      const image: AgentImagePart = request.images[i];
      try {
        const text: string = image.kind === 'uri'
          ? await OcrService.recognizeUri(image.value)
          : await OcrService.recognizeBase64(image.value);
        hilog.info(DOMAIN, TAG, 'OCR_PLAN index=%{public}d chars=%{public}d', i, text.length);
        if (text.trim().length > 0) {
          pages.push({ imageIndex: i, text: text.trim() });
        }
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'OCR_PLAN_FAILED index=%{public}d %{public}s', i, (e as Error).message);
      }
    }
    if (pages.length === 0) {
      return null;
    }
    return buildA2APlanItemsFromPages(pages);
  }

  /**
   * 单题整理入口：flag 开启时经 WriteJobScheduler（interactive lane）；
   * 关闭时直连（旧行为逐字节一致）。
   */
  static async ingestSingleText(context: common.Context, text: string): Promise<NoteOutcome> {
    if (!WriteJobFlags.isEnabled()) {
      return await AgentIngestService.ingestSingleTextDirect(context, text);
    }
    const result: Object = await WriteJobScheduler.shared().submit('interactive', text, async (): Promise<Object> => {
      const outcome: NoteOutcome = await AgentIngestService.ingestSingleTextDirect(context, text);
      return outcome as Object;
    });
    return result as NoteOutcome;
  }

  /** 单题同步整理（直连实现）：初始化 DB → ingestTextOutcome。 */
  static async ingestSingleTextDirect(context: common.Context, text: string): Promise<NoteOutcome> {
    const body: string = text.trim();
    if (body.length === 0) {
      throw new Error('empty payload');
    }
    await DatabaseHelper.init(context);
    const service: AiService = new AiService(context, false);
    return await service.ingestTextOutcome(body);
  }

  /**
   * 图片识别后的文字入口：把一段 OCR 文本按题切分（复用 036 planner）。
   * - 单题：保持原逻辑，整段文本同步整理 → 1 条笔记；
   * - 多题：先同步整理第 1 题保证 30s 内回执，其余题返回 queuedTexts 由调用方转入待整理队列
   *   （app 前台自动补跑），避免超出端A2A 35s 时间预算。
   */
  static async ingestTextBatch(context: common.Context, text: string): Promise<AgentTextBatchResult> {
    const body: string = text.trim();
    if (body.length === 0) {
      throw new Error('empty payload');
    }
    await DatabaseHelper.init(context);
    const pages: SetImageText[] = [{ imageIndex: 0, text: body }];
    const plan: SetPlan = planCaptureSet(pages);
    hilog.info(DOMAIN, TAG, 'TEXT_PLAN problems=%{public}d preambleSkipped=%{public}d',
      plan.problems.length, plan.preambleSkipped);
    const service: AiService = new AiService(context, false);
    if (plan.problems.length <= 1) {
      const outcome: NoteOutcome = await service.ingestTextOutcome(body);
      const single: AgentTextBatchResult = {
        outcomes: [outcome],
        totalProblems: plan.problems.length,
        queuedTexts: [],
      };
      return single;
    }
    const first: PlannedProblem = plan.problems[0];
    const firstOutcome: NoteOutcome = await service.ingestTextOutcome(first.text);
    const queued: string[] = [];
    for (let i = 1; i < plan.problems.length; i += 1) {
      queued.push(plan.problems[i].text);
    }
    const batch: AgentTextBatchResult = {
      outcomes: [firstOutcome],
      totalProblems: plan.problems.length,
      queuedTexts: queued,
    };
    return batch;
  }

  /**
   * A3d：端口入口的命令终态版本。A2A 回执直接消费 NoteOutcome，不再靠异常文本猜状态。
   */
  static async ingestOutcome(context: common.Context, request: AgentIngestRequest): Promise<NoteOutcome> {
    hilog.info(DOMAIN, TAG, 'INGEST source=%{public}s textChars=%{public}d images=%{public}d',
      request.source, request.text.length, request.images.length);
    const text: string = request.images.length > 0
      ? await AgentIngestService.ocrImages(request)
      : request.text.trim();
    if (text.length === 0) {
      throw new Error('empty payload');
    }
    await DatabaseHelper.init(context);
    const service: AiService = new AiService(context, false);
    return await service.ingestTextOutcome(text);
  }

  /** 图片 → 文本（单张失败不拖垮整批；全失败抛错，不写空笔记） */
  private static async ocrImages(request: AgentIngestRequest): Promise<string> {
    const total: number = request.images.length > MAX_IMAGES ? MAX_IMAGES : request.images.length;
    const texts: string[] = [];
    for (let i = 0; i < total; i++) {
      const image: AgentImagePart = request.images[i];
      try {
        const text: string = image.kind === 'uri'
          ? await OcrService.recognizeUri(image.value)
          : await OcrService.recognizeBase64(image.value);
        hilog.info(DOMAIN, TAG, 'IMAGE_OCR index=%{public}d chars=%{public}d', i, text.length);
        if (text.trim().length > 0) {
          texts.push(text.trim());
        }
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'IMAGE_OCR_FAILED index=%{public}d %{public}s', i, (e as Error).message);
      }
    }
    if (texts.length === 0) {
      throw new Error('no text recognised in images');
    }
    const body: string = texts.join(NEWLINE + NEWLINE);
    // 用户在图片旁打的字（如「存笔记」）当提示，不覆盖正文
    return request.text.trim().length > 0 ? request.text.trim() + NEWLINE + body : body;
  }
}
