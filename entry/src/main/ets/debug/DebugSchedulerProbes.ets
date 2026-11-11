/**
 * DebugSchedulerProbes.ets — 写任务调度、持久队列与并发的调试探针
 *
 * 路径: entry/src/main/ets/debug/DebugSchedulerProbes.ets
 * 职责: 写任务调度、持久队列与并发的调试探针；由 EntryAbility 的调试启动参数触发
 * 依赖: ./DebugProbeSupport 与 entry services
 *
 * 数据流: EntryAbility.runDebugProbe → DebugSchedulerProbes → services / RDB
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

export class DebugSchedulerProbes {
  static async runSchedulerIntegration(ctx: common.UIAbilityContext): Promise<void> {
    const text: string = '计算 6 + 2 × 3 的值，写出运算顺序。集成 ' + Date.now().toString();
    WriteJobFlags.setEnabled(true);
    const startedAt: number = Date.now();
    try {
      const before: WriteJobStats = WriteJobScheduler.shared().stats();
      const outcome: NoteOutcome = await AgentIngestService.ingestSingleText(ctx, text);
      const stats: WriteJobStats = WriteJobScheduler.shared().stats();
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=scheduler-integration kind=' + outcome.kind
          + ' submittedDelta=' + (stats.submitted - before.submitted).toString()
          + ' completedDelta=' + (stats.completed - before.completed).toString()
          + ' failedDelta=' + (stats.failed - before.failed).toString()
          + ' noteId=' + (outcome.noteId !== undefined ? outcome.noteId : ''));
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=done schedulerIntegration=' + (outcome.kind === 'committed' ? '1' : '0')
          + ' ms=' + (Date.now() - startedAt).toString());
    } catch (error) {
      hilog.error(DOMAIN, TAG, '%{public}s',
        'stage=done schedulerIntegration=0 err=' + (error as Error).message);
    } finally {
      WriteJobFlags.setEnabled(WRITE_JOB_UI_ENABLED);
    }
  }

  /** 文本整理 e2e：直接调用 A2A 内联同款 ingestTextBatch（不经过 App UI / 小艺 UI）。 */

  static async runSchedulerPersistEnqueue(ctx: common.UIAbilityContext): Promise<void> {
    WriteJobPersistenceFlags.setEnabled(true);
    const startedAt: number = Date.now();
    try {
      await DatabaseHelper.init(ctx);
      const store: relationalStore.RdbStore | null = DatabaseHelper.getStore();
      if (store === null) {
        throw new Error('store-null');
      }
      const dao: AgentJobDao = new AgentJobDao(store);
      const persistence: AgentJobPersistence = new AgentJobPersistence(dao);
      const text: string = '持久化探针 ' + Date.now().toString() + '：计算 6 + 7 的值并说明运算顺序。';
      const firstId: string = await persistence.enqueueForSource('interactive', text, 'e2e');
      const secondId: string = await persistence.enqueueForSource('interactive', text, 'e2e');
      const queued: number = await dao.countByStatus('queued');
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=persist-enqueue jobId=' + firstId + ' same=' + (firstId === secondId ? '1' : '0')
          + ' queued=' + queued.toString());
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=done persistEnqueue=1 ms=' + (Date.now() - startedAt).toString());
    } catch (error) {
      hilog.error(DOMAIN, TAG, '%{public}s',
        'stage=done persistEnqueue=0 err=' + (error as Error).message);
    } finally {
      WriteJobPersistenceFlags.setEnabled(WRITE_JOB_PERSIST_ENABLED);
    }
  }

  /** P3 持久化 e2e：重启后安装 hooks/recover 并等待队列清空（真实 ingest）。 */

  static async runSchedulerPersistDrain(ctx: common.UIAbilityContext): Promise<void> {
    WriteJobPersistenceFlags.setEnabled(true);
    const startedAt: number = Date.now();
    try {
      await DatabaseHelper.init(ctx);
      const store: relationalStore.RdbStore | null = DatabaseHelper.getStore();
      if (store === null) {
        throw new Error('store-null');
      }
      const dao: AgentJobDao = new AgentJobDao(store);
      const beforeQueued: number = await dao.countByStatus('queued');
      const beforeRunning: number = await dao.countByStatus('running');
      const beforeDone: number = await dao.countByStatus('done');
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=persist-drain beforeQueued=' + beforeQueued.toString()
          + ' beforeRunning=' + beforeRunning.toString() + ' beforeDone=' + beforeDone.toString());
      await WriteJobBootstrap.install(ctx);
      let queued: number = beforeQueued;
      let running: number = beforeRunning;
      let done: number = beforeDone;
      for (let i = 0; i < 180; i += 1) {
        await DebugProbeSupport.sleep(1000);
        queued = await dao.countByStatus('queued');
        running = await dao.countByStatus('running');
        done = await dao.countByStatus('done');
        if (queued === 0 && running === 0) {
          break;
        }
      }
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=persist-drain result queued=' + queued.toString() + ' running=' + running.toString()
          + ' doneDelta=' + (done - beforeDone).toString());
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=done persistDrain=' + (queued === 0 && running === 0 ? '1' : '0')
          + ' doneDelta=' + (done - beforeDone).toString()
          + ' ms=' + (Date.now() - startedAt).toString());
    } catch (error) {
      hilog.error(DOMAIN, TAG, '%{public}s',
        'stage=done persistDrain=0 err=' + (error as Error).message);
    } finally {
      WriteJobPersistenceFlags.setEnabled(WRITE_JOB_PERSIST_ENABLED);
    }
  }

  /** S2 多入口：A2A inbox 队列 → flag 开 → background lane 真实 ingest。 */

  static async runSchedulerInbox(ctx: common.UIAbilityContext): Promise<void> {
    const text: string = '计算 5 + 5 × 2 的值，写出运算顺序。收件箱 ' + Date.now().toString();
    const startedAt: number = Date.now();
    try {
      await AgentInboxQueue.append(ctx, buildInboxItem(text, Date.now()));
      const before: WriteJobStats = WriteJobScheduler.shared().stats();
      const summary: IngestSummary = await A2AInboxIngestService.consume(ctx);
      const after: WriteJobStats = WriteJobScheduler.shared().stats();
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=inbox claimed=' + summary.claimed.toString()
          + ' done=' + summary.done.toString() + ' failed=' + summary.failed.toString()
          + ' submittedDelta=' + (after.submitted - before.submitted).toString()
          + ' completedDelta=' + (after.completed - before.completed).toString()
          + ' failedDelta=' + (after.failed - before.failed).toString()
          + ' maxConcurrent=' + after.maxConcurrent.toString()
          + ' ms=' + (Date.now() - startedAt).toString());
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=done inbox=' + (summary.done > 0 ? '1' : '0'));
    } catch (error) {
      hilog.error(DOMAIN, TAG, '%{public}s',
        'stage=done inbox=0 err=' + (error as Error).message);
    }
  }

  /** S2 压测：2 interactive + 4 background + 1 失败任务；核对排队、事件与终态。 */

  static async runSchedulerStress(): Promise<void> {
    const scheduler: WriteJobScheduler = WriteJobScheduler.shared();
    WriteJobFlags.setEnabled(true);
    const startedAt: number = Date.now();
    const exec = async (): Promise<Object> => {
      await DebugProbeSupport.sleep(120);
      return 'ok' as Object;
    };
    const daoOf = (): RunStoreDao | null => {
      const store: relationalStore.RdbStore | null = DatabaseHelper.getStore();
      return store === null ? null : new RunStoreDao(store);
    };
    const countEvents = async (): Promise<number> => {
      const dao: RunStoreDao | null = daoOf();
      return dao === null ? 0 : await dao.countEventsByRunPrefix(WRITE_JOB_RUN_PREFIX);
    };
    const countTerminal = async (status: string): Promise<number> => {
      const dao: RunStoreDao | null = daoOf();
      return dao === null ? 0 : await dao.countRecordsByRunPrefixAndStatus(WRITE_JOB_RUN_PREFIX, status);
    };
    try {
      const beforeEvents: number = await countEvents();
      const beforeCommitted: number = await countTerminal('committed');
      const beforeFailed: number = await countTerminal('failed');
      const beforeStats: WriteJobStats = scheduler.stats();
      const tasks: Promise<Object>[] = [
        scheduler.submit('interactive', 'stress-i1', exec),
        scheduler.submit('interactive', 'stress-i2', exec),
        scheduler.submit('background', 'stress-b1', exec),
        scheduler.submit('background', 'stress-b2', exec),
        scheduler.submit('background', 'stress-b3', exec),
        scheduler.submit('background', 'stress-b4', exec),
        scheduler.submit('interactive', 'stress-fail', async (): Promise<Object> => {
          throw new Error('stress-fail');
        }).catch((): Object => 'failed' as Object),
      ];
      await Promise.all(tasks);
      const stats: WriteJobStats = scheduler.stats();
      const submittedDelta: number = stats.submitted - beforeStats.submitted;
      const completedDelta: number = stats.completed - beforeStats.completed;
      const failedDelta: number = stats.failed - beforeStats.failed;
      let persisted: number = 0;
      let terminalCommitted: number = 0;
      let terminalFailed: number = 0;
      const expectedPersisted: number = submittedDelta * 3;
      for (let attempt = 0; attempt < 15; attempt += 1) {
        persisted = (await countEvents()) - beforeEvents;
        terminalCommitted = (await countTerminal('committed')) - beforeCommitted;
        terminalFailed = (await countTerminal('failed')) - beforeFailed;
        if (persisted >= expectedPersisted && terminalCommitted >= completedDelta
          && terminalFailed >= failedDelta) {
          break;
        }
        await DebugProbeSupport.sleep(200);
      }
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=stress submittedDelta=' + submittedDelta.toString()
          + ' completedDelta=' + completedDelta.toString() + ' failedDelta=' + failedDelta.toString()
          + ' maxConcurrent=' + stats.maxConcurrent.toString()
          + ' queueDepth=' + stats.queueDepth.toString()
          + ' lastWaitMs=' + stats.lastWaitMs.toString()
          + ' lastRunMs=' + stats.lastRunMs.toString()
          + ' persistedEvents=' + persisted.toString()
          + ' terminalCommitted=' + terminalCommitted.toString()
          + ' terminalFailed=' + terminalFailed.toString()
          + ' ms=' + (Date.now() - startedAt).toString());
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=done stress=1 persistedEvents=' + persisted.toString()
          + ' terminalCommitted=' + terminalCommitted.toString()
          + ' terminalFailed=' + terminalFailed.toString());
    } catch (error) {
      hilog.error(DOMAIN, TAG, '%{public}s',
        'stage=done stress=0 err=' + (error as Error).message);
    } finally {
      WriteJobFlags.setEnabled(WRITE_JOB_UI_ENABLED);
    }
  }

  /** S1 调度器 lane 自检：直接注入 executor 验证双通道并发；flag 接线由 schedulerIntegration 覆盖。 */

  static async runSchedulerProbe(ctx: common.UIAbilityContext): Promise<void> {
    const stamp: string = Date.now().toString();
    const interactiveText: string = '计算 2 + 3 × 4 的值，写出运算顺序。调度 ' + stamp + 'I';
    const backgroundText: string = '计算 10 - 4 × 2 的值，写出运算顺序。调度 ' + stamp + 'B';
    const startedAt: number = Date.now();
    const timed = (run: () => Promise<Object>): Promise<number> => {
      const taskStarted: number = Date.now();
      return run().then((_value: Object): number => Date.now() - taskStarted);
    };
    try {
      hilog.info(DOMAIN, TAG, '%{public}s', 'stage=scheduler start');
      const scheduler: WriteJobScheduler = WriteJobScheduler.shared();
      const backgroundText3: string = '计算 12 - 2 × 3 的值，写出运算顺序。调度 ' + stamp + 'B2';
      const interactiveMs: Promise<number> = DebugProbeSupport.withTimeout(
        timed((): Promise<Object> => scheduler.submit('interactive', interactiveText,
          async (): Promise<Object> => await AgentIngestService.ingestSingleTextDirect(ctx, interactiveText) as Object)),
        150000, 'scheduler-interactive');
      const backgroundMs: Promise<number> = DebugProbeSupport.withTimeout(
        timed((): Promise<Object> => scheduler.submit('background', backgroundText,
          async (): Promise<Object> => await AgentIngestService.ingestSingleTextDirect(ctx, backgroundText) as Object)),
        150000, 'scheduler-background-1');
      const background2Ms: Promise<number> = DebugProbeSupport.withTimeout(
        timed((): Promise<Object> => scheduler.submit('background', backgroundText3,
          async (): Promise<Object> => await AgentIngestService.ingestSingleTextDirect(ctx, backgroundText3) as Object)),
        150000, 'scheduler-background-2');
      const results: number[] = await Promise.all([interactiveMs, backgroundMs, background2Ms]);
      const stats: WriteJobStats = scheduler.stats();
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=scheduler done interactiveMs=' + results[0].toString()
          + ' backgroundMs=' + results[1].toString()
          + ' background2Ms=' + results[2].toString()
          + ' submitted=' + stats.submitted.toString() + ' completed=' + stats.completed.toString()
          + ' failed=' + stats.failed.toString() + ' queueDepth=' + stats.queueDepth.toString()
          + ' maxConcurrent=' + stats.maxConcurrent.toString()
          + ' lastWaitMs=' + stats.lastWaitMs.toString() + ' lastRunMs=' + stats.lastRunMs.toString());
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=done scheduler=1 ms=' + (Date.now() - startedAt).toString());
    } catch (error) {
      hilog.error(DOMAIN, TAG, '%{public}s',
        'stage=done scheduler=0 err=' + (error as Error).message);
    }
  }

  /** S0 并发实验：顺序两条 vs 并发两条，量「多入口互拖」是否存在。 */

  static async runConcurrencyProbe(ctx: common.UIAbilityContext): Promise<void> {
    const stamp: string = Date.now().toString();
    const seqA: string = '计算 3 + 5 × 2 的值，写出运算顺序。批次 ' + stamp + 'A';
    const seqB: string = '计算 8 - 2 × 3 的值，写出运算顺序。批次 ' + stamp + 'B';
    const concA: string = '计算 4 + 6 × 2 的值，写出运算顺序。批次 ' + stamp + 'C';
    const concB: string = '计算 9 - 3 × 2 的值，写出运算顺序。批次 ' + stamp + 'D';
    const timeOne = async (text: string): Promise<number> => {
      const startedAt: number = Date.now();
      const task: Promise<void> = AgentIngestService.ingestSingleText(ctx, text).then((): void => {});
      await DebugProbeSupport.withTimeout(task, 120000, 'concurrency-task');
      return Date.now() - startedAt;
    };
    try {
      hilog.info(DOMAIN, TAG, '%{public}s', 'stage=concurrency seq-start');
      const seqAMs: number = await timeOne(seqA);
      const seqBMs: number = await timeOne(seqB);
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=concurrency seq a=' + seqAMs.toString() + ' b=' + seqBMs.toString()
          + ' sum=' + (seqAMs + seqBMs).toString());
      hilog.info(DOMAIN, TAG, '%{public}s', 'stage=concurrency conc-start');
      const wallStart: number = Date.now();
      let concAMs: number = 0;
      let concBMs: number = 0;
      await Promise.all([
        timeOne(concA).then((ms: number): void => { concAMs = ms; }),
        timeOne(concB).then((ms: number): void => { concBMs = ms; }),
      ]);
      const wallMs: number = Date.now() - wallStart;
      const seqSum: number = seqAMs + seqBMs;
      const concSum: number = concAMs + concBMs;
      const overlap: number = concSum > 0 ? Math.max(0, Math.round((concSum - wallMs) / concSum * 100)) : 0;
      const slowdown: number = seqSum > 0 ? Number((concSum / seqSum).toFixed(2)) : 0;
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=concurrency conc a=' + concAMs.toString() + ' b=' + concBMs.toString()
          + ' sum=' + concSum.toString() + ' wall=' + wallMs.toString()
          + ' overlapPct=' + overlap.toString()
          + ' slowdown=' + slowdown.toString()
          + ' seqSum=' + seqSum.toString());
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=done concurrency=1 slowdown=' + slowdown.toString() + ' overlapPct=' + overlap.toString());
    } catch (error) {
      hilog.error(DOMAIN, TAG, '%{public}s',
        'stage=done concurrency=0 err=' + (error as Error).message);
    }
  }

  /** 历史数据清理（B）：旧笔记学科归一 + 完全重复删除；apply=false 只审计。 */
}
