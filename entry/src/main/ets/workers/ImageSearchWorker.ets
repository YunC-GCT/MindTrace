/**
 * ImageSearchWorker.ets — 文搜图常驻 Worker（Kit 调用从主线程搬离）
 *
 * 路径: entry/src/main/ets/workers/ImageSearchWorker.ets
 * 职责: 常驻 Worker 内持有 textSearchImage，按 { id, query, topK } 请求执行一次检索，
 *       回 { id, ok, hits?, error? }；内部串行队列保证同一时刻只有一次 Kit 调用。
 * 依赖: @kit.ArkTS(worker), @hms.ai.vision.textSearchImage
 *
 * 进程约束: 由 entry 主进程内的 ThreadWorker 加载，是 entry 主进程里的 Worker 线程，
 *           不是独立进程。Core Vision Kit 只在 main 进程可用，Worker 与主线程同进程，
 *           所以 Kit 可以在 Worker 内被调用；但不得把它搬进 AgentExtAbility / 其他进程。
 *
 * 数据流:
 *   CoreVisionImageSearchIndex.search() → ThreadWorker.postMessage({id, query, topK})
 *     → 本文件入队 → 串行出队 → textSearchImage.search(query, 'mindtrace', topK)
 *     → workerPort.postMessage({id, ok, hits, error})
 *
 * 设计要点:
 *   - 串行是硬要求：真机观测到 Kit 对连续/并发调用不安全（主线程连查第二次直接卡死），
 *     因此 onmessage 只入队，drain() 用 draining flag 保证一次只处理一条，处理完再取下一条。
 *   - init() 懒加载一次：成功置 initialized=true；失败保持 false，下一条消息会重试。
 *   - hits 的字段取法与 CoreVisionImageSearchIndex 原映射一致：imagePath / similarity，
 *     不额外发明字段（sim 取值 [-1, 1]，越大越相似）。
 *
 * ArkTS 1.1 strict 适配:
 *   - SDK 的 @hms.ai.vision.textSearchImage 只有 default export，故用 default import。
 *   - catch 里不用 `throw error as Error`；只取 message 回包，不向 Worker 外抛。
 *   - Worker 事件数据显式断言成请求/回包接口类型，不用 any / unknown。
 */

import { worker, ThreadWorkerGlobalScope, MessageEvents } from '@kit.ArkTS';
import textSearchImage from '@hms.ai.vision.textSearchImage';

const SCOPE: string = 'mindtrace';
const DEFAULT_TOP_K: number = 10;

const workerPort: ThreadWorkerGlobalScope = worker.workerPort;

interface SearchRequest {
  id: number;
  query: string;
  topK: number;
}

interface SearchHit {
  imagePath: string;
  similarity: number;
}

interface SearchReply {
  id: number;
  ok: boolean;
  hits?: SearchHit[];
  error?: string;
}

// 待处理请求 + 串行闸门：draining 为 true 时新消息只入队，由当前 drain 循环继续消费。
const queue: SearchRequest[] = [];
let draining: boolean = false;
// 一次 init 覆盖本 Worker 生命周期；失败时保持 false，下一条消息可重试。
let initialized: boolean = false;

async function ensureInit(): Promise<void> {
  if (initialized) {
    return;
  }
  const initOk: boolean = await textSearchImage.init();
  if (!initOk) {
    throw new Error('textSearchImage.init returned false');
  }
  initialized = true;
}

async function handle(request: SearchRequest): Promise<void> {
  const id: number = request.id;
  try {
    await ensureInit();
    const topK: number = request.topK > 0 ? request.topK : DEFAULT_TOP_K;
    const objects: textSearchImage.ImageObject[] =
      await textSearchImage.search(request.query, SCOPE, topK);
    const hits: SearchHit[] = [];
    for (let i = 0; i < objects.length; i++) {
      hits.push({ imagePath: objects[i].imagePath, similarity: objects[i].similarity });
    }
    const reply: SearchReply = { id: id, ok: true, hits: hits };
    workerPort.postMessage(reply);
  } catch (error) {
    const e: Error = error as Error;
    const message: string = e.message === undefined ? 'unknown worker error' : e.message;
    const reply: SearchReply = { id: id, ok: false, error: message };
    workerPort.postMessage(reply);
  }
}

/** 串行消费：一次只处理一条，handle 返回后才取下一条。 */
async function drain(): Promise<void> {
  if (draining) {
    return;
  }
  draining = true;
  try {
    while (queue.length > 0) {
      const request: SearchRequest | undefined = queue.shift();
      if (request === undefined) {
        continue;
      }
      try {
        await handle(request);
      } catch (error) {
        // handle 内部已用 ok:false 收口；这里兜底，避免一条坏消息把后续队列一起终止
      }
    }
  } finally {
    draining = false;
  }
}

workerPort.onmessage = async (event: MessageEvents): Promise<void> => {
  const request: SearchRequest = event.data as SearchRequest;
  queue.push(request);
  await drain();
};
