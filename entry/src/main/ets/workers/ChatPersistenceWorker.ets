/**
 * ChatPersistenceWorker.ets — 聊天持久化 Worker fallback 能力探针
 *
 * 路径: entry/src/main/ets/workers/ChatPersistenceWorker.ets
 * 职责: 响应主线程能力探针,验证 Worker 构建接线与请求/响应失败语义。
 * 依赖: @kit.ArkTS(worker)。
 *
 * 数据流:
 *   ThreadWorker.postMessage → workerPort.onmessage → workerPort.postMessage
 *
 * ArkTS 1.1 strict 适配:
 *   - Worker 消息协议使用固定 string 常量,不使用 any/unknown 或动态对象访问。
 */

import { MessageEvents, ThreadWorkerGlobalScope, worker } from '@kit.ArkTS';

const WORKER_SUCCESS_REQUEST: string = 'worker-capability-success';
const WORKER_SUCCESS_RESPONSE: string = 'worker-capability-ok';
const WORKER_FAILURE_RESPONSE: string = 'worker-capability-error';

const workerPort: ThreadWorkerGlobalScope = worker.workerPort;

workerPort.onmessage = (event: MessageEvents): void => {
  const request: string = event.data;
  const response: string = request === WORKER_SUCCESS_REQUEST
    ? WORKER_SUCCESS_RESPONSE
    : WORKER_FAILURE_RESPONSE;
  workerPort.postMessage(response);
};
