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
import type { CaptureSetItemResult, CaptureSetPreview, CaptureSetProblem, CaptureSetResult, ImageSearchHit, KnowledgeUnit } from 'common';
import { AiService } from './AiService';
import { CardSnapshotService } from './CardSnapshotService';
import { CoreVisionImageSearchIndex } from './CoreVisionImageSearchIndex';
import { CaptureReceipt, CaptureReceiptStore } from './CaptureReceipt';
import { RagHit, RagRetrievalService } from './RagRetrievalService';
import { RagKitProbe } from './RagKitProbe';
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
