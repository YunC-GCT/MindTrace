/**
 * DebugCaptureRunner.ets — 批量链路自检（仅调试入口可见时使用）
 * 路径: entry/src/main/ets/services/DebugCaptureRunner.ets
 * 职责: 用 rawfile 里的样例题图跑完「取图 → OCR → 结构化 → 落库 → 卡片快照」整链，
 *       每个阶段打一条 [E2E] 日志，失败不中断后续图（与批量入口的语义一致）。
 * 依赖: AiService / CardSnapshotService / ResourceManager / CoreFileKit
 * 数据流: run(ctx) → getRawFileContent('debug/math-N.png') → cacheDir 下的 file:// →
 *        AiService.capture() → CardSnapshotService.refresh() → hilog [E2E]
 */
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ImageSearchIndexRegistry } from 'common';
import type { ImageSearchHit, KnowledgeUnit } from 'common';
import { AiService } from './AiService';
import { CardSnapshotService } from './CardSnapshotService';

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

    try {
      await DebugCaptureRunner.withTimeout(
        CardSnapshotService.refresh(ctx), CARD_TIMEOUT_MS, 'card refresh');
      hilog.info(DOMAIN, TAG, '%{public}s', 'stage=card refresh=1');
    } catch (error) {
      const e: BusinessError = error as BusinessError;
      hilog.error(DOMAIN, TAG, '%{public}s', 'stage=card refresh=0 err=' + e.message);
    }

    // 文搜图：确认落库的图片能被自然语言命中
    if (ImageSearchIndexRegistry.isInstalled()) {
      // 刚 insert 完立刻 search，Kit 偶发不返回（真机实测）；先等索引落盘，失败再重试一次
      // 索引写入是异步的：insert 返回后 Kit 还在建，这时 search 会阻塞主线程（真机实测）
      await DebugCaptureRunner.sleep(8000);
      // 只查一次：真机上同进程第二次 search 会在原生层阻塞主线程（连 8s 定时器都不触发），
      // 这是 Kit 的已知风险，v1 自检只验证「能不能被命中」，不做连续检索。
      const queries: string[] = ['一元二次方程'];
      for (let i = 0; i < queries.length; i++) {
        const query: string = queries[i];
        try {
          hilog.info(DOMAIN, TAG, '%{public}s', 'stage=search-start q=' + query);
          const hits: ImageSearchHit[] = await DebugCaptureRunner.searchWithRetry(query);
          let detail: string = '';
          if (hits.length > 0) {
            const best: ImageSearchHit = hits[0];
            const slash: number = best.imagePath.lastIndexOf('/');
            detail = ' best=' + (slash >= 0 ? best.imagePath.substring(slash + 1) : best.imagePath)
              + ' sim=' + best.similarity.toString();
          }
          hilog.info(DOMAIN, TAG, '%{public}s',
            'stage=search q=' + query + ' hits=' + hits.length.toString() + detail);
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
