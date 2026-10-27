# spike #240：父子图共享 RunContext / deadline / 取消

**Status:** `concluded-with-FAIL`（2026-10-27）
**票：** [#240](https://github.com/YunC-GCT/MindTrace/issues/240)
**分支 / 基线：** `feature/v7-contracts` @ `e39dec7`
**探针：** [`scripts/spikes/v7-run-context-spike.mjs`](../../../../scripts/spikes/v7-run-context-spike.mjs)
**执行状态：** **已运行**（编排会话，2026-10-27）。沙箱内 `pwsh` 启动前失败（`SetNamedSecurityInfoW failed (Win32 5)`），故改为由编排会话在主机上执行同一探针；四问实测输出见 §0.1，与下文的静态取证结论逐条一致。

> 验收口径来自 [`tasks.md`](./tasks.md) §#240 的四个问题原文。`review-report.md` 在当前 bundle 中不存在，本文件承担其内容；不新建该文件。
> 本 spike 未改任何生产 `.ets`、未新增依赖、未 commit。

## 0. 方法与证据边界

- 探针用现成 loader（[`note-review-ets-loader.mjs`](../../../../scripts/arkts-lint/tests/note-review-ets-loader.mjs) 的 `ts.transpileModule` + `vm`）装载真实的 `StateGraph.ets`，并用同一份 `StateGraph` 实例 mock `common` 后装载真实的 `CaptureGraph.ets`。因此它测的是生产代码，不是复制品。
- 本会话的 shell 被 Windows 沙箱 ACL 挡住，探针未能在会话内运行；改由**编排会话在主机上执行同一脚本**，实测输出见 §0.1。下文四节的静态取证与实测逐条一致，两条证据链都保留。
- loader 跨 `vm` realm，`instanceof` 在测试里天然不可靠。Q3 只用 `name` / 自有字段（`kind` / `step` / `retriable`）判断，不把 harness 假象写成产品缺陷。
- Q4 按任务口径只做静态取证；仓库现状没有 Worker 图节点，因此该问无适用对象。

## 0.1 探针实测输出（编排会话，主机执行）

命令：`node scripts/spikes/v7-run-context-spike.mjs`（退出码 0）

```
Q1 FAIL StateGraph fields=[]; token only via state; kernelBubble=true trace={"parent":["p1","p2"],"child":["child1","child2"]}; CaptureGraph cancel->kind=NODE_ERROR retriable=false parentContinued=true
Q2 FAIL parentBudget=4 parentRuns=3 childRuns=3 total=6 combinedThrew=false; childBudget=4 childRan=4 childError=MAX_NODE_RUNS parentRunsBeforeChild=1
Q3 FAIL kernelPreserved=true name=CaptureGraphError kind=LLM_UNAVAILABLE step=child1 retriable=true; CaptureGraph boundary kind=NODE_ERROR step=capture retriable=false
Q4 PASS addNodeFiles=8 workerMarkedGraphFiles=[]; 现状无 Worker 节点，此项无适用对象; nearest protocols plain=ChatPersistenceWorker.ets:27-43/true ImageSearchWorker.ets:39-55/true
SUMMARY blocking=3 total=4
DECISION stop: any FAIL/NEEDS-CHANGE means no #241; go back to section 17 and revise.
```

读法（与下文四节逐个对应）：

- **Q1**：`StateGraph` 实例上没有任何上下文字段（`fields=[]`）；裸内核确实会向上冒泡（`kernelBubble=true`，父图只跑了 `p1/p2`、子图跑了 `child1/child2` 就停），但生产子图 `CaptureGraph` 把取消压成 `NODE_ERROR(retriable=false)`，且**父图继续跑**（`parentContinued=true`）—— 取消既不分类也不传播。
- **Q2**：父预算 4，父图跑 3 次 + 子图跑 3 次 = **6 次**，父图的 `MAX_NODE_RUNS` 从未触发（`combinedThrew=false`）；反向测试里子图在自己的第 5 次抛 `MAX_NODE_RUNS`，而父图预算仍有剩余 —— 两个计数器互不可见。
- **Q3**：裸内核保留领域错误（`kernelPreserved=true`，`kind=LLM_UNAVAILABLE`、`step=child1`、`retriable=true` 全在）；到 `CaptureGraph` 边界变成 `kind=NODE_ERROR`、`retriable=false`。**压平发生在 CaptureGraph，不在 StateGraph**。
- **Q4**：含 `.addNode(` 的 8 个文件都没有 Worker 标记；最近的 Worker 协议是纯字段接口。

## Q1：子图能拿到父图 `runId` / `deadline` / `CancellationToken`，且取消能冒泡

### 现状（文件:行）

- `StateGraph` 只持图结构，不持 run 上下文：字段仅有 `startStep` / `endStep` / `haltWhen` / `nodes` / `edges` / `conditionalEdges`（`common/src/main/ets/workflow/StateGraph.ets:19-32`）；`run(initialState, maxNodeRuns = 128)` 没有 context / deadline / token 参数（`:55`）。
- 全仓 `common/src/main/ets/workflow/` 下没有 `runId` / `deadline` / `RunContext` 定义。`AgentTask.deadline` 只有类型声明（`common/src/main/ets/models/CommonTypes.ets:123-131`），工作流没有消费它。
- token 只能靠调用方手工塞进泛型 State：`AgentState.cancellationToken?`（`agents/src/main/ets/graph/AgentState.ets:52`）；`Dispatcher` 在构造初始 state 时放入（`agents/src/main/ets/core/Dispatcher.ets:132-140`），`DispatchOptions` 本身没有 `runId` / `deadline` 字段（`:72-82`）。
- `CaptureGraph` 在每个节点前后检查 token（`agents/src/main/ets/graph/CaptureGraph.ets:37`、`:39`），但 `catch` 把任何异常统一改写成 `NODE_ERROR`、`retriable: false`（`:41-43`）。`CancellationToken.throwIfCancelled()` 抛的是通用 `Error('CONVERSATION_CANCELLED')`（`common/src/main/ets/llm/CancellationToken.ets:41-45`），到子图边界已经无法与普通节点错误区分。
- A2A 的 35s deadline 是 entry 层的 `setTimeout`，到点调用同一个 token 的 `cancel()`（`entry/src/main/ets/agentextability/AgentExtAbility.ets:320-329`）；它不是图参数，也没有传进 `StateGraph`。
- `Dispatcher` 在入口和 `graph.run` 返回后各查一次 token（`agents/src/main/ets/core/Dispatcher.ets:120`、`:143`），但图内取消已经被 `CaptureGraph` 吞成 `NODE_ERROR`。

### 实验（怎么测的）

探针 `q1()` 构造父图三节点 `p1 → p2 → p3`，`p2` 内部 `await child.run(...)`：

1. **kernel 形态**：子图是裸 `StateGraph`；子图中间节点先 `token.cancel()`，再自己 `throwIfCancelled()`。观察子图后续节点是否停止、父图 `p3` 是否停止、父图 `catch` 收到什么。
2. **生产形态**：子图是真实 `CaptureGraph`，节点内 `cancel()` 后正常返回；`CaptureGraph` 的节点包装器会在 `:39` 检查并抛，随后被 `:41-43` 改写成 `NODE_ERROR`。观察父图拿到的是异常还是带 `error` 的 state。
3. **上下文可得性**：检查 `StateGraph` 实例上是否存在 `runId` / `deadline` / `token` 字段，并核对 `StateGraph.run` 签名。

实测见 §0.1 的 `Q1` 行：`CaptureGraph cancel->kind=NODE_ERROR retriable=false parentContinued=true`，与上述静态取证一致。

### 结论：FAIL

- `CancellationToken` **可以**通过 `AgentState` 手工传递，节点也会协作检查；这部分是“能拿 token”，但不是图契约，子图必须自己记得从 state 取。
- `runId` / `deadline` **拿不到**：`StateGraph` 没有这两个字段，`DispatchOptions` 也没有；A2A deadline 只体现为 token 取消，子图无法知道还剩多少时间。
- 取消**不能可靠冒泡**：裸 `StateGraph` 只有在节点自己把异常抛出来时才会向上冒；真实子图 `CaptureGraph` 会在 `:41-43` 把取消改写成 `NODE_ERROR(retriable=false)`，父图看到的是一个普通失败 state，无法区分“用户取消”和“节点出错”。ADR-0019 也把这条列为现状缺陷（`docs/adr/0019-note-command-and-outcome.md:15`、`:128`、`:147`）。

三项是合取条件，`runId` / `deadline` 缺失且取消被吞，因此判 **FAIL**。

### 若为否，最小改动提案

新增 `common/src/main/ets/workflow/RunContext.ets`（提案，不落生产文件）：

```ts
import { CancellationToken } from '../llm/CancellationToken';

export class RunBudget {
  limit: number;
  used: number = 0;

  constructor(limit: number) {
    this.limit = limit;
  }

  hasRemaining(): boolean {
    return this.used < this.limit;
  }

  take(): void {
    this.used += 1;
  }
}

export interface RunContextInit {
  runId: string;
  parentRunId?: string;
  deadlineAt: number;
  token: CancellationToken;
  maxNodeRuns?: number;
}

export class RunContext {
  readonly runId: string;
  readonly parentRunId?: string;
  readonly deadlineAt: number;
  readonly token: CancellationToken;
  readonly budget: RunBudget;

  constructor(init: RunContextInit) {
    this.runId = init.runId;
    this.parentRunId = init.parentRunId;
    this.deadlineAt = init.deadlineAt;
    this.token = init.token;
    this.budget = new RunBudget(init.maxNodeRuns ?? 128);
  }

  throwIfStopped(now: number = Date.now()): void {
    this.token.throwIfCancelled();
    if (now >= this.deadlineAt) {
      throw new Error('RUN_DEADLINE_EXCEEDED');
    }
  }
}
```

`StateGraph.run` 增加可选第三参，并在每个节点前后检查：

```ts
async run(initialState: State, maxNodeRuns: number = 128, context?: RunContext): Promise<State> {
  let state: State = initialState;
  let current: Step = this.next(this.startStep, state);
  const budget: RunBudget = context === undefined ? new RunBudget(maxNodeRuns) : context.budget;
  while (current !== this.endStep) {
    if (context !== undefined) {
      context.throwIfStopped();
    }
    if (!budget.hasRemaining()) {
      throw new StateGraphError('Workflow exceeded shared maxNodeRuns=' + budget.limit.toString(),
        'MAX_NODE_RUNS', current);
    }
    const node: StateGraphNode<State> | undefined = this.nodes.get(current);
    if (node === undefined) {
      throw new StateGraphError('Missing workflow node: ' + current, 'INVALID_GRAPH', current);
    }
    state = await node(state);
    budget.take();
    if (context !== undefined) {
      context.throwIfStopped();
    }
    if (this.haltWhen !== undefined && this.haltWhen(state)) {
      return state;
    }
    current = this.next(current, state);
  }
  return state;
}
```

配套改动点：

- `agents/src/main/ets/graph/CaptureGraph.ets`：`run(initialState, context?: RunContext)` 把 context 继续传给 `this.graph.run(...)`；`addNode` 的 catch 重新抛出取消/领域错误（见 Q3），不要改写成 `NODE_ERROR`；`run` 的 catch 也要放行 `RUN_DEADLINE_EXCEEDED`（否则会被 `INVALID_GRAPH` 吞掉）。
- `agents/src/main/ets/core/Dispatcher.ets`：`DispatchOptions` 增加 `runContext?: RunContext`（或 `runId` + `deadlineAt` 二字段），capture 分支创建一次 context 并只创建一次；`graph.run` 与子图节点共用同一个对象。
- 取消到终态：`Dispatcher` 捕获 `CONVERSATION_CANCELLED` 后返回 `cancelled(committed: false)`；若写已落库则按 ADR-0019 返回 `cancelled(committed: true)`，具体由 persist / `NoteWritePort` 判定（`docs/adr/0019-note-command-and-outcome.md:121-131`）。
- deadline 到点抛 `RUN_DEADLINE_EXCEEDED`，由 `Dispatcher` 映射为 `TIMEOUT` / `A2A_DEADLINE_EXCEEDED`；不要在子图边界重新起计时器。

## Q2：`maxNodeRuns` 父子累计

### 现状（文件:行）

- `StateGraph.run()` 每次进入都执行 `let nodeRuns: number = 0`（`common/src/main/ets/workflow/StateGraph.ets:58`），上限是本次调用的 `maxNodeRuns`（默认 128，`:55`），每次成功节点后 `nodeRuns += 1`（`:68`）。
- 子图调用 `child.run(state, 4)` 会开启一份新的局部 `nodeRuns`，与父图的计数互不可见；没有共享可变 budget。
- `CaptureGraph.run(initialState)` 只接收初始 state（`agents/src/main/ets/graph/CaptureGraph.ets:61-64`），内部 `this.graph.run(state)` 使用默认 128（`:64`）；即使父图想传预算，也没有参数入口。
- `Dispatcher` 的 capture 分支也是 `graph.run(initial)`（`agents/src/main/ets/core/Dispatcher.ets:142`），没有显式预算。

### 实验（怎么测的）

探针 `q2()`：

1. 父图 3 节点，`p2` 调 `child.run(state, 4)`；子图 3 节点。记录父/子各自执行次数与总次数，看父图预算 4 是否会在总次数第 5 次时抛 `MAX_NODE_RUNS`。
2. 反向：子图 5 节点、`child.run(state, 4)`，父图只先跑 1 个节点；看子图是否在自己的第 5 个节点抛出 `MAX_NODE_RUNS`，而父图预算仍未用完。

实测见 §0.1 的 `Q2` 行：`parentBudget=4 parentRuns=3 childRuns=3 total=6 combinedThrew=false`，与上述静态取证一致。

### 结论：FAIL

`nodeRuns` 是 `run()` 的局部变量，每次调用重置；“父子累计”没有实现，两个图各算各的。按现状，父图 `run(state, 4)` 里再调 `child.run(state, 4)`，实际可执行节点数会超过 4，且父图的 `MAX_NODE_RUNS` 不会触发；这正是 ADR-0008 在 `docs/adr/0008-capturegraph-self-built-runtime.md:33` 记录的现状。

### 若为否，最小改动提案

复用 Q1 的 `RunBudget`，父图创建一次、子图透传同一个对象：

```ts
// parent
const context = new RunContext({
  runId: runId,
  deadlineAt: deadlineAt,
  token: token,
  maxNodeRuns: 4,
});
await parent.run(state, context);

// parent node that invokes a child
parent.addNode('child_node', async (input: AgentState): Promise<AgentState> => {
  return await child.run(input, context);
});
```

- `StateGraph.run` 以 `context.budget` 为唯一计数源，父子都调用同一个 `budget.take()`；没有 context 时保持现有局部计数，避免一次性改所有调用方。
- `CaptureGraph.run` 增加 `context?: RunContext` 并透传，不再使用内部的默认 128。
- `Dispatcher` 创建 context 时把预算显式设为当前 capture 的预算；不要在两处各写一个 `maxNodeRuns`。
- 测试落在 `common/src/test/StateGraph.test.ets`，新增 `parent_and_child_share_one_budget`：父 3 节点 + 子 3 节点、共享 limit 4，应在总第 5 次前抛 `MAX_NODE_RUNS`。

## Q3：领域错误穿子图边界不被压成 `Error`

### 现状（文件:行）

- `CaptureGraphError` 目前是 **interface**，不是 class：`kind` / `message` / `step` / `retriable` / `cause?`（`agents/src/main/ets/graph/AgentState.ets:26-32`）。因此任务描述里的 `throw new CaptureGraphError(...)` 在当前代码中并不存在，节点实际是构造对象字面量或抛别的 `Error`。
- `CaptureGraph.addNode` 的包装器 `catch` 只取 `message`（`agents/src/main/ets/graph/CaptureGraph.ets:42`），然后统一 `withError(..., 'NODE_ERROR', message, step, false)`（`:43`）。`kind` / `step` / `retriable` 全部丢失，连 `cause` 都没有保留。
- `CaptureGraph.run` 的 `catch` 只把 `StateGraphError` 映射成 `INVALID_GRAPH`（`agents/src/main/ets/graph/CaptureGraph.ets:65-68`）；节点内的领域错误到不了这里，因为上一层已经吞掉。
- `Dispatcher` 拿到 `finalState.error` 后只把 `error.message` 放进 `DispatchResult.errorMessage`（`agents/src/main/ets/core/Dispatcher.ets:144-152`），`kind` / `retriable` 也没有继续传。
- 裸 `StateGraph` 不做 `try/catch`：`state = await node(state)`（`common/src/main/ets/workflow/StateGraph.ets:67`），所以如果边界就是 `StateGraph.run`，对象会原样冒出。问题出在 `CaptureGraph` 这层生产包装。

### 实验（怎么测的）

探针 `q3()`：

1. 裸 `StateGraph` 子图节点 `throw new ProbeDomainError('LLM_UNAVAILABLE', 'child1', true, 'rate limited')`；父图节点 `await child.run(...)` 并 `catch`，检查 `name` / `kind` / `step` / `retriable` 是否还在。
2. 真实 `CaptureGraph` 子图节点抛同样形状的错误；检查 `child.run(...)` 返回的 `state.error` 里 `kind` / `step` / `retriable` 变成了什么。
3. 因为 `CaptureGraphError` 是 interface，探针用一个同字段的 class 作为 stand-in；判定只看 `name` 和自有字段，不看 `instanceof`。

实测见 §0.1 的 `Q3` 行：`kernelPreserved=true ... CaptureGraph boundary kind=NODE_ERROR step=capture retriable=false`，与上述静态取证一致。

### 结论：FAIL

- 裸 `StateGraph`：领域错误可以原样穿过，`kind` / `step` / `retriable` 保留（`:67` 没有 catch）。
- 真实子图 `CaptureGraph`：所有节点异常都被压成 `NODE_ERROR(retriable=false)`，`kind` 变成 `'NODE_ERROR'`，`step` 只是当前 `CaptureStep`，原始 `retriable` 丢失（`agents/src/main/ets/graph/CaptureGraph.ets:41-43`）。父图拿到的是普通失败 state，不是领域错误。
- 这正是 ADR-0008 在“子图的领域错误穿边界不被压成 `Error`”一条里点名的现状（`docs/adr/0008-capturegraph-self-built-runtime.md:32`），也是 ADR-0019 要求 `CaptureGraph` 停止 flatten 的原因（`docs/adr/0019-note-command-and-outcome.md:147`）。

因此按“生产子图边界”判 **FAIL**；不能把裸 `StateGraph` 的通过当成产品通过。

### 若为否，最小改动提案

把 `CaptureGraphError` 从 interface 升级为 class（或保留 interface + 增加显式 type guard），并让 `CaptureGraph` 只吞未知错误：

```ts
// agents/src/main/ets/graph/AgentState.ets (proposal)
export class CaptureGraphError extends Error {
  kind: string;
  step: CaptureStep;
  retriable: boolean;
  cause?: Object;

  constructor(kind: string, message: string, step: CaptureStep, retriable: boolean, cause?: Object) {
    super(message);
    this.name = 'CaptureGraphError';
    this.kind = kind;
    this.step = step;
    this.retriable = retriable;
    this.cause = cause;
  }
}
```

```ts
// agents/src/main/ets/graph/CaptureGraph.ets (proposal)
} catch (e) {
  if (e instanceof CaptureGraphError) {
    throw e;
  }
  if (e instanceof CancellationError) {
    throw e;
  }
  if (e instanceof Error && e.message === 'CONVERSATION_CANCELLED') {
    throw e;
  }
  const message: string = e instanceof Error ? e.message : String(e);
  return this.withError(nodeInput, 'NODE_ERROR', message, step, false);
}
```

配套改动点：

- `agents/src/main/ets/graph/CaptureGraph.ets:65-68`：`run` 的 catch 同样先重抛 `CaptureGraphError` / `CancellationError`，只把真正的图结构错误映射成 `INVALID_GRAPH`。
- 所有 `CaptureGraphError` 对象字面量改为 `new CaptureGraphError(...)`：至少 `CaptureGraph.ets:99-101`、`Dispatcher.ets:1664-1669`，以及各 node 里的 error 构造点。
- `common/src/main/ets/llm/CancellationToken.ets`：把 `throw new Error('CONVERSATION_CANCELLED')` 换成专用的 `CancellationError`（或保留 message，但由 `CaptureGraph` 显式识别），这样取消不再依赖字符串匹配。
- `agents/src/main/ets/core/Dispatcher.ets:144-152`：捕获 `CaptureGraphError` 后把 `kind` / `retriable` 写入 `DispatchResult`（#241 迁移到 `NoteOutcome.failed(code, retryable)`），不要只留 `message`。
- 需要同步 `agents/src/test/CaptureGraph.test.ets:190-199` 的 `NODE_ERROR` 期望；该测试目前把“节点抛错 → NODE_ERROR”固定成行为，改语义时必须一起改。

## Q4：Worker 节点只传可序列化数据

### 现状（文件:行）

- 全仓 `.ets` 中带 `.addNode(` 的文件共 8 个、调用点 44 处；这些文件没有同时出现 `ThreadWorker` / `workerPort` / `postMessage`。图节点装配的集中位置是 `agents/src/main/ets/core/Dispatcher.ets:1646-1684`（逐节点 `addNode`）和 `agents/src/main/ets/graph/CaptureGraph.ets:50`（包装后交给 `StateGraph`）。
- 仓库里存在 Worker，但它们不是图节点：
  - `entry/src/main/ets/workers/ChatPersistenceWorker.ets:27-50`：`ChatWorkerRequest` / `ChatWorkerResponse` / `ChatWorkerSnapshot` 都是纯字段接口；`:92` 直接 `const request: ChatWorkerRequest = event.data`，`:107-121` 再 `JSON.stringify(snapshot)`。
  - 调用方 `entry/src/main/ets/services/ChatHistoryPersistence.ets:896-905`：`postMessage` 的是 `{ kind, path, sessions, historyEpoch }` 普通对象。
  - `entry/src/main/ets/workers/ImageSearchWorker.ets:39-55`：`SearchRequest` / `SearchHit` / `SearchReply` 都是 `string` / `number` / `boolean` / 数组；`:85-86` `postMessage` 回包。
  - 客户端镜像 `entry/src/main/ets/services/CoreVisionImageSearchIndex.ets:42-58` 同样只有纯字段；`:189-191` 创建 `ThreadWorker`。
- 这些协议里没有 `CancellationToken`、`runId`、`deadline`、class 实例或闭包。

### 实验（怎么测的）

探针 `q4()` 只做静态扫描：递归读取仓库 `.ets`（跳过 `node_modules` / `oh_modules` / `build` / `.git` / `.hvigor`），收集含 `.addNode(` 的文件，并标记同时含 `ThreadWorker` / `workerPort` / `postMessage` 的文件；再检查最近的两个 Worker 协议是不是纯接口。

本会话未执行扫描脚本；这一问按任务允许的“静态取证”人工核对，证据见上。

### 结论：PASS（现状无适用对象）

仓库现状**没有 Worker 图节点**，因此“Worker 节点只传可序列化数据”没有适用对象；最近的 Worker 协议本身是纯数据结构。此项不构成 #241 的失败项，但它也不能证明未来新增的 Worker 节点会自动满足约束。

### 若为否，最小改动提案

不适用。若 #241 之后引入 Worker 图节点，约束应写成：

```ts
// 允许跨线程的载荷：只放原始值和普通对象
interface WorkerNodeInput {
  runId: string;
  deadlineAt: number;
  text: string;
}

// 禁止：CancellationToken（含监听器闭包）、AgentState、LlmClient、DAO、class 实例
```

取消不要靠“把 token 传进 Worker”；应由主线程 `postMessage({ kind: 'cancel', runId })` 并在超时后 `terminate()`，Worker 只回纯数据结果。这样才与 Q1 的 `RunContext` 不冲突。

## 总判决

| 问 | 结论 | 关键证据 |
|---|---|---|
| Q1 `runId` / `deadline` / token + 取消冒泡 | **FAIL** | `StateGraph.ets:19-32`、`:55` 无 context；`CaptureGraph.ets:41-43` 吞取消 |
| Q2 `maxNodeRuns` 父子累计 | **FAIL** | `StateGraph.ets:58` 每次 `run` 重置 `nodeRuns` |
| Q3 领域错误穿子图边界 | **FAIL** | `CaptureGraph.ets:41-43` 只保留 message，压成 `NODE_ERROR` |
| Q4 Worker 节点只传可序列化数据 | **PASS（无适用对象）** | 无 Worker 图节点；协议为纯接口 |

四问中 **Q1 / Q2 / Q3 为 FAIL**。按 [`tasks.md`](./tasks.md) §#240 的口径原样执行：

> **任一 FAIL → 停，不进 #241，回 §17 改方案。**

因此本票结论是 **不进 #241**。即使只修 Q1/Q2/Q3 也需要先回 `docs/system-architecture-layered.md` §17 定方案（`RunContext` 形状、预算归属、领域错误与取消的边界），再重跑本探针；不要在本 spike 里直接改生产 `.ets`。

另外，#241 还依赖 #238，而 #238 的 `NoteReadPort`、`ArtifactStorePort`、`RunStore` 生产适配器等仍未完成（[`tasks.md`](./tasks.md):18-29）；即使本 spike 通过，也不具备直接开工条件。

## 未验证项

- 沙箱会话内 `node scripts/spikes/v7-run-context-spike.mjs` 未能运行（ACL）；**编排会话已在主机执行并贴出四条 `Q<n>` 输出与 `SUMMARY blocking=3 total=4`**（§0.1），Q1-Q3 的静态判定与实测一致，Q4 为静态扫描（探针同样只用静态扫描）。
- 未跑 ArkTS 编译 / `agent-gate` / 真机；本 spike 不改生产文件，构建影响应为零，但未实测。
- 未验证真实 `CaptureGraph` 在 `Dispatcher` 调用链里的取消时序（`Dispatcher.ets:143` 的二次检查、`PersistNode` 写后检查）；这些属于 #241 的等价性验证。
- 未验证未来 Worker 节点；当前仓库没有该对象。
