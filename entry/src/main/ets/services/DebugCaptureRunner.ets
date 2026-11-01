/**
 * DebugCaptureRunner.ets — 批量链路自检（仅调试入口可见时使用）
 * 路径: entry/src/main/ets/services/DebugCaptureRunner.ets
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
import { AiService } from './AiService';
import { CardSnapshotService } from './CardSnapshotService';
import { CoreVisionImageSearchIndex } from './CoreVisionImageSearchIndex';
import { CaptureReceipt, CaptureReceiptStore } from './CaptureReceipt';
import { RagHit, RagRetrievalService } from './RagRetrievalService';
import { RagKitProbe } from './RagKitProbe';
import { AgentIngestService, AgentTextBatchResult } from './AgentIngestService';
import { AgentImagePart } from './AgentImageParts';
import { AgentIngestRequest, buildIngestRequest, INGEST_SOURCE_XIAOYI } from './AgentIngestRequest';
import {
  A2APlan,
  A2APlanItem,
  buildA2APlanItems,
  formatA2APlanProgress,
  formatA2APlanSummary,
  nextPlanItem,
  remainingPlanCount,
} from './A2APlanModels';
import { A2APlanStore } from './A2APlanStore';
import { NoteEvidenceService } from './NoteEvidenceService';
import { NoteEvidenceContext } from '../models/NoteEvidenceModels';

const TAG: string = 'E2E';
const DOMAIN: number = 0xE2E0;
// 平台调用偶发不返回（updateForm / search 都遇到），自检每一步都限时，先保证有结论
const CAPTURE_TIMEOUT_MS: number = 150000;
const CARD_TIMEOUT_MS: number = 15000;

export class DebugCaptureRunner {
  /** 返回人类可读的结果串，调用方直接 Toast */
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
        const uri: string = await DebugCaptureRunner.materialize(ctx, rawPaths[i]);
        hilog.info(DOMAIN, TAG, '%{public}s', 'stage=pick seq=' + seq + ' uri=' + uri);

        const unit: KnowledgeUnit = await DebugCaptureRunner.withTimeout(
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
      await DebugCaptureRunner.withTimeout(
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
      await DebugCaptureRunner.sleep(8000);
      const queries: string[] = ['一元二次方程', '平方根'];
      for (let i = 0; i < queries.length; i++) {
        const query: string = queries[i];
        const startedAt: number = Date.now();
        try {
          hilog.info(DOMAIN, TAG, '%{public}s', 'stage=search-start q=' + query);
          const hits: ImageSearchHit[] = await DebugCaptureRunner.searchWithRetry(query);
          const elapsed: number = Date.now() - startedAt;
          hilog.info(DOMAIN, TAG, '%{public}s',
            'stage=search q=' + query + ' hits=' + hits.length.toString() + ' ms=' + elapsed.toString());
          if (hits.length === 0) {
            // 0 命中可能是真没命中，也可能是 Worker 超时/异常降级；分开打给 e2e 判定
            hilog.warn(DOMAIN, TAG, '%{public}s',
              'stage=search q=' + query + ' hits=0 degraded='
                + (DebugCaptureRunner.isSearchDegraded() ? 'true' : 'false')
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
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=done audit=1 notes=' + count.toString() + ' duplicatePairs=' + dup.toString()
          + ' notesWithBlankSections=' + blankFields.toString());
    } catch (error) {
      hilog.error(DOMAIN, TAG, '%{public}s', 'stage=done audit=0 err=' + (error as Error).message);
    }
  }

  /** A2A 图片 OCR checkpoint 自检：OCR → 规划（不写库）→ 第一题入库。 */
  static async runAgentImagePlan(ctx: common.UIAbilityContext): Promise<void> {
    const startedAt: number = Date.now();
    try {
      const localPath: string = await DebugCaptureRunner.materialize(ctx, 'debug/math-1.png');
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
      await A2APlanStore.save(ctx, plan);
      hilog.info(DOMAIN, TAG, '%{public}s', 'stage=image-plan checkpoint saved (未写库)');
      const outcome: NoteOutcome = await AgentIngestService.ingestSingleText(ctx, first.text);
      if (outcome.kind !== 'committed' || outcome.unit === undefined) {
        hilog.error(DOMAIN, TAG, '%{public}s', 'stage=done imagePlan=0 err=ingest kind=' + outcome.kind);
        return;
      }
      plan.done.push(first.index);
      await A2APlanStore.save(ctx, plan);
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=image-plan progress=' + formatA2APlanProgress(plan, first, outcome.unit.title, outcome.unit.subject).split('\n')[0]);
      await A2APlanStore.clear(ctx);
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
      await A2APlanStore.save(ctx, plan);
      const loaded: A2APlan | null = await A2APlanStore.load(ctx);
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
      await A2APlanStore.save(ctx, loaded);
      const progress: string = formatA2APlanProgress(loaded, first, outcome.unit.title, outcome.unit.subject);
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=plan-progress remaining=' + remainingPlanCount(loaded).toString()
          + ' first=' + progress.split('\n')[0]);
      await A2APlanStore.clear(ctx);
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
  static async runCaptureSetS3(ctx: common.UIAbilityContext): Promise<void> {
    const rawPaths: string[] = ['debug/cross-1.png', 'debug/cross-2.png'];
    const uris: string[] = [];
    for (let i = 0; i < rawPaths.length; i++) {
      uris.push(await DebugCaptureRunner.materialize(ctx, rawPaths[i]));
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
      uris.push(await DebugCaptureRunner.materialize(ctx, rawPaths[i]));
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
      const chunkCount: number = await DebugCaptureRunner.countRows(searchStore, 'rag_chunk');
      const ftsCount: number = await DebugCaptureRunner.countRows(searchStore, 'note_fts');
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=rag-index ragChunks=' + chunkCount.toString() + ' ftsRows=' + ftsCount.toString());
      const evidenceService: NoteEvidenceService = new NoteEvidenceService();
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

  /** e2e 辅助：统计表行数（仅调试）。 */
  private static async countRows(store: relationalStore.RdbStore, table: string): Promise<number> {
    try {
      const rs: relationalStore.ResultSet = await store.querySql('SELECT COUNT(*) AS c FROM ' + table, []);
      try {
        if (rs.goToFirstRow()) {
          return rs.getLong(rs.getColumnIndex('c'));
        }
        return 0;
      } finally {
        rs.close();
      }
    } catch (error) {
      return -1;
    }
  }

  /** RAG 能力探针：FTS5 与 Kit 各自带超时，保证一定给出结论。 */
  static async runRagProbe(ctx: common.UIAbilityContext): Promise<void> {
    hilog.info(DOMAIN, TAG, '%{public}s', 'stage=rag-probe start');
    const startedAt: number = Date.now();
    let ftsResult: string = 'timeout';
    try {
      const probeStore: relationalStore.RdbStore | null = DatabaseHelper.getStore();
      ftsResult = probeStore === null
        ? 'fts5Ok=0 err=store-null'
        : await DebugCaptureRunner.withTimeout(
          RagRetrievalService.fts5Diagnostic(probeStore), 15000, 'fts5');
    } catch (error) {
      ftsResult = 'timeout-or-error: ' + (error as Error).message;
    }
    hilog.info(DOMAIN, TAG, '%{public}s', 'stage=rag-fts ' + ftsResult);
    let kitResult: string = 'timeout';
    try {
      kitResult = await DebugCaptureRunner.withTimeout(
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
      const uri: string = await DebugCaptureRunner.materialize(ctx, rawPaths[i]);
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
        const uri: string = await DebugCaptureRunner.materialize(ctx, rawPaths[i]);
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
  private static isSearchDegraded(): boolean {
    const index = ImageSearchIndexRegistry.require();
    if (index instanceof CoreVisionImageSearchIndex) {
      return index.lastSearchDegraded();
    }
    return false;
  }

  /** search 失败等 500ms 再试一次：索引刚写入时首次检索可能不返回 */
  private static async searchWithRetry(query: string): Promise<ImageSearchHit[]> {
    let lastError: string = '';
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        return await ImageSearchIndexRegistry.require().search(query, 5);
      } catch (error) {
        lastError = (error as BusinessError).message ?? 'unknown';
        hilog.warn(DOMAIN, TAG, '%{public}s',
          'search attempt=' + attempt.toString() + ' q=' + query + ' err=' + lastError);
        await DebugCaptureRunner.sleep(500);
      }
    }
    throw new Error(lastError);
  }

  private static async withTimeout<T>(task: Promise<T>, ms: number, label: string): Promise<T> {
    let timer: number = -1;
    const timeout: Promise<T> = new Promise<T>((_resolve, reject) => {
      timer = setTimeout(() => {
        reject(new Error(label + ' 超时 ' + ms.toString() + 'ms'));
      }, ms);
    });
    try {
      return await Promise.race([task, timeout]);
    } finally {
      clearTimeout(timer);
    }
  }

  private static async sleep(ms: number): Promise<void> {
    await new Promise<void>((resolve) => {
      setTimeout(() => resolve(), ms);
    });
  }

  /** rawfile → 缓存目录，返回 file:// URI（capture 的 ImageUriResolver 能吃这个形式） */
  private static async materialize(ctx: common.UIAbilityContext, rawPath: string): Promise<string> {
    const bytes: Uint8Array = await ctx.resourceManager.getRawFileContent(rawPath);
    const name: string = rawPath.substring(rawPath.lastIndexOf('/') + 1);
    const path: string = ctx.cacheDir + '/e2e-' + name;
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, bytes.buffer as ArrayBuffer);
    } finally {
      fileIo.closeSync(file);
    }
    return 'file://' + path;
  }
}

// 036 幂等自检辅助：按题目顺序拼 noteId 串（空值跳过，便于两次提交对比）。
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
