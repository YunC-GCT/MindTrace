// ============================================================================
//  services/CoreVisionImageSearchIndex.ets — textSearchImage 适配器
//  ----------------------------------------------------------------------------
//  Process: main only. 不得被 agent / agentUI 入口可达，也不得进 common barrel；
//  Kit 只允许在 UI 进程加载 (spec 033 R2/R3)。
//  路径: entry/src/main/ets/services/CoreVisionImageSearchIndex.ets
//  职责: 承接 @kit.CoreVisionKit 的 textSearchImage (API 26) 调用, 对 common 端口
//        暴露「插图片 / 按文字搜 / 删 / 清」四件事, 并把 Kit 的异常码翻译成日志。
//        检索 (search) 走常驻 Worker 客户端，避免 Kit 连续调用同步阻塞主线程（#230）；
//        insert / remove / clear 仍在主线程直调（写入未观测到阻塞）。
//  依赖: @kit.CoreVisionKit (textSearchImage), @kit.ArkTS(worker), common 端口契约
//  数据流: AiService.capture → ImageSearchIndexRegistry.require().insert(path)
//          → textSearchImage.insertImage(path, 'mindtrace')
//          search → ThreadWorker('entry/ets/workers/ImageSearchWorker.ets')
//          → postMessage({id, query, topK}) → 5s 超时则 terminate + 重建
//  实测约束 (SDK d.ts):
//    - imagePath: 沙箱内绝对路径, ≤128 字符; 不接受 file:// 前缀
//    - scope: 只允许字母/数字, ≤32 字符; 同一 scope 内的图片互相竞争
//    - search: query 允许中文, topKey 0..100, 默认 100
//    - 错误码: 1013100001 路径非法 / 1013100002 服务异常 / 1013100003 能力已更新(需 clearData)
// ============================================================================

import { textSearchImage } from '@kit.CoreVisionKit';
import { worker, MessageEvents } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import type { ImageSearchHit, ImageSearchIndex } from 'common';

const DOMAIN: number = 0xC5D0;
const TAG: string = 'ImageSearch';
// scope 只允许字母和数字, 且 ≤32 字符; 换 scope 等于换一个独立索引库。
const SCOPE: string = 'mindtrace';
/** 主线程直调单次上限：正常 50ms~1.5s，超过 8s 视为 Kit 阻塞 */
const SEARCH_TIMEOUT_MS: number = 8000;
/** Worker 检索单次上限：超时直接 terminate + 重建，返回空结果降级，绝不冻主线程 */
const WORKER_SEARCH_TIMEOUT_MS: number = 5000;
const DEFAULT_TOP_K: number = 10;
const WORKER_SCRIPT: string = 'entry/ets/workers/ImageSearchWorker.ets';
/** 现场对比开关：false 退回主线程直调（今天的行为）；两条路径都要能编译。 */
const USE_WORKER: boolean = true;

interface SearchRequest {
  id: number;
  query: string;
  topK: number;
}

interface WorkerSearchHit {
  imagePath: string;
  similarity: number;
}

interface WorkerSearchReply {
  id: number;
  ok: boolean;
  hits?: WorkerSearchHit[];
  error?: string;
}

export class CoreVisionImageSearchIndex implements ImageSearchIndex {
  private initialized: boolean = false;
  // 常驻 Worker：懒创建并复用，超时 / Worker 异常后置空，下一条请求自动重建。
  private workerInstance: worker.ThreadWorker | null = null;
  // 按请求 id 找回 pending resolver，避免 Worker 回包串到别的 query 上。
  private pending: Map<number, (reply: WorkerSearchReply | null) => void> =
    new Map<number, (reply: WorkerSearchReply | null) => void>();
  private nextRequestId: number = 1;
  private degraded: boolean = false;

  /** 供自检记录 degraded=<bool>；每次 search 开始时重置。 */
  lastSearchDegraded(): boolean {
    return this.degraded;
  }

  isAvailable(): boolean {
    return canIUse('SystemCapability.AI.Vision.VisionBase');
  }

  async insert(imagePath: string): Promise<boolean> {
    const path: string = this.normalizePath(imagePath);
    await this.ensureInit();
    try {
      const ok: boolean = await textSearchImage.insertImage(path, SCOPE);
      hilog.info(DOMAIN, TAG, '%{public}s', 'insert ok=' + (ok ? '1' : '0') + ' path=' + this.tail(path));
      return ok;
    } catch (error) {
      this.logError('insert', error);
      throw new Error(this.describe(error));
    }
  }

  async search(query: string, topK?: number): Promise<ImageSearchHit[]> {
    const limit: number = topK === undefined ? DEFAULT_TOP_K : topK;
    this.degraded = false;
    if (!USE_WORKER) {
      return this.searchOnMainThread(query, limit);
    }
    return this.searchInWorker(query, limit);
  }

  /** USE_WORKER=false 时的回退路径：与搬 Worker 前完全一致（现场对比用）。 */
  private async searchOnMainThread(query: string, limit: number): Promise<ImageSearchHit[]> {
    await this.ensureInit();
    try {
      // 真机实测：连续第二次 search 可能永不返回（首次 1.4s 正常，紧接着那条一直挂着）。
      // 文搜图是 best-effort，超时就当没命中，绝不能把批量链路拖死。
      const objects: textSearchImage.ImageObject[] =
        await this.withTimeout(textSearchImage.search(query, SCOPE, limit), SEARCH_TIMEOUT_MS, 'search');
      const hits: ImageSearchHit[] = [];
      for (let i = 0; i < objects.length; i++) {
        hits.push({ imagePath: objects[i].imagePath, similarity: objects[i].similarity });
      }
      hilog.info(DOMAIN, TAG, '%{public}s',
        'search query=' + query + ' topK=' + limit.toString() + ' hits=' + hits.length.toString());
      return hits;
    } catch (error) {
      this.logError('search', error);
      throw new Error(this.describe(error));
    }
  }

  /**
   * Worker 客户端：发一条请求，按 id 等回包。
   * 5000ms 没回包就 terminate + 清空 pending + 置空 Worker，返回空数组（不 throw）。
   */
  private searchInWorker(query: string, limit: number): Promise<ImageSearchHit[]> {
    const w: worker.ThreadWorker | null = this.acquireWorker();
    if (w === null) {
      this.degraded = true;
      return Promise.resolve<ImageSearchHit[]>([]);
    }
    const id: number = this.nextRequestId;
    this.nextRequestId += 1;
    const request: SearchRequest = { id: id, query: query, topK: limit };
    return new Promise<ImageSearchHit[]>((resolve) => {
      let timer: number = -1;
      const resolver = (reply: WorkerSearchReply | null): void => {
        if (timer !== -1) {
          clearTimeout(timer);
          timer = -1;
        }
        this.pending.delete(id);
        if (reply === null) {
          resolve([]);
          return;
        }
        if (!reply.ok) {
          this.degraded = true;
          hilog.warn(DOMAIN, TAG, '%{public}s',
            '[ImageSearch] search degraded reason=worker-error q=' + query
              + ' err=' + (reply.error === undefined ? 'unknown' : reply.error));
          resolve([]);
          return;
        }
        const hits: ImageSearchHit[] = this.mapHits(reply.hits);
        hilog.info(DOMAIN, TAG, '%{public}s',
          'search source=worker query=' + query + ' topK=' + limit.toString()
            + ' hits=' + hits.length.toString());
        resolve(hits);
      };
      this.pending.set(id, resolver);
      timer = setTimeout((): void => {
        // 超时可能意味着 Kit 在 Worker 内也卡住：直接丢弃这个 Worker，别让下一条再排队等着。
        this.degrade('timeout', query);
        resolve([]);
      }, WORKER_SEARCH_TIMEOUT_MS);
      try {
        w.postMessage(request);
      } catch (error) {
        if (timer !== -1) {
          clearTimeout(timer);
          timer = -1;
        }
        this.pending.delete(id);
        this.degraded = true;
        this.logError('worker-post', error);
        resolve([]);
      }
    });
  }

  /** 懒创建并复用同一个 ThreadWorker；onmessage 按 id 找 pending resolver。 */
  private acquireWorker(): worker.ThreadWorker | null {
    const existing: worker.ThreadWorker | null = this.workerInstance;
    if (existing !== null) {
      return existing;
    }
    try {
      const created: worker.ThreadWorker = new worker.ThreadWorker(WORKER_SCRIPT);
      created.onmessage = (event: MessageEvents): void => {
        const reply: WorkerSearchReply = event.data as WorkerSearchReply;
        this.onReply(reply);
      };
      // Worker 加载失败 / 处理异常时不能只让请求干等：按降级收口，下一条重建。
      // 只处理当前实例：超时 terminate 时的回调可能晚到，不能把刚重建的 Worker 再清掉。
      created.onAllErrors = (): void => {
        if (this.workerInstance === created) {
          this.degrade('worker-error', '');
        }
      };
      this.workerInstance = created;
      hilog.info(DOMAIN, TAG, '%{public}s', 'worker created script=' + WORKER_SCRIPT);
      return created;
    } catch (error) {
      this.logError('worker-create', error);
      return null;
    }
  }

  private onReply(reply: WorkerSearchReply): void {
    const resolver: ((reply: WorkerSearchReply | null) => void) | undefined = this.pending.get(reply.id);
    if (resolver === undefined) {
      return;
    }
    this.pending.delete(reply.id);
    resolver(reply);
  }

  /** 丢弃当前 Worker、清空 pending（全部按空结果收口），下一条请求重建。 */
  private degrade(reason: string, query: string): void {
    this.degraded = true;
    const w: worker.ThreadWorker | null = this.workerInstance;
    this.workerInstance = null;
    if (w !== null) {
      try {
        w.terminate();
      } catch (error) {
        this.logError('worker-terminate', error);
      }
    }
    const resolvers: ((reply: WorkerSearchReply | null) => void)[] = [];
    this.pending.forEach((resolver: (reply: WorkerSearchReply | null) => void): void => {
      resolvers.push(resolver);
    });
    this.pending.clear();
    for (let i = 0; i < resolvers.length; i++) {
      resolvers[i](null);
    }
    hilog.warn(DOMAIN, TAG, '%{public}s',
      '[ImageSearch] search degraded reason=' + reason + (query.length > 0 ? ' q=' + query : ''));
  }

  /** 照原映射逻辑把 Worker 回包转成端口命中原语：imagePath / similarity。 */
  private mapHits(objects: WorkerSearchHit[] | undefined): ImageSearchHit[] {
    const hits: ImageSearchHit[] = [];
    if (objects === undefined) {
      return hits;
    }
    for (let i = 0; i < objects.length; i++) {
      hits.push({ imagePath: objects[i].imagePath, similarity: objects[i].similarity });
    }
    return hits;
  }

  /** 包一层超时；超时抛错由上层 catch 记 warn */
  private async withTimeout<T>(task: Promise<T>, ms: number, label: string): Promise<T> {
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

  async remove(imagePath: string): Promise<boolean> {
    const path: string = this.normalizePath(imagePath);
    await this.ensureInit();
    try {
      return await textSearchImage.deleteImage(path, SCOPE);
    } catch (error) {
      this.logError('remove', error);
      throw new Error(this.describe(error));
    }
  }

  async clear(): Promise<boolean> {
    await this.ensureInit();
    try {
      return await textSearchImage.clearData();
    } catch (error) {
      this.logError('clear', error);
      throw new Error(this.describe(error));
    }
  }

  /** init 幂等: 能力在一次进程生命周期内只需初始化一次, 失败则下次调用重试。 */
  private async ensureInit(): Promise<void> {
    if (this.initialized) {
      return;
    }
    if (!this.isAvailable()) {
      throw new Error('CoreVisionKit textSearchImage is not supported on this device');
    }
    const ok: boolean = await textSearchImage.init();
    if (!ok) {
      throw new Error('CoreVisionKit textSearchImage init failed');
    }
    this.initialized = true;
    hilog.info(DOMAIN, TAG, '%{public}s', 'init ok scope=' + SCOPE);
  }

  private normalizePath(uri: string): string {
    return uri.startsWith('file://') ? uri.substring('file://'.length) : uri;
  }

  /** 日志只留路径尾部, 避免把整条沙箱路径刷进 hilog。 */
  private tail(path: string): string {
    const index: number = path.lastIndexOf('/');
    return index >= 0 ? path.substring(index + 1) : path;
  }

  /** ArkTS 不允许 `throw error as Error`；把 code/message 抽成新 Error 再抛 */
  private describe(error: Error): string {
    const e: BusinessError = error as BusinessError;
    return (e.code === undefined ? '' : 'code=' + e.code.toString() + ' ') + e.message;
  }

  private logError(op: string, error: Error): void {
    const e: BusinessError = error as BusinessError;
    hilog.error(DOMAIN, TAG, '%{public}s',
      op + ' failed code=' + (e.code === undefined ? '?' : e.code.toString()) + ' msg=' + e.message);
  }
}
