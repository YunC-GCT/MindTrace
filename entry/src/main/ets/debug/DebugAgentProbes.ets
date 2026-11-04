/**
 * DebugAgentProbes.ets — 小艺端A2A、应用内意图与对话上下文的调试探针
 *
 * 路径: entry/src/main/ets/debug/DebugAgentProbes.ets
 * 职责: 小艺端A2A、应用内意图与对话上下文的调试探针；由 EntryAbility 的调试启动参数触发
 * 依赖: ./DebugProbeSupport 与 entry services
 *
 * 数据流: EntryAbility.runDebugProbe → DebugAgentProbes → services / RDB
 */
/**
 * DebugCaptureRunner.ets — 批量链路自检（仅调试入口可见时使用）
 * 路径: entry/src/main/ets/debug/DebugCaptureRunner.ets
 * 职责: 用 rawfile 里的样例题图跑完「取图 → OCR → 结构化 → 落库 → 卡片快照」整链，
 *       每个阶段打一条 [E2E] 日志，失败不中断后续图（与批量入口的语义一致）。
 * 依赖: AiService / CardSnapshotService / CoreVisionImageSearchIndex / ResourceManager / CoreFileKit / CaptureReceipt
 * 数据流: run(ctx) → getRawFileContent('debug/math-N.png') → cacheDir 下的 file:// →
 *        AiService.capture() → CardSnapshotService.refresh() → hilog [E2E]
 */
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DatabaseHelper, ImageSearchIndexRegistry } from 'common';
import type { CaptureSetItemResult, CaptureSetPreview, CaptureSetProblem, CaptureSetResult, ImageSearchHit, KnowledgeUnit, NoteOutcome } from 'common';
import { AiService } from '../services/AiService';
import { CardSnapshotService } from '../services/CardSnapshotService';
import { CoreVisionImageSearchIndex } from '../services/CoreVisionImageSearchIndex';
import { CaptureReceipt, CaptureReceiptStore } from '../services/CaptureReceipt';
import { RagHit, RagRetrievalService } from '../services/RagRetrievalService';
import { RagKitProbe } from '../services/RagKitProbe';
import { AgentIngestService, AgentTextBatchResult } from '../services/AgentIngestService';
import { A2AChatContext, A2AChatContextResult } from '../services/A2AChatContext';

import { NoteDao } from '../database/NoteDao';
import { RunStoreDao } from '../database/RunStoreDao';
import { A2AInboxIngestService, IngestSummary } from '../services/A2AInboxIngestService';
import { AgentInboxQueue } from '../services/AgentInboxQueue';
import { A2AImageContextStore } from '../services/A2AImageContextStore';
import { buildInboxItem } from '../services/AgentInboxModels';
import { WRITE_JOB_RUN_PREFIX } from '../services/WriteJobEvents';
import { WriteJobFlags, WriteJobScheduler, WriteJobStats } from '../services/WriteJobScheduler';
import { WRITE_JOB_PERSIST_ENABLED, WRITE_JOB_UI_ENABLED, WriteJobPersistenceFlags } from '../services/WriteJobConfig';
import { AgentJobPersistence } from '../services/WriteJobPersistence';
import { WriteJobBootstrap } from '../services/WriteJobBootstrap';
import { AgentJobDao } from '../database/AgentJobDao';
import { AgentImagePart } from '../services/AgentImageParts';
import { AgentIngestRequest, buildIngestRequest, INGEST_SOURCE_XIAOYI } from '../services/AgentIngestRequest';
import {
  A2APlan,
  A2APlanItem,
  buildA2APlanItems,
  formatA2APlanProgress,
  formatA2APlanSummary,
  nextPlanItem,
  remainingPlanCount,
} from '../services/A2APlanModels';
import { A2APlanStore } from '../services/A2APlanStore';

import { createNoteEvidenceService } from '../services/EvidenceComposition';
import { NoteEvidenceContext } from 'common';
import { AppIntentDecision, classifyAppIntentLocal } from 'agents/src/main/ets/chat/Index';
import { LegacyDedupeEntry, LegacyDuplicateGroup, LegacySubjectInput, groupExactDuplicates, groupNearDuplicates, normalizeLegacySubject, isDuplicateOf } from 'agents/src/main/ets/note/Index';
import type { NoteEvidenceService } from 'agents/src/main/ets/evidence/Index';
import { DebugProbeSupport, TAG, DOMAIN, CAPTURE_TIMEOUT_MS, CARD_TIMEOUT_MS } from './DebugProbeSupport';

export class DebugAgentProbes {
  static async runA2ATextIngestProbe(ctx: common.UIAbilityContext): Promise<void> {
    const startedAt: number = Date.now();
    try {
      const batch: AgentTextBatchResult = await AgentIngestService.ingestTextBatch(ctx,
        '整理成笔记：计算 12 - 4 * 2 的值，并写出运算顺序。');
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=done a2aTextIngest=1 problems=' + batch.totalProblems.toString()
          + ' queued=' + batch.queuedTexts.length.toString()
          + ' ms=' + (Date.now() - startedAt).toString());
    } catch (error) {
      hilog.error(DOMAIN, TAG, '%{public}s',
        'stage=done a2aTextIngest=0 err=' + (error as Error).message);
    }
  }

  /** e2e：清除图片材料（含探针污染），不触发 ingest。 */

  static async runA2AImageContextClear(ctx: common.UIAbilityContext): Promise<void> {
    try {
      await A2AImageContextStore.clear(ctx, 'default');
      await A2AImageContextStore.clear(ctx, 'e2e-probe');
      await A2AImageContextStore.clear(ctx, 'mindtrace-context');
      hilog.info(DOMAIN, TAG, '%{public}s', 'stage=done a2aImageClear=1');
    } catch (error) {
      hilog.error(DOMAIN, TAG, '%{public}s',
        'stage=done a2aImageClear=0 err=' + (error as Error).message);
    }
  }

  /** 图片整理闭环 e2e：保存 OCR 文本 → 跨消息读回 → 直接内联整理（不经 App UI）。 */

  static async runA2AImageIngestProbe(ctx: common.UIAbilityContext): Promise<void> {
    const startedAt: number = Date.now();
    try {
      const probeKey: string = 'e2e-probe';
      const ocrText: string = '图片OCR探针：计算 6 + 7 的值，并写出运算顺序。';
      await A2AImageContextStore.clear(ctx, probeKey);
      await A2AImageContextStore.clear(ctx, 'default');
      await A2AImageContextStore.save(ctx, probeKey, ocrText, false);
      const material = await A2AImageContextStore.load(ctx, probeKey);
      if (material === null) {
        throw new Error('recall-null');
      }
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=a2a-image-ingest recalledChars=' + material.text.length.toString());
      const outcome = await AgentIngestService.ingestSingleTextDirect(ctx, material.text) as NoteOutcome;
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=done a2aImageIngest=1 kind=' + outcome.kind
          + ' committed=' + (outcome.committed === true ? '1' : '0')
          + ' ms=' + (Date.now() - startedAt).toString());
    } catch (error) {
      hilog.error(DOMAIN, TAG, '%{public}s',
        'stage=done a2aImageIngest=0 err=' + (error as Error).message);
    }
  }

  /** P3 持久化 e2e：入队一条 job（同 fingerprint 两次 → 同 jobId），不执行，供重启后 drain。 */

  static async runAppIntentProbe(ctx: common.UIAbilityContext): Promise<void> {
    const cases: string[][] = [
      ['存笔记：矩阵的秩等于行秩', '0'],
      ['不要整理，直接讲解', '0'],
      ['今天该复习什么？', '0'],
      ['把我之前记的极限题找出来', '0'],
      ['这题怎么做', '1'],
      ['帮我把这张图整理成笔记', '1'],
      ['帮我看看这个', '1'],
      ['帮我看看这个', '0'],
      ['洛必达法则为什么成立？', '0'],
    ];
    try {
      for (let i = 0; i < cases.length; i += 1) {
        const text: string = cases[i][0];
        const hasImage: boolean = cases[i][1] === '1';
        const decision: AppIntentDecision | undefined = classifyAppIntentLocal(text, hasImage);
        hilog.info(DOMAIN, TAG, '%{public}s',
          'stage=intent case=' + i.toString() + ' text=' + text.substring(0, 18)
            + ' image=' + cases[i][1]
            + ' kind=' + (decision === undefined ? 'llm' : decision.kind)
            + ' source=' + (decision === undefined ? '-' : decision.source));
      }
      hilog.info(DOMAIN, TAG, '%{public}s', 'stage=done appIntent=1 cases=' + cases.length.toString());
    } catch (error) {
      hilog.error(DOMAIN, TAG, '%{public}s', 'stage=done appIntent=0 err=' + (error as Error).message);
    }
  }

  /** A2A 聊天 RAG 自检：构建证据上下文（应命中笔记）并做引用校验。 */

  static async runAgentChatContext(ctx: common.UIAbilityContext): Promise<void> {
    const query: string = '连续性的定义是什么？';
    const startedAt: number = Date.now();
    try {
      const built: A2AChatContextResult = await A2AChatContext.build(query);
      const sampleAnswer: string = '连续性的定义见 [noteId=fake-id version=1]。';
      const sanitized: string = A2AChatContext.sanitize(built.evidence, sampleAnswer);
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=chat-context citations=' + built.citations.toString()
          + ' degraded=' + (built.degraded ? '1' : '0')
          + ' reason=' + built.reason
          + ' evidenceChars=' + built.replyContext.evidenceContext.length.toString()
          + ' fakeRefRemoved=' + (sanitized.indexOf('fake-id') < 0 ? '1' : '0'));
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=done chatContext=1 ms=' + (Date.now() - startedAt).toString());
    } catch (error) {
      hilog.error(DOMAIN, TAG, '%{public}s',
        'stage=done chatContext=0 err=' + (error as Error).message);
    }
  }

  /** A2A 图片 OCR checkpoint 自检：OCR → 规划（不写库）→ 第一题入库。 */

  static async runAgentImagePlan(ctx: common.UIAbilityContext): Promise<void> {
    const startedAt: number = Date.now();
    try {
      const localPath: string = await DebugProbeSupport.materialize(ctx, 'debug/math-1.png');
      const images: AgentImagePart[] = [{ kind: 'uri', value: localPath }];
      const request: AgentIngestRequest = buildIngestRequest(INGEST_SOURCE_XIAOYI, '', images);
      hilog.info(DOMAIN, TAG, '%{public}s', 'stage=image-plan ocr-start');
      const items: A2APlanItem[] | null = await AgentIngestService.planItemsFromRequest(request);
      if (items === null || items.length === 0) {
        hilog.error(DOMAIN, TAG, '%{public}s', 'stage=done imagePlan=0 err=ocr-empty');
        return;
      }
      const plan: A2APlan = { taskId: 'e2e-image-plan', createdAt: Date.now(), items: items, done: [] };
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=image-plan items=' + items.length.toString()
          + ' summary=' + formatA2APlanSummary(plan).split('\n')[0]);
      const first: A2APlanItem | undefined = nextPlanItem(plan);
      if (first === undefined) {
        hilog.error(DOMAIN, TAG, '%{public}s', 'stage=done imagePlan=0 err=no-item');
        return;
      }
      await A2APlanStore.save(ctx, plan.taskId, plan);
      hilog.info(DOMAIN, TAG, '%{public}s', 'stage=image-plan checkpoint saved (未写库)');
      const outcome: NoteOutcome = await AgentIngestService.ingestSingleText(ctx, first.text);
      if (outcome.kind !== 'committed' || outcome.unit === undefined) {
        hilog.error(DOMAIN, TAG, '%{public}s', 'stage=done imagePlan=0 err=ingest kind=' + outcome.kind);
        return;
      }
      plan.done.push(first.index);
      await A2APlanStore.save(ctx, plan.taskId, plan);
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=image-plan progress=' + formatA2APlanProgress(plan, first, outcome.unit.title, outcome.unit.subject).split('\n')[0]);
      await A2APlanStore.clear(ctx, 'e2e-plan');
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=done imagePlan=1 ms=' + (Date.now() - startedAt).toString());
    } catch (error) {
      hilog.error(DOMAIN, TAG, '%{public}s',
        'stage=done imagePlan=0 err=' + (error as Error).message);
    }
  }

  /** A2A「规划 + 一题一题来」自检：切题 → 落盘计划 → 取第一题入库 → 进度回执。 */

  static async runAgentTextPlan(ctx: common.UIAbilityContext): Promise<void> {
    const text: string = '1. 求方程 x^2-5x+6=0 的解。\n2. 求函数 f(x)=x^2+2x+1 的最小值。';
    hilog.info(DOMAIN, TAG, '%{public}s', 'stage=plan start chars=' + text.length.toString());
    const startedAt: number = Date.now();
    try {
      const items: A2APlanItem[] = buildA2APlanItems(text);
      const plan: A2APlan = { taskId: 'e2e-plan', createdAt: Date.now(), items: items, done: [] };
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=plan items=' + items.length.toString() + ' remaining=' + remainingPlanCount(plan).toString()
          + ' summary=' + formatA2APlanSummary(plan).split('\n')[0]);
      await A2APlanStore.save(ctx, plan.taskId, plan);
      const loaded: A2APlan | null = await A2APlanStore.load(ctx, 'e2e-plan');
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=plan-store loaded=' + (loaded === null ? '0' : '1'));
      if (loaded === null) {
        hilog.error(DOMAIN, TAG, '%{public}s', 'stage=done plan=0 err=store-load');
        return;
      }
      const first: A2APlanItem | undefined = nextPlanItem(loaded);
      if (first === undefined) {
        hilog.error(DOMAIN, TAG, '%{public}s', 'stage=done plan=0 err=no-item');
        return;
      }
      const outcome: NoteOutcome = await AgentIngestService.ingestSingleText(ctx, first.text);
      if (outcome.kind !== 'committed' || outcome.unit === undefined) {
        hilog.error(DOMAIN, TAG, '%{public}s', 'stage=done plan=0 err=ingest kind=' + outcome.kind);
        return;
      }
      loaded.done.push(first.index);
      await A2APlanStore.save(ctx, loaded.taskId, loaded);
      const progress: string = formatA2APlanProgress(loaded, first, outcome.unit.title, outcome.unit.subject);
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=plan-progress remaining=' + remainingPlanCount(loaded).toString()
          + ' first=' + progress.split('\n')[0]);
      await A2APlanStore.clear(ctx, 'e2e-plan');
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=done plan=1 ms=' + (Date.now() - startedAt).toString());
    } catch (error) {
      hilog.error(DOMAIN, TAG, '%{public}s',
        'stage=done plan=0 err=' + (error as Error).message);
    }
  }

  /** A2A 文本多题自检：一段「图片识别后的文字」按题切分，首题入库、其余转队列。 */

  static async runAgentTextBatch(ctx: common.UIAbilityContext): Promise<void> {
    const text: string = '1. 求方程 x^2-5x+6=0 的解。\n2. 求函数 f(x)=x^2+2x+1 的最小值。';
    hilog.info(DOMAIN, TAG, '%{public}s', 'stage=text-batch start chars=' + text.length.toString());
    const startedAt: number = Date.now();
    try {
      const batch: AgentTextBatchResult = await AgentIngestService.ingestTextBatch(ctx, text);
      let committed: number = 0;
      let firstTitle: string = '';
      for (let i = 0; i < batch.outcomes.length; i += 1) {
        const outcome: NoteOutcome = batch.outcomes[i];
        if (outcome.kind === 'committed') {
          committed += 1;
          const unit: KnowledgeUnit | undefined = outcome.unit;
          if (firstTitle.length === 0 && unit !== undefined) {
            firstTitle = unit.title;
          }
        }
      }
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=text-batch problems=' + batch.totalProblems.toString()
          + ' committed=' + committed.toString()
          + ' queued=' + batch.queuedTexts.length.toString()
          + ' first=' + firstTitle);
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=done textBatch=1 ms=' + (Date.now() - startedAt).toString());
    } catch (error) {
      hilog.error(DOMAIN, TAG, '%{public}s',
        'stage=text-batch fail err=' + (error as Error).message);
      hilog.error(DOMAIN, TAG, '%{public}s', 'stage=done textBatch=0');
    }
  }

  /** 036 S3 自检：题干页 + 解答页应合并为 1 题（sources=[0,1]）。 */
}
