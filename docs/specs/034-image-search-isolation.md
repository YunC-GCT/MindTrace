# 034 文搜图检索的线程隔离（修复 #230）

Status: accepted（2026-10-25）
Refs: #230、#227（OCR 端口化）、033（进程边界）

## 1. 现象与既有证据

真机 MRO-W00 / HarmonyOS 26 / API 26：

| 场景 | 结果 |
|---|---|
| 冷启后只查一次（insert 后等 8s） | `hits=5`，50ms~1.4s，连续两轮 PASS |
| 同一轮里连查两次（`一元二次方程`、`平方根`） | 第一次正常返回；第二次 `stage=search-start` 之后再无任何日志，300s 超时 |
| 第二次调用时 adapter 的 `Promise.race(…, 8000)` | **没有触发** |

`Promise.race` 的定时器不触发只有一个解释：**JS 线程被同步占住**，事件循环停转，所以这不是「Promise 不 resolve」，而是「原生调用把主线程 block 住了」。

## 2. 根因假设（按可能性排序）

- **H1 索引写入锁**：`insertImage` 返回后 Kit 仍在后台建索引，native 侧持锁；此时 `search` 在**调用线程**上阻塞等待锁。证据方向：把 insert 与 search 的间隔从 8s 拉到 30s，阻塞应消失或概率下降。
- **H2 会话状态损坏**：同一进程内第二次 `search` 触发 Kit 内部重新建会话/重连 `TextServiceAbility`，IPC 同步等待且永不返回；`release()` + `init()` 重建会话应能恢复。
- **H3 线程亲和性**：Kit 只在「主线程 + 有 UI 上下文」时正常工作，换线程/换进程行为未定义。
- **H4 与 insert 无关的偶发**：纯 search 场景（无 insert）也会偶发第二次阻塞。

## 3. 可区分假设的实验

| 编号 | 做法 | 判读 |
|---|---|---|
| E1 | 只 search 两次，不 insert，中间 sleep 2s；再跑一遍 sleep 30s | 两次都卡 → H4；拉长间隔后不卡 → H1 |
| E2 | 两次 search 用不同 scope（`mindtrace` / `mindtrace2`） | 仍卡 → 与 scope 锁无关（偏 H2/H4） |
| E3 | 第二次前 `release()` + `init()` | 不卡 → H2 |
| E4 | 把两次 search 放进 Worker | Worker 卡但 UI 不卡 → 隔离有效（方案 B 成立） |
| E5 | 卡住时抓栈：`hdc shell "hidumper -s 401 -a '-p <pid>'"` / `hdc shell "hstack <pid>"` | 直接看 native 栈，能定位是锁等待还是 IPC |

E5 是最强证据，但需要卡住的现场；E1–E4 都能在自检里做成开关，跑一轮就有结论。

## 4. 方案对比

| 方案 | 改动 | 代价 | 能否不冻 UI |
|---|---|---|---|
| A 单飞 + 重入保护 | adapter 内只允许一个 search 在飞，第二次直接返回「忙」；已有 8s 超时保留 | 小 | **不能**。本例第二次调用是串行发的，不是并发；单飞挡不住同步阻塞 |
| B Worker / TaskPool 隔离 | 检索跑在 Worker，主线程只等回调；超时 5s 直接降级 | 中（新增 worker 文件 + 消息协议） | **能**（前提：Kit 在 Worker 可用，见 E4/S1） |
| C 每次 search 前 release+init | adapter 内重建会话 | 小 | 不能（若阻塞发生在 init 内部） |
| D 独立进程承载检索 | 新增无 UI 的 HAP/Ability，跨进程调用 | 大（IPC、生命周期、装机多一件） | 能，但 v1 过重 |

## 5. 推荐

**B 为主线，A 作兜底，D 只在 B 被证伪时启用。**

理由：v1 的验收标准是「检索可用 + 不冻 UI」，只有换线程能满足；A 保不住 UI，C 只是换触发点。B 的风险是 Kit 的线程亲和性（H3），所以先用 S1 探针证伪/证实，再决定是否落到 D。

### S1 探针（先做，决定路线）

`entry/src/main/ets/workers/ImageSearchProbeWorker.ets`：

```ts
import { worker, ThreadWorkerGlobalScope, MessageEvents, ErrorEvent } from '@kit.ArkTS';
import { textSearchImage } from '@hms.ai.vision.textSearchImage';

const scope: ThreadWorkerGlobalScope = worker.workerPort;

scope.onmessage = async (e: MessageEvents): Promise<void> => {
  const query: string = e.data.query as string;
  try {
    await textSearchImage.init();
    const hits = await textSearchImage.search(query, 'mindtrace', 5);
    scope.postMessage({ ok: true, count: hits.length });
  } catch (err) {
    scope.postMessage({ ok: false, error: (err as Error).message });
  }
};
```

主线程侧 `new worker.ThreadWorker('entry/ets/workers/ImageSearchProbeWorker.ets')`，发两条 query，各等 10s。

- 两条都回 → B 成立，按 §6 实现。
- Worker 起不来（Kit 在 Worker 内不可用 / 加载即崩）→ 记结论，v1 只保留「自检里单次检索」，UI 接入推迟，另开票走 D。

## 6. 实施清单（B 成立时）

1. `common/src/main/ets/capability/imagesearch/ImageSearchIndex.ets`：端口签名不变，新增 `ImageSearchBusyError`（或返回 `hits: []` + `degraded: true`）。
2. `entry/src/main/ets/workers/ImageSearchWorker.ets`：持有 `textSearchImage`，串行处理消息队列（一次只处理一条），`init` 懒加载一次。
3. `entry/src/main/ets/services/CoreVisionImageSearchIndex.ets`：改成 Worker 客户端——`search()` 发消息、`Promise.race` 5s、超时 `worker.terminate()` 并重建、返回空结果并标记降级；`insert`/`remove` 保持主线程直调（写入阻塞未观测到）。
4. `entry/src/main/ets/services/DebugCaptureRunner.ets`：恢复两次检索（`一元二次方程`、`平方根`），断言两次都有 `hits>0`；超时/降级要打 `probe=degraded reason=`。
5. `docs/specs/033-process-boundaries.md`：RESTRICTED 表补一行说明「Kit 在 Worker（同进程非 UI 线程）可用性由 S1 结论决定」。

## 7. 验收

- 真机：`node scripts/e2e-capture/run.mjs` → `stage=done ok=2 failed=0`，且两条 `stage=search` 都有 `hits>=1`，`判定: PASS`。
- 负向：把 Worker 超时改成 50ms 跑一轮，必须看到 `degraded` 且**主线程仍在打日志**（证明没冻）。
- 单测：`scripts/image-search-port/tests/` 增加「adapter 不直接 import Kit」与「超时返回降级而非抛出」两条断言。

## 8. 风险与回退

- Worker 内 Kit 不可用 → 立即回退到「自检单次检索」，#230 保持 open，另开 D 方案票。
- Worker 常驻内存开销 → 空闲 60s 自动 `terminate()`。
- 回退开关：`ImageSearchIsolation.USE_WORKER = false` 时退回主线程直调（保持今天的行为，便于现场对比）。
