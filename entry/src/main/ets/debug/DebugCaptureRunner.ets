/**
 * DebugCaptureRunner.ets — 采集、审计与检索的调试探针
 *
 * 路径: entry/src/main/ets/debug/DebugCaptureRunner.ets
 * 职责: 端到端采集回放、笔记审计、重复/延迟探针、RAG 与批量采集探针
 * 依赖: ./DebugProbeSupport、entry services
 *
 * 数据流: EntryAbility.runDebugProbe → 本文件 → AiService / RDB
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
import { intelligence, relationalStore } from '@kit.ArkData';
import { textProcessing } from '@kit.NaturalLanguageKit';
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
import { RAG_EVAL_CASES, RagEvalCase } from './RagEvalCases';
import { AppIntentDecision, classifyAppIntentLocal } from 'agents/src/main/ets/chat/Index';
import { LegacyDedupeEntry, LegacyDuplicateGroup, LegacySubjectInput, groupExactDuplicates, groupNearDuplicates, isDuplicateOf, normalizeForDedupe, normalizeLegacySubject } from 'agents/src/main/ets/note/Index';
import { extractMathSignature } from 'common';
import type { NoteEvidenceService } from 'agents/src/main/ets/evidence/Index';
import { DebugProbeSupport } from './DebugProbeSupport';

const TAG: string = 'E2E';
interface AuditRow {
  id: string;
  title: string;
  content: string;
}

const DOMAIN: number = 0xE2E0;
// 平台调用偶发不返回（updateForm / search 都遇到），自检每一步都限时，先保证有结论
const CAPTURE_TIMEOUT_MS: number = 150000;
const CARD_TIMEOUT_MS: number = 15000;

export class DebugCaptureRunner {
  static async run(ctx: common.UIAbilityContext): Promise<string> {
    const rawPaths: string[] = ['debug/math-1.png', 'debug/math-2.png'];
    const service: AiService = new AiService(ctx);
    const totalStart: number = Date.now();
    let ok: number = 0;
    let failed: number = 0;

    for (let i = 0; i < rawPaths.length; i++) {
      const stageStart: number = Date.now();
      const seq: string = (i + 1).toString();
      try {
        const uri: string = await DebugProbeSupport.materialize(ctx, rawPaths[i]);
        hilog.info(DOMAIN, TAG, '%{public}s', 'stage=pick seq=' + seq + ' uri=' + uri);

        const unit: KnowledgeUnit = await DebugProbeSupport.withTimeout(
          service.capture(uri), CAPTURE_TIMEOUT_MS, 'capture seq=' + seq);
        ok += 1;
        hilog.info(DOMAIN, TAG, '%{public}s',
          'stage=capture seq=' + seq + ' ok=1 ms=' + (Date.now() - stageStart).toString()
            + ' id=' + unit.id + ' title=' + unit.title
            + ' sourceImageId=' + (unit.sourceImageId ?? '(空)')
            + ' ocrConfidence=' + (unit.ocrConfidence ?? 0).toString()
            + ' contentLen=' + unit.content.length.toString());
      } catch (error) {
        failed += 1;
        const e: BusinessError = error as BusinessError;
        hilog.error(DOMAIN, TAG, '%{public}s',
          'stage=capture seq=' + seq + ' ok=0 ms=' + (Date.now() - stageStart).toString() + ' err=' + e.message);
      }
    }

    const receipt: CaptureReceipt = {
      done: ok,
      failed: failed,
      total: rawPaths.length,
      at: Date.now(),
      source: 'debug',
    };
    try {
      await CaptureReceiptStore.save(ctx, receipt);
    } catch (error) {
      console.warn('[BatchCapture] receipt save failed: ' + (error as Error).message);
    }

    try {
      await DebugProbeSupport.withTimeout(
        CardSnapshotService.refresh(ctx), CARD_TIMEOUT_MS, 'card refresh');
      hilog.info(DOMAIN, TAG, '%{public}s', 'stage=card refresh=1');
    } catch (error) {
      const e: BusinessError = error as BusinessError;
      hilog.error(DOMAIN, TAG, '%{public}s', 'stage=card refresh=0 err=' + e.message);
    }

    // 文搜图：确认落库的图片能被自然语言命中。
    // 检索已搬进常驻 Worker（#230），两条连续查询正是之前在主线程序列发出、第二次卡死的场景，必须覆盖。
    if (ImageSearchIndexRegistry.isInstalled()) {
      // 索引写入是异步的：insert 返回后 Kit 还在建，先等索引落盘再查
      await DebugProbeSupport.sleep(8000);
      const queries: string[] = ['一元二次方程', '平方根'];
      for (let i = 0; i < queries.length; i++) {
        const query: string = queries[i];
        const startedAt: number = Date.now();
        try {
          hilog.info(DOMAIN, TAG, '%{public}s', 'stage=search-start q=' + query);
          const hits: ImageSearchHit[] = await DebugProbeSupport.searchWithRetry(query);
          const elapsed: number = Date.now() - startedAt;
          hilog.info(DOMAIN, TAG, '%{public}s',
            'stage=search q=' + query + ' hits=' + hits.length.toString() + ' ms=' + elapsed.toString());
          if (hits.length === 0) {
            // 0 命中可能是真没命中，也可能是 Worker 超时/异常降级；分开打给 e2e 判定
            hilog.warn(DOMAIN, TAG, '%{public}s',
              'stage=search q=' + query + ' hits=0 degraded='
                + (DebugProbeSupport.isSearchDegraded() ? 'true' : 'false')
                + ' ms=' + elapsed.toString());
          }
        } catch (error) {
          const e: BusinessError = error as BusinessError;
          hilog.error(DOMAIN, TAG, '%{public}s', 'stage=search q=' + query + ' err=' + e.message);
        }
      }
    } else {
      hilog.warn(DOMAIN, TAG, '%{public}s', 'stage=search skipped: 端口未安装');
    }

    const summary: string = 'ok=' + ok.toString() + ' failed=' + failed.toString();
    hilog.info(DOMAIN, TAG, '%{public}s', 'stage=done ' + summary + ' totalMs=' + (Date.now() - totalStart).toString());
    return summary;
  }

  /**
   * 只测 search：每条 query 限时 20s，用来区分「检索慢」和「检索死不返回」。
   * 触发：aa start ... --ps e2e search
   */
  /** 笔记质量审计（只读）：最近笔记的学科/分类/结构化字段完整度/重复标题。 */

  static async runNoteAudit(ctx: common.UIAbilityContext): Promise<void> {
    const store: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    if (store === null) {
      hilog.error(DOMAIN, TAG, '%{public}s', 'stage=done audit=0 err=store-null');
      return;
    }
    try {
      const rs: relationalStore.ResultSet = await store.querySql(
        'SELECT id, title, subject, category, content FROM knowledge_unit ORDER BY created_at DESC LIMIT 24', []);
      const titles: string[] = [];
      const rows: AuditRow[] = [];
      let count: number = 0;
      let blankFields: number = 0;
      try {
        while (rs.goToNextRow()) {
          const id: string = rs.getString(rs.getColumnIndex('id'));
          const title: string = rs.getString(rs.getColumnIndex('title'));
          const subject: string = rs.getString(rs.getColumnIndex('subject'));
          const category: string = rs.getString(rs.getColumnIndex('category'));
          const content: string = rs.getString(rs.getColumnIndex('content'));
          const sections: string[] = content.split('## ');
          const sectionLabels: string[] = [];
          let filled: number = 0;
          let empty: number = 0;
          for (let i = 1; i < sections.length; i += 1) {
            const block: string = sections[i];
            const nl: number = block.indexOf('\n');
            const label: string = nl > 0 ? block.substring(0, nl).trim() : block.trim();
            const value: string = nl > 0 ? block.substring(nl + 1).trim() : '';
            sectionLabels.push(label + ':' + value.length.toString());
            if (value.length > 0) {
              filled += 1;
            } else {
              empty += 1;
            }
          }
          if (empty > 0) {
            blankFields += 1;
          }
          titles.push(title.replace(/\s+/g, ''));
          rows.push({ id: id, title: title, content: content });
          hilog.info(DOMAIN, TAG, '%{public}s',
            'audit note id=' + id + ' subject=' + subject + ' category=' + category
              + ' title=' + title.substring(0, 40) + ' sections=' + sectionLabels.join(',')
              + ' filled=' + filled.toString() + ' empty=' + empty.toString());
          count += 1;
        }
      } finally {
        rs.close();
      }
      let dup: number = 0;
      for (let i = 0; i < titles.length; i += 1) {
        for (let j = i + 1; j < titles.length; j += 1) {
          if (titles[i] === titles[j]) {
            dup += 1;
          }
        }
      }
      let contentDup: number = 0;
      for (let i = 0; i < rows.length; i += 1) {
        for (let j = i + 1; j < rows.length; j += 1) {
          if (isDuplicateOf(rows[i].title, rows[i].content,
            { id: rows[j].id, title: rows[j].title, content: rows[j].content })) {
            contentDup += 1;
          }
        }
      }
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=done audit=1 notes=' + count.toString() + ' duplicatePairs=' + dup.toString()
          + ' contentDuplicatePairs=' + contentDup.toString()
          + ' notesWithBlankSections=' + blankFields.toString());
    } catch (error) {
      hilog.error(DOMAIN, TAG, '%{public}s', 'stage=done audit=0 err=' + (error as Error).message);
    }
  }

  /** 写前查重自检：同一文本连续整理两次，第二次应复用同一笔记（不新增）。 */

  static async runDedupeProbe(ctx: common.UIAbilityContext): Promise<void> {
    const text: string = '求函数 f(x)=x+1 在 x=0 处的函数值。';
    const startedAt: number = Date.now();
    try {
      const countBefore: number = await DebugProbeSupport.countRows(DatabaseHelper.getStore() as relationalStore.RdbStore, 'knowledge_unit');
      const first: NoteOutcome = await AgentIngestService.ingestSingleText(ctx, text);
      const second: NoteOutcome = await AgentIngestService.ingestSingleText(ctx, text);
      const countAfter: number = await DebugProbeSupport.countRows(DatabaseHelper.getStore() as relationalStore.RdbStore, 'knowledge_unit');
      const firstUnitId: string = first.unit !== undefined ? first.unit.id : '';
      const secondUnitId: string = second.unit !== undefined ? second.unit.id : '';
      const firstId: string = first.noteId !== undefined && first.noteId.length > 0 ? first.noteId : firstUnitId;
      const secondId: string = second.noteId !== undefined && second.noteId.length > 0 ? second.noteId : secondUnitId;
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=dedupe firstId=' + firstId + ' secondId=' + secondId
          + ' same=' + (firstId.length > 0 && firstId === secondId ? '1' : '0')
          + ' notesBefore=' + countBefore.toString() + ' notesAfter=' + countAfter.toString()
          + ' added=' + (countAfter - countBefore).toString()
          + ' ms=' + (Date.now() - startedAt).toString());
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=done dedupe=' + (firstId.length > 0 && firstId === secondId ? '1' : '0'));
    } catch (error) {
      hilog.error(DOMAIN, TAG, '%{public}s', 'stage=done dedupe=0 err=' + (error as Error).message);
    }
  }

  /** 延迟基线：单题整理一次，节点耗时由 CapturePipeline 的 CAPTURE_STAGE 日志输出。 */

  static async runLatencyProbe(ctx: common.UIAbilityContext): Promise<void> {
    const text: string = '计算 12 + 7 × 3 的值并写出运算顺序。设备时间戳 ' + Date.now().toString();
    const startedAt: number = Date.now();
    try {
      const outcome: NoteOutcome = await AgentIngestService.ingestSingleText(ctx, text);
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=done latency=1 kind=' + outcome.kind
          + ' totalMs=' + (Date.now() - startedAt).toString());
    } catch (error) {
      hilog.error(DOMAIN, TAG, '%{public}s', 'stage=done latency=0 err=' + (error as Error).message);
    }
  }

  /** 相似去重探针：同一道题换个说法再整理一次，写入口应该判重跳过、笔记数不增加。 */
  static async runDedupeSimilarityProbe(ctx: common.UIAbilityContext): Promise<void> {
    const store: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    if (store === null) {
      hilog.error(DOMAIN, TAG, '%{public}s', 'stage=done dedupeSimilarity=0 err=store-null');
      return;
    }
    const startedAt: number = Date.now();
    const addend: number = (Date.now() % 80) + 11;
    const expression: string = '计算 ' + addend.toString() + ' 加 ' + addend.toString() + ' 的结果并写出运算步骤';
    const text: string = expression;
    // 换成文字表述：签名规则应把它与上面的算式判为同一道题。
    const variant: string = '帮我整理：两个 ' + addend.toString() + ' 的和是多少';
    try {
      const before: number = await DebugProbeSupport.countRows(store, 'knowledge_unit');
      const first: NoteOutcome = await AgentIngestService.ingestSingleTextDirect(ctx, text);
      const afterFirst: number = await DebugProbeSupport.countRows(store, 'knowledge_unit');
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=dedupe-similarity first=' + first.kind
          + ' addedFirst=' + (afterFirst - before).toString()
          + ' ms=' + (Date.now() - startedAt).toString());
      const second: NoteOutcome = await AgentIngestService.ingestSingleTextDirect(ctx, variant);
      const afterSecond: number = await DebugProbeSupport.countRows(store, 'knowledge_unit');
      const addedFirst: number = afterFirst - before;
      const addedSecond: number = afterSecond - afterFirst;
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=dedupe-similarity first=' + first.kind + ' second=' + second.kind
          + ' addedFirst=' + addedFirst.toString() + ' addedSecond=' + addedSecond.toString());
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=done dedupeSimilarity=' + (addedSecond === 0 ? '1' : '0')
          + ' ms=' + (Date.now() - startedAt).toString());
    } catch (error) {
      hilog.error(DOMAIN, TAG, '%{public}s',
        'stage=done dedupeSimilarity=0 err=' + (error as Error).message);
    }
  }

  /**
   * 系统文本嵌入能力探针：确认 syscap、模型加载耗时、向量维度与语义区分度。
   * 这是「笔记相似度 / 语义召回」方案能否落地的先决条件。
   */
  static async runEmbeddingProbe(ctx: common.UIAbilityContext): Promise<void> {
    const startedAt: number = Date.now();
    const syscap: string = 'SystemCapability.DistributedDataManager.DataIntelligence.Core';
    const supported: boolean = canIUse(syscap);
    hilog.info(DOMAIN, TAG, '%{public}s', 'stage=embedding syscap=' + (supported ? '1' : '0'));
    if (!supported) {
      hilog.info(DOMAIN, TAG, '%{public}s', 'stage=done embedding=0 err=unsupported');
      return;
    }
    let localError: string = '';
    try {
      const config: intelligence.ModelConfig = {
        version: intelligence.ModelVersion.BASIC_MODEL,
        isNpuAvailable: false,
        cachePath: ctx.cacheDir,
      };
      hilog.info(DOMAIN, TAG, '%{public}s', 'stage=embedding local-obtain-begin');
      const model: intelligence.TextEmbedding = await intelligence.getTextEmbeddingModel(config);
      hilog.info(DOMAIN, TAG, '%{public}s', 'stage=embedding local-obtain-ok');
      const loadStartedAt: number = Date.now();
      await model.loadModel();
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=embedding local-load-ok ms=' + (Date.now() - loadStartedAt).toString());
      await DebugCaptureRunner.runEmbeddingInference(model);
      await model.releaseModel();
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=done embedding=1 path=local ms=' + (Date.now() - startedAt).toString());
      return;
    } catch (error) {
      localError = (error as Error).message;
      hilog.warn(DOMAIN, TAG, '%{public}s', 'stage=embedding local-failed err=' + localError);
    }
    try {
      const clouds: Array<intelligence.CloudModelInfo> = await intelligence.getSupportedCloudModel();
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=embedding cloud-count=' + clouds.length.toString());
      if (clouds.length === 0) {
        hilog.info(DOMAIN, TAG, '%{public}s',
          'stage=done embedding=0 err=local:' + localError + ' cloud:none');
        return;
      }
      const cloudConfig: intelligence.ModelConfig = {
        version: intelligence.ModelVersion.BASIC_MODEL,
        isNpuAvailable: false,
        modelInfo: clouds[0],
        networkPolicy: intelligence.NetworkPolicy.WIFI_AND_CELLULAR,
      };
      const cloudModel: intelligence.TextEmbedding = await intelligence.getTextEmbeddingModel(cloudConfig);
      await cloudModel.loadModel();
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=embedding cloud-load-ok type=' + clouds[0].modelType);
      await DebugCaptureRunner.runEmbeddingInference(cloudModel);
      await cloudModel.releaseModel();
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=done embedding=1 path=cloud ms=' + (Date.now() - startedAt).toString());
    } catch (error) {
      hilog.error(DOMAIN, TAG, '%{public}s',
        'stage=done embedding=0 err=local:' + localError + ' cloud:' + (error as Error).message);
    }
  }

  private static async runEmbeddingInference(model: intelligence.TextEmbedding): Promise<void> {
    const texts: string[] = [
      '导数定义',
      '函数在一点的瞬时变化率',
      '拉格朗日中值定理的条件',
      '今天天气怎么样',
    ];
    const inferStartedAt: number = Date.now();
    const vectors: Array<Array<number>> = await model.getEmbedding(texts);
    hilog.info(DOMAIN, TAG, '%{public}s',
      'stage=embedding infer ms=' + (Date.now() - inferStartedAt).toString()
        + ' dim=' + vectors[0].length.toString());
    hilog.info(DOMAIN, TAG, '%{public}s',
      'stage=embedding sim related=' + DebugCaptureRunner.cosine(vectors[0], vectors[1]).toFixed(3)
        + ' math=' + DebugCaptureRunner.cosine(vectors[1], vectors[2]).toFixed(3)
        + ' unrelated=' + DebugCaptureRunner.cosine(vectors[0], vectors[3]).toFixed(3));
  }

  /** 中文分词能力探针：关键词抽取与词性可用于纯算法相似度。 */
  static async runSegmentationProbe(ctx: common.UIAbilityContext): Promise<void> {
    const syscap: string = 'SystemCapability.AI.NaturalLanguage.TextProcessing';
    const supported: boolean = canIUse(syscap);
    hilog.info(DOMAIN, TAG, '%{public}s', 'stage=segmentation syscap=' + (supported ? '1' : '0'));
    if (!supported) {
      hilog.info(DOMAIN, TAG, '%{public}s', 'stage=done segmentation=0 err=unsupported');
      return;
    }
    const startedAt: number = Date.now();
    try {
      const inited: boolean = await textProcessing.init();
      hilog.info(DOMAIN, TAG, '%{public}s', 'stage=segmentation init=' + (inited ? '1' : '0'));
      const words: Array<textProcessing.WordSegment> = await textProcessing.getWordSegment(
        '计算 21 加 21 的结果并写出运算步骤，拉格朗日中值定理的条件是什么');
      let joined: string = '';
      for (let i = 0; i < words.length; i += 1) {
        joined += words[i].word + '/' + words[i].wordTag + ' ';
      }
      hilog.info(DOMAIN, TAG, '%{public}s', 'stage=segmentation words=' + joined);
      await textProcessing.release();
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=done segmentation=1 ms=' + (Date.now() - startedAt).toString());
    } catch (error) {
      const e: Error = error as Error;
      hilog.error(DOMAIN, TAG, '%{public}s', 'stage=done segmentation=0 err=' + e.message);
    }
  }

  private static cosine(left: Array<number>, right: Array<number>): number {
    if (left.length === 0 || left.length !== right.length) {
      return 0;
    }
    let dot: number = 0;
    let leftNorm: number = 0;
    let rightNorm: number = 0;
    for (let i = 0; i < left.length; i += 1) {
      dot += left[i] * right[i];
      leftNorm += left[i] * left[i];
      rightNorm += right[i] * right[i];
    }
    if (leftNorm <= 0 || rightNorm <= 0) {
      return 0;
    }
    return dot / (Math.sqrt(leftNorm) * Math.sqrt(rightNorm));
  }

  private static titleOfEntry(entries: LegacyDedupeEntry[], id: string): string {
    for (let i = 0; i < entries.length; i += 1) {
      if (entries[i].id === id) {
        return entries[i].titleKey;
      }
    }
    return '';
  }

  /** M3 集成自检：flag 开启时 ingestSingleText 必须经调度器包装路径返回结果（看 delta）。 */

  static async runLegacyCleanup(ctx: common.UIAbilityContext, apply: boolean): Promise<void> {
    const store: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    if (store === null) {
      hilog.error(DOMAIN, TAG, '%{public}s', 'stage=done legacyCleanup=0 err=store-null');
      return;
    }
    const startedAt: number = Date.now();
    try {
      const rs: relationalStore.ResultSet = await store.querySql(
        'SELECT id, title, subject, chapter, content, created_at FROM knowledge_unit ORDER BY created_at ASC', []);
      const entries: LegacyDedupeEntry[] = [];
      const subjectFixes: string[][] = [];
      let processed: number = 0;
      try {
        while (rs.goToNextRow()) {
          const id: string = rs.getString(rs.getColumnIndex('id'));
          const title: string = rs.getString(rs.getColumnIndex('title'));
          const subject: string = rs.getString(rs.getColumnIndex('subject'));
          const chapter: string = rs.getString(rs.getColumnIndex('chapter'));
          const content: string = rs.getString(rs.getColumnIndex('content'));
          const createdAt: number = rs.getLong(rs.getColumnIndex('created_at'));
          processed += 1;
          entries.push({ id: id, titleKey: title, contentKey: content, createdAt: createdAt });
          const input: LegacySubjectInput = {
            id: id,
            subject: subject,
            chapter: chapter,
            title: title,
            contentExcerpt: content,
          };
          const fixed: string = normalizeLegacySubject(input);
          if (fixed.length > 0 && fixed !== subject) {
            subjectFixes.push([id, subject, fixed]);
          }
        }
      } finally {
        rs.close();
      }
      for (let i = 0; i < subjectFixes.length; i += 1) {
        hilog.info(DOMAIN, TAG, '%{public}s',
          'legacy subject id=' + subjectFixes[i][0] + ' from=' + subjectFixes[i][1]
            + ' to=' + subjectFixes[i][2] + (apply ? ' apply=1' : ' apply=0'));
        if (apply) {
          await store.executeSql('UPDATE knowledge_unit SET subject = ?, updated_at = ? WHERE id = ?',
            [subjectFixes[i][2], Date.now(), subjectFixes[i][0]]);
        }
      }
      const exactGroups: LegacyDuplicateGroup[] = groupExactDuplicates(entries);
      const nearGroups: LegacyDuplicateGroup[] = groupNearDuplicates(entries);
      const seenKeep: string[] = [];
      const groups: LegacyDuplicateGroup[] = [];
      for (let i = 0; i < exactGroups.length; i += 1) {
        groups.push(exactGroups[i]);
        seenKeep.push(exactGroups[i].keepId);
      }
      for (let i = 0; i < nearGroups.length; i += 1) {
        if (seenKeep.indexOf(nearGroups[i].keepId) < 0) {
          groups.push(nearGroups[i]);
        }
      }
      // 清理只处理「同一标题归一」或「同一数学签名」的组：
      // 标题相似的泛化题名（如「解一元一次方程」系列）可能是不同题目，不自动删除；
      // 含 galaxy 预置笔记的组整组跳过，既不删种子也不删用户笔记。
      const strictGroups: LegacyDuplicateGroup[] = [];
      for (let i = 0; i < groups.length; i += 1) {
        const group: LegacyDuplicateGroup = groups[i];
        if (group.keepId.indexOf('galaxy_preview_') === 0) {
          continue;
        }
        let hasPreview: boolean = false;
        for (let k = 0; k < group.removeIds.length; k += 1) {
          if (group.removeIds[k].indexOf('galaxy_preview_') === 0) {
            hasPreview = true;
          }
        }
        if (hasPreview) {
          continue;
        }
        const baseTitle: string = DebugCaptureRunner.titleOfEntry(entries, group.keepId);
        const baseNorm: string = normalizeForDedupe(baseTitle);
        const baseSignature: string = extractMathSignature(baseTitle);
        let sameTopic: boolean = true;
        for (let k = 0; k < group.removeIds.length; k += 1) {
          const title: string = DebugCaptureRunner.titleOfEntry(entries, group.removeIds[k]);
          const norm: string = normalizeForDedupe(title);
          const signature: string = extractMathSignature(title);
          if (norm !== baseNorm && !(baseSignature.length > 0 && signature === baseSignature)) {
            sameTopic = false;
            break;
          }
        }
        if (sameTopic) {
          strictGroups.push(group);
        }
      }
      let removed: number = 0;
      let plannedRemoves: number = 0;
      const dao: NoteDao = new NoteDao(store);
      for (let i = 0; i < strictGroups.length; i += 1) {
        const group: LegacyDuplicateGroup = strictGroups[i];
        const removeTitles: string[] = [];
        for (let k = 0; k < group.removeIds.length; k += 1) {
          removeTitles.push(group.removeIds[k] + '(' + DebugCaptureRunner.titleOfEntry(entries, group.removeIds[k]) + ')');
        }
        plannedRemoves += group.removeIds.length;
        hilog.info(DOMAIN, TAG, '%{public}s',
          'legacy duplicate keep=' + group.keepId + '(' + DebugCaptureRunner.titleOfEntry(entries, group.keepId) + ')'
            + ' remove=' + removeTitles.join(',')
            + (apply ? ' apply=1' : ' apply=0'));
        if (!apply) {
          continue;
        }
        for (let k = 0; k < group.removeIds.length; k += 1) {
          try {
            await dao.deleteById(group.removeIds[k]);
            removed += 1;
          } catch (e) {
            hilog.warn(DOMAIN, TAG, 'legacy dedupe delete failed id=%{public}s %{public}s',
              group.removeIds[k], (e as Error).message);
          }
        }
      }
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=done legacyCleanup=1 apply=' + (apply ? '1' : '0')
          + ' scanned=' + processed.toString()
          + ' subjectFixes=' + subjectFixes.length.toString()
          + ' duplicateGroups=' + groups.length.toString()
          + ' strictGroups=' + strictGroups.length.toString()
          + ' duplicateNotes=' + plannedRemoves.toString()
          + ' removed=' + removed.toString()
          + ' ms=' + (Date.now() - startedAt).toString());
    } catch (error) {
      hilog.error(DOMAIN, TAG, '%{public}s',
        'stage=done legacyCleanup=0 err=' + (error as Error).message);
    }
  }

  /**
   * 旧笔记清理：删除「根本没进 note_fts」的笔记（索引异步同步被中断的批量写入产物）。
   * audit 只计数与样本；apply=true 才真正删除。
   * 注意：不要按「无 rag_chunk」删——galaxy 预置笔记和 v19 之前的笔记都没有 chunk，
   * 但它们在 note_fts 里、检索可用。
   */
  static async runRagLegacyCleanup(ctx: common.UIAbilityContext, apply: boolean): Promise<void> {
    const store: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    if (store === null) {
      hilog.error(DOMAIN, TAG, '%{public}s', 'stage=done ragLegacyCleanup=0 err=store-null');
      return;
    }
    const startedAt: number = Date.now();
    const sql: string = 'SELECT k.id AS id, k.title AS title FROM knowledge_unit k'
      + ' WHERE NOT EXISTS (SELECT 1 FROM note_fts f WHERE f.unit_id = k.id)';
    try {
      const rs: relationalStore.ResultSet = await store.querySql(sql, []);
      const ids: string[] = [];
      const samples: string[] = [];
      try {
        while (rs.goToNextRow()) {
          const id: string = rs.getString(rs.getColumnIndex('id'));
          ids.push(id);
          if (samples.length < 5) {
            samples.push(rs.getString(rs.getColumnIndex('title')) + '(' + id + ')');
          }
        }
      } finally {
        rs.close();
      }
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=rag-legacy candidates=' + ids.length.toString() + ' apply=' + (apply ? '1' : '0')
          + ' sample=' + (samples.length > 0 ? samples.join('|') : '-'));
      let removed: number = 0;
      let failed: number = 0;
      if (apply) {
        const dao: NoteDao = new NoteDao(store);
        for (let i = 0; i < ids.length; i += 1) {
          try {
            await dao.deleteById(ids[i]);
            removed += 1;
          } catch (e) {
            failed += 1;
            hilog.warn(DOMAIN, TAG, 'rag legacy delete failed id=%{public}s %{public}s',
              ids[i], (e as Error).message);
          }
        }
        await CardSnapshotService.refresh(ctx);
      }
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=done ragLegacyCleanup=1 apply=' + (apply ? '1' : '0')
          + ' candidates=' + ids.length.toString()
          + ' removed=' + removed.toString() + ' failed=' + failed.toString()
          + ' ms=' + (Date.now() - startedAt).toString());
    } catch (error) {
      hilog.error(DOMAIN, TAG, '%{public}s',
        'stage=done ragLegacyCleanup=0 err=' + (error as Error).message);
    }
  }

  private static async countWithBind(store: relationalStore.RdbStore, sql: string,
    args: Array<string | number>): Promise<number> {
    const rs: relationalStore.ResultSet = await store.querySql(sql, args);
    try {
      if (rs.goToFirstRow()) {
        return rs.getLong(rs.getColumnIndex('c'));
      }
      return 0;
    } finally {
      rs.close();
    }
  }

  /** 044 R5：召回评测。逐条跑固定查询集，输出 hit@1 / hit@5 / miss / 负样本假阳性。 */
  static async runRagEval(ctx: common.UIAbilityContext): Promise<void> {
    const store: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    if (store === null) {
      hilog.error(DOMAIN, TAG, '%{public}s', 'stage=done ragEval=0 err=store-null');
      return;
    }
    const startedAt: number = Date.now();
    const service: NoteEvidenceService = createNoteEvidenceService();
    let total: number = 0;
    let hit1: number = 0;
    let hit5: number = 0;
    let miss: number = 0;
    let negatives: number = 0;
    let falsePositives: number = 0;
    let skipped: number = 0;
    try {
      for (let i = 0; i < RAG_EVAL_CASES.length; i += 1) {
        const item: RagEvalCase = RAG_EVAL_CASES[i];
        if (item.expectTitle.length > 0) {
          const exists: number = await DebugCaptureRunner.countWithBind(store,
            'SELECT COUNT(*) AS c FROM knowledge_unit WHERE title = ?', [item.expectTitle]);
          if (exists === 0) {
            skipped += 1;
            hilog.info(DOMAIN, TAG, '%{public}s', 'stage=rag-eval-case q=' + item.query + ' skip=no-note');
            continue;
          }
        }
        total += 1;
        const context: NoteEvidenceContext = await service.build(item.query, { topK: 5, graphMode: 'none' });
        let rank: number = -1;
        for (let k = 0; k < context.citations.length; k += 1) {
          if (item.expectTitle.length > 0 && context.citations[k].title.indexOf(item.expectTitle) >= 0) {
            rank = k;
            break;
          }
        }
        if (item.expectTitle.length === 0) {
          negatives += 1;
          if (context.citations.length > 0) {
            falsePositives += 1;
          }
          hilog.info(DOMAIN, TAG, '%{public}s',
            'stage=rag-eval-case q=' + item.query + ' negative=1 citations=' + context.citations.length.toString());
          continue;
        }
        if (rank === 0) {
          hit1 += 1;
        }
        if (rank >= 0) {
          hit5 += 1;
        } else {
          miss += 1;
        }
        hilog.info(DOMAIN, TAG, '%{public}s',
          'stage=rag-eval-case q=' + item.query + ' rank=' + rank.toString()
            + ' citations=' + context.citations.length.toString());
      }
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=done ragEval=1 total=' + total.toString()
          + ' hit1=' + hit1.toString() + ' hit5=' + hit5.toString() + ' miss=' + miss.toString()
          + ' negatives=' + negatives.toString() + ' falsePositives=' + falsePositives.toString()
          + ' skipped=' + skipped.toString()
          + ' ms=' + (Date.now() - startedAt).toString());
    } catch (error) {
      hilog.error(DOMAIN, TAG, '%{public}s',
        'stage=done ragEval=0 err=' + (error as Error).message);
    }
  }

  /** App 意图规则自检（纯本地，不调模型）：逐条输出意图决策。 */

  static async runCaptureSetS3(ctx: common.UIAbilityContext): Promise<void> {
    const rawPaths: string[] = ['debug/cross-1.png', 'debug/cross-2.png'];
    const uris: string[] = [];
    for (let i = 0; i < rawPaths.length; i++) {
      uris.push(await DebugProbeSupport.materialize(ctx, rawPaths[i]));
    }
    hilog.info(DOMAIN, TAG, '%{public}s', 'stage=s3 start images=' + uris.length.toString());
    const startedAt: number = Date.now();
    const service: AiService = new AiService(ctx);
    try {
      const preview: CaptureSetPreview = await service.previewCaptureSet(uris);
      let sourcesText: string = '';
      let firstSources: number[] = [];
      if (preview.problems.length > 0) {
        firstSources = preview.problems[0].sourceImageIndexes;
        sourcesText = JSON.stringify(firstSources);
      }
      const merged: string = preview.problems.length === 1
        && firstSources.length === 2 && firstSources[0] === 0 && firstSources[1] === 1 ? '1' : '0';
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=s3 plan problems=' + preview.problems.length.toString()
          + ' sources=' + sourcesText + ' merged=' + merged
          + ' preambleSkipped=' + preview.preambleSkipped.toString());
      const all: number[] = [];
      for (let i = 0; i < preview.problems.length; i++) {
        all.push(preview.problems[i].index);
      }
      const result: CaptureSetResult = await service.commitCaptureSet(preview, all);
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=s3 commit done=' + result.done.toString() + ' failed=' + result.failed.toString()
          + ' ms=' + (Date.now() - startedAt).toString());
      hilog.info(DOMAIN, TAG, '%{public}s', 'stage=done s3=' + merged);
    } catch (error) {
      const e: Error = error as Error;
      hilog.error(DOMAIN, TAG, '%{public}s', 'stage=s3 fail err=' + e.message);
      hilog.error(DOMAIN, TAG, '%{public}s', 'stage=done s3=0');
    }
  }

  /** 036 幂等自检：同一预览提交两次，第二次应命中 commit 记录（duplicate，不重复写笔记）。 */

  static async runCaptureSetIdem(ctx: common.UIAbilityContext): Promise<void> {
    const rawPaths: string[] = ['debug/math-1.png', 'debug/math-2.png'];
    const uris: string[] = [];
    for (let i = 0; i < rawPaths.length; i++) {
      uris.push(await DebugProbeSupport.materialize(ctx, rawPaths[i]));
    }
    hilog.info(DOMAIN, TAG, '%{public}s', 'stage=idem start images=' + uris.length.toString());
    const startedAt: number = Date.now();
    const service: AiService = new AiService(ctx);
    try {
      const preview: CaptureSetPreview = await service.previewCaptureSet(uris);
      const all: number[] = [];
      for (let i = 0; i < preview.problems.length; i++) {
        all.push(preview.problems[i].index);
      }
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=idem preview setId=' + preview.setId + ' problems=' + preview.problems.length.toString());
      const first: CaptureSetResult = await service.commitCaptureSet(preview, all);
      const firstIds: string = CaptureSetResultScanner.noteIds(first);
      const second: CaptureSetResult = await service.commitCaptureSet(preview, all);
      const secondIds: string = CaptureSetResultScanner.noteIds(second);
      let duplicates: number = 0;
      for (let i = 0; i < second.items.length; i++) {
        if (second.items[i].duplicate === true) {
          duplicates += 1;
        }
      }
      const equal: string = firstIds === secondIds ? '1' : '0';
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=idem firstDone=' + first.done.toString() + ' firstIds=' + firstIds);
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=idem secondDone=' + second.done.toString() + ' secondIds=' + secondIds
          + ' duplicates=' + duplicates.toString() + ' idsEqual=' + equal);
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=done idem=' + equal + ' duplicates=' + duplicates.toString()
          + ' ms=' + (Date.now() - startedAt).toString());
    } catch (error) {
      const e: Error = error as Error;
      hilog.error(DOMAIN, TAG, '%{public}s',
        'stage=idem fail ms=' + (Date.now() - startedAt).toString() + ' err=' + e.message);
      hilog.error(DOMAIN, TAG, '%{public}s', 'stage=done idem=0');
    }
  }

  /** RAG 检索自检：对既有笔记跑 FTS（≥3字）/ LIKE（2字）两种查询。 */

  static async runRagSearch(ctx: common.UIAbilityContext): Promise<void> {
    hilog.info(DOMAIN, TAG, '%{public}s', 'stage=rag-search start');
    const startedAt: number = Date.now();
    const queries: string[] = ['连续性', '极限'];
    try {
      const searchStore: relationalStore.RdbStore | null = DatabaseHelper.getStore();
      if (searchStore === null) {
        hilog.error(DOMAIN, TAG, '%{public}s', 'stage=done ragSearch=0 err=store-null');
        return;
      }
      for (let i = 0; i < queries.length; i++) {
        const query: string = queries[i];
        const hits: RagHit[] = await RagRetrievalService.search(searchStore, query, 5);
        let firstId: string = '';
        let firstTitle: string = '';
        if (hits.length > 0) {
          firstId = hits[0].unitId;
          firstTitle = hits[0].title;
        }
        hilog.info(DOMAIN, TAG, '%{public}s',
          'stage=rag-hit q=' + query + ' hits=' + hits.length.toString()
            + ' first=' + firstId + ' title=' + firstTitle);
      }
      const chunkCount: number = await DebugProbeSupport.countRows(searchStore, 'rag_chunk');
      const ftsCount: number = await DebugProbeSupport.countRows(searchStore, 'note_fts');
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=rag-index ragChunks=' + chunkCount.toString() + ' ftsRows=' + ftsCount.toString());
      const coverage: string = await DebugCaptureRunner.noteIndexCoverage(searchStore);
      hilog.info(DOMAIN, TAG, '%{public}s', 'stage=rag-coverage ' + coverage);
      const evidenceService: NoteEvidenceService = createNoteEvidenceService();
      const evidence: NoteEvidenceContext = await evidenceService.build('连续性', { topK: 3 });
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=rag-evidence citations=' + evidence.citations.length.toString()
          + ' degraded=' + (evidence.degraded ? '1' : '0')
          + ' reason=' + evidence.reason
          + ' contextChars=' + evidence.contextText.length.toString());
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=done ragSearch=1 ms=' + (Date.now() - startedAt).toString());
    } catch (error) {
      const e: Error = error as Error;
      hilog.error(DOMAIN, TAG, '%{public}s', 'stage=done ragSearch=0 err=' + e.message);
    }
  }

  /**
   * 索引覆盖诊断：note_fts 是「尽力而为」同步（超时只告警），历史笔记可能没进索引。
   * 输出缺失条数与样本标题，用来判断是否需要补建。
   */
  static async noteIndexCoverage(store: relationalStore.RdbStore): Promise<string> {
    try {
      const total: number = await DebugProbeSupport.countRows(store, 'knowledge_unit');
      const missingFts: number = await DebugCaptureRunner.countMatching(store,
        'SELECT COUNT(*) AS c FROM knowledge_unit k WHERE NOT EXISTS'
          + ' (SELECT 1 FROM note_fts f WHERE f.unit_id = k.id)');
      const stats: string[] = [
        'notes=' + total.toString(),
        'missingFts=' + missingFts.toString(),
      ];
      if (missingFts > 0) {
        const samples: string[] = await DebugCaptureRunner.sampleRows(store,
          'SELECT k.id AS id, k.title AS title FROM knowledge_unit k WHERE NOT EXISTS'
            + ' (SELECT 1 FROM note_fts f WHERE f.unit_id = k.id)'
            + ' ORDER BY k.created_at DESC LIMIT 5');
        stats.push('missingFtsSample=' + (samples.length > 0 ? samples.join('|') : '-'));
      }
      const missingChunk: number = await DebugCaptureRunner.countMatching(store,
        "SELECT COUNT(*) AS c FROM knowledge_unit k WHERE length(trim(k.content)) > 0 AND NOT EXISTS"
          + ' (SELECT 1 FROM rag_chunk r WHERE r.unit_id = k.id)');
      stats.push('missingChunk=' + missingChunk.toString());
      return stats.join(' ');
    } catch (error) {
      return 'coverage=? err=' + (error as Error).message;
    }
  }

  private static async countMatching(store: relationalStore.RdbStore, sql: string): Promise<number> {
    const rs: relationalStore.ResultSet = await store.querySql(sql, []);
    try {
      if (rs.goToFirstRow()) {
        return rs.getLong(rs.getColumnIndex('c'));
      }
      return 0;
    } finally {
      rs.close();
    }
  }

  private static async sampleRows(store: relationalStore.RdbStore, sql: string): Promise<string[]> {
    const rs: relationalStore.ResultSet = await store.querySql(sql, []);
    const samples: string[] = [];
    try {
      while (rs.goToNextRow()) {
        samples.push(rs.getString(rs.getColumnIndex('title'))
          + '(' + rs.getString(rs.getColumnIndex('id')) + ')');
      }
    } finally {
      rs.close();
    }
    return samples;
  }

  /** e2e 辅助：统计表行数（仅调试）。 */

  static async runRagProbe(ctx: common.UIAbilityContext): Promise<void> {
    hilog.info(DOMAIN, TAG, '%{public}s', 'stage=rag-probe start');
    const startedAt: number = Date.now();
    let ftsResult: string = 'timeout';
    try {
      const probeStore: relationalStore.RdbStore | null = DatabaseHelper.getStore();
      ftsResult = probeStore === null
        ? 'fts5Ok=0 err=store-null'
        : await DebugProbeSupport.withTimeout(
          RagRetrievalService.fts5Diagnostic(probeStore), 15000, 'fts5');
    } catch (error) {
      ftsResult = 'timeout-or-error: ' + (error as Error).message;
    }
    hilog.info(DOMAIN, TAG, '%{public}s', 'stage=rag-fts ' + ftsResult);
    let kitResult: string = 'timeout';
    try {
      kitResult = await DebugProbeSupport.withTimeout(
        RagKitProbe.kitDiagnostic(ctx), 15000, 'kit');
    } catch (error) {
      kitResult = 'timeout-or-error: ' + (error as Error).message;
    }
    hilog.info(DOMAIN, TAG, '%{public}s', 'stage=rag-kit ' + kitResult);
    hilog.info(DOMAIN, TAG, '%{public}s',
      'stage=done ragProbe=1 ms=' + (Date.now() - startedAt).toString());
  }

  /**
   * 036 阶段 4 预览自检：真实 OCR + 切题 + 合并，**零落库**。
   * 关键日志：stage=preview-start / stage=preview-item（题号/来源图/复核标记）/ stage=done previewOnly=1。
   */

  static async runCaptureSetPreview(ctx: common.UIAbilityContext): Promise<void> {
    const rawPaths: string[] = ['debug/math-1.png', 'debug/math-2.png'];
    const uris: string[] = [];
    for (let i = 0; i < rawPaths.length; i++) {
      const uri: string = await DebugProbeSupport.materialize(ctx, rawPaths[i]);
      uris.push(uri);
    }
    hilog.info(DOMAIN, TAG, '%{public}s', 'stage=preview-start images=' + uris.length.toString());
    const startedAt: number = Date.now();
    const service: AiService = new AiService(ctx);
    try {
      const preview: CaptureSetPreview = await service.previewCaptureSet(uris);
      for (let k = 0; k < preview.problems.length; k++) {
        const problem: CaptureSetProblem = preview.problems[k];
        hilog.info(DOMAIN, TAG, '%{public}s',
          'stage=preview-item idx=' + problem.index.toString()
            + ' anchors=' + JSON.stringify(problem.anchors)
            + ' sources=' + JSON.stringify(problem.sourceImageIndexes)
            + ' review=' + (problem.needsReview ? '1' : '0')
            + ' textLen=' + problem.text.length.toString());
      }
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=done previewOnly=1 setId=' + preview.setId
          + ' images=' + preview.imageCount.toString()
          + ' problems=' + preview.problems.length.toString()
          + ' failedImages=' + preview.failedItems.length.toString()
          + ' preambleSkipped=' + preview.preambleSkipped.toString()
          + ' degraded=' + preview.degradedImageCount.toString()
          + ' ms=' + (Date.now() - startedAt).toString());
    } catch (error) {
      const e: Error = error as Error;
      hilog.error(DOMAIN, TAG, '%{public}s',
        'stage=fail ms=' + (Date.now() - startedAt).toString() + ' err=' + e.message);
      hilog.error(DOMAIN, TAG, '%{public}s', 'stage=done previewOnly=1 problems=0');
    }
  }

  /**
   * 036 阶段 2/3 真机自检：把 debug 图放进 captureSet（逐图 OCR → 切题 → 跨图合并 → 按题入库）。
   * 关键日志：stage=set-start images=N / stage=set-item（每题一行，含 kind/sourceImageIndexes/anchors/review）/ stage=done total/done/failed。
   */

  static async runCaptureSet(ctx: common.UIAbilityContext, withDuplicate?: boolean): Promise<void> {
    // S5：withDuplicate=true 时把第一张图再选一次，验证重拍去重。
    const rawPaths: string[] = withDuplicate === true
      ? ['debug/math-1.png', 'debug/math-2.png', 'debug/math-1.png']
      : ['debug/math-1.png', 'debug/math-2.png'];
    const uris: string[] = [];
    for (let i = 0; i < rawPaths.length; i++) {
      try {
        const uri: string = await DebugProbeSupport.materialize(ctx, rawPaths[i]);
        uris.push(uri);
        hilog.info(DOMAIN, TAG, '%{public}s', 'stage=set-pick idx=' + i.toString() + ' uri=' + uri);
      } catch (error) {
        const e: BusinessError = error as BusinessError;
        hilog.error(DOMAIN, TAG, '%{public}s',
          'stage=set-pick idx=' + i.toString() + ' ok=0 err=' + e.message);
      }
    }
    hilog.info(DOMAIN, TAG, '%{public}s', 'stage=set-start images=' + uris.length.toString());
    const startedAt: number = Date.now();
    const service: AiService = new AiService(ctx);
    try {
      const result: CaptureSetResult = await service.captureSet(uris, undefined, undefined);
      for (let k = 0; k < result.items.length; k++) {
        const item: CaptureSetItemResult = result.items[k];
        const title: string = item.title !== undefined ? item.title : '';
        const noteId: string = item.noteId !== undefined ? item.noteId : '';
        const sources: number[] = item.sourceImageIndexes !== undefined ? item.sourceImageIndexes : [];
        const anchors: string[] = item.anchors !== undefined ? item.anchors : [];
        const review: string = item.needsReview === true ? '1' : '0';
        hilog.info(DOMAIN, TAG, '%{public}s',
          'stage=set-item idx=' + item.index.toString() + ' kind=' + item.kind
            + ' ok=' + (item.success ? '1' : '0') + ' noteId=' + noteId
            + ' title=' + title + ' sources=' + JSON.stringify(sources)
            + ' anchors=' + JSON.stringify(anchors) + ' review=' + review
            + ' ms=' + item.durationMs.toString());
      }
      const setId: string = result.setId !== undefined ? result.setId : '';
      const preambleSkipped: number = result.preambleSkipped !== undefined ? result.preambleSkipped : 0;
      const degraded: number = result.degradedImageCount !== undefined ? result.degradedImageCount : 0;
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=plan setId=' + setId + ' images=' + uris.length.toString()
          + ' problems=' + result.total.toString()
          + ' preambleSkipped=' + preambleSkipped.toString()
          + ' degradedImages=' + degraded.toString());
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=done total=' + result.total.toString() + ' done=' + result.done.toString()
          + ' failed=' + result.failed.toString() + ' cancelled=' + result.cancelled.toString()
          + ' images=' + uris.length.toString()
          + ' ms=' + (Date.now() - startedAt).toString());
    } catch (error) {
      const e: Error = error as Error;
      hilog.error(DOMAIN, TAG, '%{public}s',
        'stage=fail ms=' + (Date.now() - startedAt).toString() + ' err=' + e.message);
      hilog.error(DOMAIN, TAG, '%{public}s', 'stage=done total=0 done=0 failed=1 cancelled=0');
    }
  }

  static async runSearchProbe(): Promise<void> {
    if (!ImageSearchIndexRegistry.isInstalled()) {
      hilog.warn(DOMAIN, TAG, '%{public}s', 'probe: 端口未安装');
      return;
    }
    const index = ImageSearchIndexRegistry.require();
    const cases: string[] = ['一元二次方程', '平方根'];
    for (let i = 0; i < cases.length; i++) {
      const query: string = cases[i];
      const startedAt: number = Date.now();
      const timeout: Promise<string> = new Promise<string>((resolve) => {
        setTimeout(() => resolve('timeout'), 20000);
      });
      const call: Promise<string> = index.search(query, 5)
        .then((hits: ImageSearchHit[]): string => 'hits=' + hits.length.toString())
        .catch((e: Error): string => 'err=' + e.message);
      const outcome: string = await Promise.race([call, timeout]);
      hilog.info(DOMAIN, TAG, '%{public}s',
        'probe=search q=' + query + ' ' + outcome + ' ms=' + (Date.now() - startedAt).toString());
    }
  }

  /** Worker 超时 / 异常会返回空数组而不抛错，degraded 标记由适配器实例提供 */
}

class CaptureSetResultScanner {
  static noteIds(result: CaptureSetResult): string {
    const ids: string[] = [];
    for (let i = 0; i < result.items.length; i++) {
      const item = result.items[i];
      if (item.kind === 'problem' && item.noteId !== undefined && item.noteId.length > 0) {
        ids.push(item.noteId);
      }
    }
    return ids.join(',');
  }
}
