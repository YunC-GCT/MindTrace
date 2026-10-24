// ============================================================================
//  services/CoreVisionImageSearchIndex.ets — textSearchImage 适配器
//  ----------------------------------------------------------------------------
//  Process: main only. 不得被 agent / agentUI 入口可达，也不得进 common barrel；
//  Kit 只允许在 UI 进程加载 (spec 033 R2/R3)。
//  路径: entry/src/main/ets/services/CoreVisionImageSearchIndex.ets
//  职责: 承接 @kit.CoreVisionKit 的 textSearchImage (API 26) 调用, 对 common 端口
//        暴露「插图片 / 按文字搜 / 删 / 清」四件事, 并把 Kit 的异常码翻译成日志。
//  依赖: @kit.CoreVisionKit (textSearchImage), common 端口契约
//  数据流: AiService.capture → ImageSearchIndexRegistry.require().insert(path)
//          → textSearchImage.insertImage(path, 'mindtrace')
//  实测约束 (SDK d.ts):
//    - imagePath: 沙箱内绝对路径, ≤128 字符; 不接受 file:// 前缀
//    - scope: 只允许字母/数字, ≤32 字符; 同一 scope 内的图片互相竞争
//    - search: query 允许中文, topKey 0..100, 默认 100
//    - 错误码: 1013100001 路径非法 / 1013100002 服务异常 / 1013100003 能力已更新(需 clearData)
// ============================================================================

import { textSearchImage } from '@kit.CoreVisionKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import type { ImageSearchHit, ImageSearchIndex } from 'common';

const DOMAIN: number = 0xC5D0;
const TAG: string = 'ImageSearch';
// scope 只允许字母和数字, 且 ≤32 字符; 换 scope 等于换一个独立索引库。
const SCOPE: string = 'mindtrace';
/** 检索单次上限：正常 50ms~1.5s，超过 8s 视为 Kit 阻塞 */
const SEARCH_TIMEOUT_MS: number = 8000;
const DEFAULT_TOP_K: number = 10;

export class CoreVisionImageSearchIndex implements ImageSearchIndex {
  private initialized: boolean = false;

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
    await this.ensureInit();
    const limit: number = topK === undefined ? DEFAULT_TOP_K : topK;
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
