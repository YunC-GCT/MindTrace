/**
 * ImageSearchProbeWorker.ets — S1 探针：验证 Core Vision Kit 能否在 Worker 线程内工作
 *
 * 路径: entry/src/main/ets/workers/ImageSearchProbeWorker.ets
 * 职责: 接收 { query }，模块级 flag 保证只 init 一次，再执行一次 textSearchImage.search，
 *       回传 { ok, count } 或 { ok: false, error }。
 * 进程约束: 仅由 entry 的 ThreadWorker 加载（同进程非 UI 线程）；不得进 common barrel，
 *          也不得被 agent / agentUI 入口可达。结论出来前不要接进生产路径。
 * 依赖: @kit.ArkTS(worker), @hms.ai.vision.textSearchImage
 *
 * 数据流:
 *   ImageSearchWorkerProbe.postMessage({query}) → workerPort.onmessage
 *     → textSearchImage.init()/search() → workerPort.postMessage({ok, count|error})
 *
 * ArkTS 1.1 strict 适配:
 *   - SDK 的 @hms.ai.vision.textSearchImage 只有 default export，故用 default import；
 *     同名具名导出只存在于 @kit.CoreVisionKit 的 re-export。
 *   - catch 里不用 `throw error as Error`；init 失败抛 new Error(...)，其余取 message 回包。
 */

import { worker, ThreadWorkerGlobalScope, MessageEvents } from '@kit.ArkTS';
import textSearchImage from '@hms.ai.vision.textSearchImage';

const SCOPE: string = 'mindtrace';
const TOP_K: number = 5;

const workerPort: ThreadWorkerGlobalScope = worker.workerPort;
// 一次 init 覆盖本 Worker 生命周期；init 失败时保持 false，下一条消息可重试
let initialized: boolean = false;

interface ProbeRequest {
  query: string;
}

interface ProbeReply {
  ok: boolean;
  count?: number;
  error?: string;
}

workerPort.onmessage = async (event: MessageEvents): Promise<void> => {
  const request: ProbeRequest = event.data;
  const query: string = request.query;
  try {
    if (!initialized) {
      const initOk: boolean = await textSearchImage.init();
      if (!initOk) {
        throw new Error('textSearchImage.init returned false');
      }
      initialized = true;
    }
    const hits: textSearchImage.ImageObject[] = await textSearchImage.search(query, SCOPE, TOP_K);
    const reply: ProbeReply = { ok: true, count: hits.length };
    workerPort.postMessage(reply);
  } catch (error) {
    const e: Error = error as Error;
    const message: string = e.message === undefined ? 'unknown worker error' : e.message;
    const reply: ProbeReply = { ok: false, error: message };
    workerPort.postMessage(reply);
  }
};
