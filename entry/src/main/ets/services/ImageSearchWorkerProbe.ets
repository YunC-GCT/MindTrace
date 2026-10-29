/**
 * ImageSearchWorkerProbe.ets — S1 探针：主线程编排 Worker 侧文搜图可用性验证
 *
 * 路径: entry/src/main/ets/services/ImageSearchWorkerProbe.ets
 * 职责: 启动 ImageSearchProbeWorker，依次发两条 query，每条最多等 10000ms，
 *       汇总「两条都 ok=true 且 count>0」是否成立，供 e2e=worker 分支记录结论。
 * 进程约束: 仅 entry UI 进程调用；只做探针，不改生产检索路径。
 * 依赖: @kit.ArkTS(worker), @kit.PerformanceAnalysisKit(hilog)
 *
 * 数据流:
 *   EntryAbility.runE2eIfRequested(e2e=worker) → run()
 *     → ThreadWorker.postMessage({query}) → ImageSearchProbeWorker → onmessage
 *     → hilog [E2E] probe=worker ... → return boolean
 *
 * 这是 S1 探针：验证 Kit 能否在 Worker 里工作；结论出来前不要把它接进生产路径。
 *
 * ArkTS 1.1 strict 适配:
 *   - Worker 回包是异步的，主线程维护单个 pending resolver，用 Promise.race + setTimeout
 *     按顺序等每条回包；超时只记一条 timeout 并继续下一条，不向方法外抛错。
 */

import { worker, MessageEvents } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'E2E';
const DOMAIN: number = 0xE2E0;
const WORKER_SCRIPT: string = 'entry/ets/workers/ImageSearchProbeWorker.ets';
const PROBE_TIMEOUT_MS: number = 10000;
const PROBE_QUERIES: string[] = ['一元二次方程', '平方根'];

interface ProbeRequest {
  query: string;
}

interface ProbeReply {
  ok: boolean;
  count?: number;
  error?: string;
}

export class ImageSearchWorkerProbe {
  static async run(): Promise<boolean> {
    const w: worker.ThreadWorker = new worker.ThreadWorker(WORKER_SCRIPT);
    // 同一时刻只等一条回包；回包与超时都通过 pendingResolve + Promise.race 收口
    let pendingResolve: ((reply: ProbeReply | undefined) => void) | undefined = undefined;
    let allOk: boolean = true;

    w.onmessage = (event: MessageEvents): void => {
      const resolve: ((reply: ProbeReply | undefined) => void) | undefined = pendingResolve;
      pendingResolve = undefined;
      if (resolve !== undefined) {
        const reply: ProbeReply = event.data;
        resolve(reply);
      }
    };
    // Worker 加载失败 / 消息处理异常时也要收口，否则主线程只能干等到超时
    w.onAllErrors = (): void => {
      const resolve: ((reply: ProbeReply | undefined) => void) | undefined = pendingResolve;
      pendingResolve = undefined;
      if (resolve !== undefined) {
        const failed: ProbeReply = { ok: false, error: 'worker onAllErrors' };
        resolve(failed);
      }
    };

    try {
      for (let i = 0; i < PROBE_QUERIES.length; i++) {
        const query: string = PROBE_QUERIES[i];
        const startedAt: number = Date.now();
        let timer: number = -1;
        const response: Promise<ProbeReply | undefined> =
          new Promise<ProbeReply | undefined>((resolve): void => {
            pendingResolve = (reply: ProbeReply | undefined): void => {
              if (reply !== undefined) {
                resolve(reply);
              }
            };
          });
        const timeout: Promise<ProbeReply | undefined> =
          new Promise<ProbeReply | undefined>((resolve): void => {
            timer = setTimeout((): void => {
              resolve(undefined);
            }, PROBE_TIMEOUT_MS);
          });
        let reply: ProbeReply | undefined = undefined;
        try {
          const request: ProbeRequest = { query: query };
          w.postMessage(request);
          reply = await Promise.race([response, timeout]);
        } catch (error) {
          reply = undefined;
        } finally {
          clearTimeout(timer);
          pendingResolve = undefined;
        }

        const elapsed: number = Date.now() - startedAt;
        if (reply === undefined) {
          allOk = false;
          hilog.warn(DOMAIN, TAG, '%{public}s',
            'probe=worker q=' + query + ' timeout ms=' + PROBE_TIMEOUT_MS.toString());
        } else {
          const count: number = reply.count === undefined ? 0 : reply.count;
          if (!reply.ok || count <= 0) {
            allOk = false;
          }
          hilog.info(DOMAIN, TAG, '%{public}s',
            'probe=worker q=' + query + ' ok=' + (reply.ok ? 'true' : 'false')
              + ' count=' + count.toString() + ' ms=' + elapsed.toString());
          if (!reply.ok && reply.error !== undefined) {
            hilog.warn(DOMAIN, TAG, '%{public}s',
              'probe=worker q=' + query + ' error=' + reply.error);
          }
        }
      }
    } finally {
      w.terminate();
    }
    return allOk;
  }
}
