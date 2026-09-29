# CaptureGraph Agent Workflow 架构 �?演进 / 现状 / Drift

> **Date**: 2026-09-16
> **Scope**: MindTrace 后端 agent workflow �?(a) 演进历史 + 当前架构 + drift; (b) **工具�?* 完整拓扑 (ToolRegistry / ToolLoop / wire / MCP); (c) **10 �?agent / workflow 的设计模式判�?* (ReAct / Reflexion / Plan-Execute / Router / Pipeline / Pure function �?�?> **方式**: 不复制粘�? 按章节重�? 引用回到原文 + 代码行号。Drift 节并�?"doc vs code" 已核�?仍未核实�?> **Author note**: 全部论断�?`path:LINE` 引用或指�?docs/ 子目录�?
---

## 1. 一句话定位 + 范围

MindTrace 后端 agent workflow 是一�?*正在持续完善�?agent 工作流框�?*, 当前�?ArkTS 自研�?`StateGraph<State, Step>` 内核为底�? 承载 **4 个生�?workflow**: CaptureGraph / ToolCallingWorkflow / ConversationWorkflow / SkillIntentWorkflow�?*LangGraph 是当前所借用的设计模型参�?* (Node / Edge / State / conditional edge / START/END 等词�?, 不是运行时依�?�?评估过的 Python sidecar LangGraph 路径未采�?(�?§3.2), 当前自研 88 LOC 内核�?*项目的长期目�?*是把 §10 drift 14 �?+ §5.6 RAG 4 模式 + §3.4 三维度合并成完整�?agent 工作流框�?(生产可用 / UI 可驱�?/ 检索可扩展 / 决策可监�?�?
### 1.1 本文档合并了什�?
| 来源 | 章节 |
|---|---|
| `agent-framework-comparison-2026-09-02.md` (legacy) | §3.1 基线 (pre-D2 评估) |
| `langgraph-migration-2026-09-02.md` (legacy) | §3.2 评估过的另一条路�?(Python sidecar, 未采�? |
| `capturegraph-processing-chain-2026-09-16.md` (legacy) | §4 当前架构 + §5 笔记生成 + §6 兄弟 workflow |
| `d2-capturegraph-teaching-2026-09-05.md` (agents/) | Appendix B 实施链路 (历史) |
| `capturegraph-tool-layer-and-patterns-2026-09-16.md` (legacy, 2026-09-16 当日 earlier) | §7 Tool �?+ §8 设计模式 |

### 1.2 不在本文档范�?(正交)

- **`docs/research/agent-toolkit-and-skill-dispatch-2026-09-06.md`** �?工具�?/ 小艺 skill 调度设计 (�?CaptureGraph 处理链无�? �?§7.8 引用�?统一工具�?结论)�?- **`docs/research/langgraph-mapping-verification-2026-09-06.md`** �?LangGraph 概念 �?鸿蒙 Kit API 核查 (不涉�?CaptureGraph 处理�? §10.3 引其 API 24 vs 26 边界结论)�?- **`docs/specs/011 / 014 / 015 / 018`** �?实施规范, 本文不复�?spec 内容, 引用其章节�?
### 1.3 阅读路径

接后端新�?(30 分钟): §1 �?§3 (当前取向与趋�? �?§4 (图机�? �?§5 (笔记生成) �?§7 (工具) �?§8 (模式)。�? / §9 / §10 / §11 按需。Appendix A/B 仅维�?历史查询用�?
---

## 2. 时间�?
```
2026-08           初始实现: Dispatcher (159 LOC) + TypeClassifier + KnowledgeModel (929 LOC god class) + LlmClient (3 methods)
2026-09-01        审计发现 #3/#4/#5/#7 = P0 refactor (Dispatcher 单入�?/ LlmClient 合并 / KnowledgeModel 拆分)
2026-09-02        research �? pre-D2 基线评估 (legacy) �?当时 Dispatcher + TypeClassifier + 929 LOC KnowledgeModel god class 同步�?                  research �? 评估过的另一条路�?(legacy) �?Python sidecar LangGraph 3-5 人周提案; 三条具体原因未采�?(§3.2)
2026-09-05        ADR-0008 拍板: 当前取向 = �?LangGraph 设计词汇 + ArkTS 自研 StateGraph 运行�?(§3.3); 长期目标 = 完整稳定 agent 工作流框�?(§3.4)
                  spec 011 (CaptureGraph ArkTS refactor) 起草
2026-09-05~09-08  D2 实施 (12 commit: 050349e �?8b52f9a) �?详见 Appendix B
2026-09-06        research �? LangGraph 概念 �?鸿蒙 Kit API 逐行核查 (修正 API 24 vs 26)
                  research �? 工具�?/ skill 调度调研, 复核 ADR-0008
2026-09-09        spec 014 (tool-calling-protocol) + spec 015 (KnowledgeModel 拆分) + spec 018 (4 workflow 共享 kernel)
2026-09-10        spec 018 落地验收: Hypium 3/3, ArkTS lint 83/83
2026-09-16        research �?(capturegraph-processing-chain) + research �?(tool layer + patterns)
                  本文�? 合并 5 份旧 research + teaching �?当前权威
```

---

## 3. 决策 �?当前取向与趋�? �?LangGraph 设计模式, 趋向完整稳定�?agent 工作流框�?
### 3.1 基线 (2026-09-02)

来源: research �?(legacy) �?[`docs/legacy/mindtrace/research/agent-framework-comparison-2026-09-02.md`](https://github.com/YunC-GCT/MindTrace/blob/develop/docs/legacy/mindtrace/research/agent-framework-comparison-2026-09-02.md)

| 组件 | LOC | 公共 API |
|---|---|---|
| Dispatcher (`agents/src/main/ets/core/Dispatcher.ets`) | 159 | `analyze / dispatch / routeDispatch` 3 �?|
| TypeClassifier | 363 | `classify / recognizeText` |
| KnowledgeModel | 929 (god class) | `structure` |
| LlmClient | ~500 | `call / callStream / callSseTokens` 3 �?|

数据�? `AiService.capture �?Dispatcher.dispatch �?TypeClassifier.recognizeText (�?LlmClient.callStream) �?KnowledgeModel.structure (�?LlmClient.call) �?DispatchResult`�?*同步 / 线�?/ 无状态机 / �?checkpoint / 无中�?/ 无条件路�?*。与 LangGraph 概念匹配 0/12�?
### 3.2 评估过的另一条路�?�?Python sidecar LangGraph (2026-09-02, 未采�?

来源: research �?(legacy) �?[`docs/legacy/mindtrace/research/langgraph-migration-2026-09-02.md`](https://github.com/YunC-GCT/MindTrace/blob/develop/docs/legacy/mindtrace/research/langgraph-migration-2026-09-02.md)

提案: Python HTTP 边车�?LangGraph, ArkTS 前端 `POST /dispatch` 调用。估�?**3-5 人周** (1 工程�?4-6 �?, 渐进 4 阶段�?
**未采纳的三条具体原因** (�?ADR-0008):
1. LangGraph 1.4.14 主入口强制依�?`node:async_hooks`; `/web` 入口虽避开但重度依�?`@langchain/core` + `zod` 动态类型栈, ArkTS strict (`any` �?/ 动态属性访问禁) 无法集成�?2. 全网零鸿�?/ ArkTS 运行案例 (GitHub `gh search "langgraph arkts/harmonyos"` 0 结果, 2026-09-06)�?3. LangGraph 1.x 把条件路由收敛为 `Command({goto})` + `Send` fan-out, `addConditionalEdges` 已废 �?本项�?CaptureGraph �?conditional edge 词汇与上游方向一�? **设计采纳本身已对�?*�?
**采纳的设计模�?* (零运行时依赖):
- `BaseCheckpointSaver` 5 方法接口 (`getTuple / list / put / putWrites / deleteThread`) �?未来若做"复习会话恢复 / Order 断点续跑", �?`agents/graph/` 定义 5 方法接口 + RDB 实现, 不必引框架�?- `interrupt(payload)` 异常 + 重放 �?TruthCheck 失败即短路即此模�?(本项�?ADR-0008 §Consequences)�?- `Command/goto` 条件路由 �?CaptureGraph �?`addConditionalEdge` 实现对齐此形状�?
### 3.3 当前取向 (ADR-0008 + spec 011/014/015/018)

来源: [`docs/adr/0008-capturegraph-self-built-runtime.md`](https://github.com/YunC-GCT/MindTrace/blob/develop/docs/adr/0008-capturegraph-self-built-runtime.md) · [`docs/specs/018-agent-workflow-architecture.md`](https://github.com/YunC-GCT/MindTrace/blob/develop/docs/specs/018-agent-workflow-architecture.md)

> "We **adopted LangGraph as the project's primary Agent workflow architecture design root** �?its model and vocabulary (Node, Edge, State, conditional edges, START/END, addNode / addEdge / addConditionalEdge / run) are canonical for every Agent workflow that requires orchestration."

**LangGraph = 当前借用的设计模�?*, Runtime = `common/src/main/ets/workflow/StateGraph.ets` (88 LOC, §4.1)�?
> **当前定位**: MindTrace �?agent workflow 框架**正在持续完善**中。LangGraph 是当前所借用的设计参�?(Node / Edge / State / conditional edge / START/END 等词�?, 但框�?*不止�?LangGraph 词汇** �?实际承载 4 个生�?workflow + 工具�?+ 笔记生成 + 真值检�?+ 持久化缝 + 6 项决策一致�?+ �?agent 设计模式判定。这是一�?*自研的完�?agent 工作流框�?*, LangGraph 只是当前阶段的词汇参考�?
### 3.4 趋向 / 未来路径 �?完整稳定�?agent 工作流框�?
当前框架**骨架稳定**, �?*血肉仍在补** (§10 drift 是当前与"完整稳定"目标的差距清�?。按本节 §3 现状 + §10 drift + §5.6 RAG 路径, 趋向目标拆为 3 个维�?

**A. 词汇�?�?扩展设计模式覆盖** (短期):
- 当前已识�?8 种模�?(ReAct / Reflexion / Plan-and-Execute / Router / Single-shot / Multi-turn / Pure function / Pipeline) (§8.1)
- 趋向: �?Multi-agent 协作 / Hierarchical Agent (Supervisor) / Human-in-the-Loop (per ADR-0008 §Consequences) / Streaming Agent �?- 参�? LangGraph 1.x 演进�?`Command` / `Send` fan-out / interrupt 重放 (research �?§3 采纳的设计模�? §10.1 已部分实�?

**B. 工具�?�?工具循环落地 + 事件�?* (复赛后第一优先):
- ToolLoop �?ConversationWorkflow (�?§10.2 H1/H2) �?当前 spec 018 §1.44 / §1.74 �?ToolLoop 定为稳定入口, 但生产零消费
- SSE tool_call/tool_result emit (�?§10.2 S3) �?UI 过程展示拿不到工具调用中间状�?- ToolLoop 事件出口 (�?§10.2 S4)
- 工具层事件化 = 框架�?UI �?完整契约"

**C. 接入�?�?检�?+ 决策辅助** (中长�?:
- RAG 引入 (智慧化数据检�?API 20+ / vectorStore API 18+, research �?§1) 作为工具层扩�?(§5.6)
- 写类工具开�?(P2, ToolRegistry 写工�? �?当前 P1 只读
- �?LLM provider 路由 (qwen / deepseek / 自建 / 兜底) �?当前 spec 020 reply contract by transport 是开�?
**趋同目标**: �?§10 drift 14 �?+ §5.6 RAG 4 模式 + §3.4 三维�?= **完整�?agent 工作流框�?* (生产可用、UI 可驱动、检索可扩展、决策可监督)。这是项目的中长期愿�? **不是某次复赛或决赛的终点**�?
---



---

## 4. 当前架构 �?CaptureGraph 处理�?
### 4.1 共享内核: `StateGraph<State, Step>` (88 LOC)

文件: [`common/src/main/ets/workflow/StateGraph.ets:1-88`](../../common/src/main/ets/workflow/StateGraph.ets)

公共表面:
- `StateGraphNode<State> = (state: State) => Promise<State>` (`:1`)
- `StateGraphRoute<State, Step> = (state: State) => Step` (`:2`)
- `StateGraphHalt<State> = (state: State) => boolean` (`:3`)
- `StateGraphErrorKind = 'INVALID_GRAPH' | 'MAX_NODE_RUNS'` (`:5`)
- `StateGraphError` extends Error (`:7-17`)

`StateGraph<State, Step extends string>` (`:19`):
- 构�?(`:28-32`): `(startStep: Step, endStep: Step, haltWhen?: StateGraphHalt<State>)`
- `addNode(step, node)` (`:34-39`) �?�?START/END/重名; �?`INVALID_GRAPH`
- `addEdge(from, to)` (`:41-46`) �?�?from=END/已有�?- `addConditionalEdge(from, route)` (`:48-53`) �?�?addEdge 限制
- `run(initialState, maxNodeRuns = 128)` (`:55-75`):
  1. �?`nodeRuns`, �?`maxNodeRuns` �?`MAX_NODE_RUNS` (`:60-62`)
  2. �?node; 缺抛 `INVALID_GRAPH` (`:63-66`)
  3. `state = await node(state)` (`:67`)
  4. `haltWhen(state)` �?�?立即返回 (`:69-71`)
  5. `next(from, state)` 优先 conditional edge, 回退 plain edge; 都没 �?`INVALID_GRAPH` (`:77-87`)

**重要性质**:
- **State 对内核不透明** �?内核不复制字�? 每个节点自己 forward (`copyAgentState` �?§4.3)
- **`haltWhen` �?early-exit 谓词** �?�?CaptureGraph 使用 (`CaptureGraph.ets:23` 谓词 `state.error !== undefined`), 其他 workflow �?plain edge �?END

### 4.2 CaptureGraph 节点�?
文件: [`agents/src/main/ets/graph/CaptureGraph.ets:1-99`](../../agents/src/main/ets/graph/CaptureGraph.ets) · 拓扑�?[`Dispatcher.ets:1497-1531`](../../agents/src/main/ets/core/Dispatcher.ets) `buildGraph` 装配

| 节点 | file:line | 输入 | 输出 | 出边 | 条件谓词 | LLM 调用 |
|---|---|---|---|---|---|---|
| `capture` (OcrNode) | [`OcrNode.ets:8-27`](../../agents/src/main/ets/graph/nodes/OcrNode.ets) | `payload` | `captureText` | plain �?`classify` | �?| 不直�? �?`TypeClassifier.recognizeText` �?`OcrTool.recognize` (`TypeClassifier.ets:140-148`) |
| `classify` (ClassifyNode) | [`ClassifyNode.ets:8-15`](../../agents/src/main/ets/graph/nodes/ClassifyNode.ets) | `captureText` | `classification` | conditional �?`structure` / `END` | `input.analysisOnly ? 'END' : 'structure'` (`Dispatcher.ets:1525`) | `TypeClassifier.classifyText` �?`LlmGuard.callJsonWithRetry` (`:224-229`); LLM 失败 �?rule fallback (`:123-133`) |
| `structure` (StructureNode) | [`StructureNode.ets:7-65`](../../agents/src/main/ets/graph/nodes/StructureNode.ets) | `captureText`, `classification?`, `generationRequest?` | `knowledgeUnit`, `draft?`, `standardResult?` | plain �?`truth_check` | �?; `STANDARD_GATE_FAILED` 短路 (`:17-31`) for `route==='standard'` | `KnowledgeModel.structure*` 多种形�?�?`LlmClient.call({responseFormat})` 间接 |
| `truth_check` (TruthCheckNode) | [`TruthCheckNode.ets:7-38`](../../agents/src/main/ets/graph/nodes/TruthCheckNode.ets) | `captureText`, `knowledgeUnit?`, `generationRequest?`, `preparedCandidate?` | `truthCheck`, `error?` | conditional �?`persist` / `END` | `input.persist ? 'persist' : 'END'` (`Dispatcher.ets:1528`) | 不调; �?`TruthCheckService.check(truthInput)` |
| `persist` (PersistNode) | [`PersistNode.ets:7-84`](../../agents/src/main/ets/graph/nodes/PersistNode.ets) | `knowledgeUnit`, `persist`, `preparedCandidate?` | `commitResult?`, `error?` | plain �?`END` | �?; `!input.persist` �?no-op return (`:10-12`) | 不调; `dao.insert` (`:80`) / `dao.insertWithCommitKey` (`:75`) / `dao.updateWithCommitKey` (`:38`) |

**�?/ 错误语义**:
- **`haltWhen`** (`CaptureGraph.ets:23`) �?任一节点�?`state.error` 即停, `run()` 重写 `currentStep='END'` (`:58-59`)。ADR-0008 "AI 失败�?CaptureGraphError 短路, �?fallback KU" 的实现�?- **Per-node try/catch** (`CaptureGraph.ets:30-36`) �?节点内异常转 `CaptureGraphError{kind:'NODE_ERROR', retriable:false}`, �?inner per-node 错误共用同一 `haltWhen` 门�?- **TruthCheck 短路**: 失败�?`TruthCheckNode` 双写 `state.truthCheck={passed:false,...}` + `state.error={kind:'TRUTH_CHECK_ERROR', step:'truth_check', retriable:false}` (`:27-34`)�?- **未注�?DAO**: �?stub `persist` 返回 `PERSIST_DAO_REQUIRED` (`:1508-1521`)。`buildPreparedGraph` 同样 (`:1413-1425`)�?
### 4.3 AgentState / CaptureStep / CaptureNode 契约

文件: [`agents/src/main/ets/graph/AgentState.ets:1-98`](../../agents/src/main/ets/graph/AgentState.ets)

```ts
type CaptureStep = 'START' | 'capture' | 'classify' | 'structure' | 'truth_check' | 'persist' | 'END';  // :16-23

interface CaptureGraphError {                                                  // :25-31
  kind: string; message: string; step: CaptureStep; retriable: boolean; cause?: Object;
  // �? cause �?Object 而非 unknown �?�?§10.1 drift #4
}

interface AgentState {                                                         // :33-51
  captureText: string;
  source: string;
  payload?: DispatchPayload;                                                   // 原始入参, capture 后保�?  classification?: ClassificationResult;
  knowledgeUnit?: KnowledgeUnit;
  truthCheck?: TruthCheckResult;
  error?: CaptureGraphError;
  currentStep: CaptureStep;
  persist: boolean; analysisOnly: boolean;
  generationRequest?: NoteGenerationRequest;
  draft?: NoteDraftDocument;
  standardResult?: NoteGenerationStandardResult;
  preparedCandidate?: PreparedCandidate;
  commitResult?: NoteCommitResult;
}

type CaptureNode = (state: AgentState) => Promise<{ state: AgentState }>;      // :57

// copyAgentState (:59-98): 逐字�?if-defined 复制, 保证 channel 不丢
```

### 4.4 Dispatcher 契约 �?`dispatch(req, options)`

文件: [`agents/src/main/ets/core/Dispatcher.ets:68-188`](../../agents/src/main/ets/core/Dispatcher.ets)

**唯一公共方法**: `async dispatch(req: DispatchRequest, options: DispatchOptions = {}): Promise<DispatchResult>` (`:98-100`)�?
| `req.*` 字段 | 分支 | file:line | 持久化行�?|
|---|---|---|---|
| `req.preparedCandidate !== undefined` | `dispatchPreparedCandidate` | `:1316-1406` | `updateExisting===true` �?`updateWithCommitKey`; �?`commitKey` �?`insertWithCommitKey`; �?commit �?`dao.insert` |
| `req.generation` + `mode === 'regenerate'` | `dispatchIncrementalGeneration` | `:190-304` | 不调 persist |
| `req.generation` + `mode !== 'regenerate'` | `dispatchGeneration` | `:332-573` | `route==='standard'` �?`KnowledgeModel.structureStandardDraft` + repair; `route==='deep'` �?`structureDeepDraft` + repair; `route==='light'` �?`buildGenerationGraph` |
| (以上皆无) | 默认 Capture pipeline | `:114-187` | `buildGraph`, `options.persist` 默认 true |

`DispatchOptions` (`:68-75`): `{ persist?, includeRawText?, analysisOnly?, dao?, generationRepository?, knowledgeModel? }`

### 4.5 KnowledgeModel (spec 015 拆分�?

文件: [`agents/src/main/ets/agents/KnowledgeModel.ets`](../../agents/src/main/ets/agents/KnowledgeModel.ets) (�?54 LOC, 拆分�?878)

| 关注�?(拆分�? | 新归�?| file:line |
|---|---|---|
| prompt 构�?+ `KNOWLEDGE_*` 常量 | `PromptBuilder` | [`PromptBuilder.ets:9-58`](../../agents/src/main/ets/agents/PromptBuilder.ets) |
| 4 项校�?+ `patchIntegralDx` | `TruthCheckService` | [`TruthCheckService.ets:30-283`](../../agents/src/main/ets/agents/TruthCheckService.ets) |
| 编排 (`structure*` / `repair*` / `draftToKnowledgeUnit`) | **`KnowledgeModel`** (保留�? | `:114-511, 1100-1117` |

**spec 018 ownership 更新**: `TruthCheckService` 生产调用权收敛到 TruthCheckNode; `KnowledgeModel` 不再�?TruthCheck。验�? `TruthCheckService` �?`TruthCheckNode.ets:5,13` import�?
`KnowledgeModel` 拥有: `callAi` (`:122-155`) · `structureLightDraft` (`:186-233`) · `structureStandardDraft` / `repairStandardDraft` (`:235-287`) · `structureDeepDraft` / `repairDeepDraft` (`:289-451`) · `repairIncrementalSections` (`:453-511`) · `draftToKnowledgeUnit` (`:1100-1117`)�?
LLM �? `this.llm` (`:102-106`), 类型 `LlmCaller` (re-export of `LlmClient.call` from [`LlmGuard.ets:5-7`](../../common/src/main/ets/llm/LlmGuard.ets))。默�?`new LlmClient()`�?
### 4.6 TruthCheck 节点短路力学

文件: [`agents/src/main/ets/graph/nodes/TruthCheckNode.ets:7-38`](../../agents/src/main/ets/graph/nodes/TruthCheckNode.ets) · 4 项校�?([`TruthCheckService.ets:42-113`](../../agents/src/main/ets/agents/TruthCheckService.ets)):
1. **bracePair** (`:115-154`) �?`{`/`}` 深度, 自动闭合
2. **divisionByZero** (`:156-165`) �?子串 `/0`
3. **equationCheck** (`:166-188`) �?矛盾恒等�?+ `≠` + 平凡等式
4. **latexSyntax** (`:189-282`) �?brace + `\left/\right` parity + typo fix + `patchIntegralDx`

**短路力学**:
1. `truthFlag === false` �?`state.error = { kind:'TRUTH_CHECK_ERROR', step:'truth_check', retriable:false }` (`:27-34`)
2. CaptureGraph `haltWhen` 即停 (`StateGraph.ets:69-71`)
3. `CaptureGraph.run` 终态化 `currentStep='END'` �?返回错误 state
4. `dispatchRequest` 构�?`DispatchResult { success:false, errorMessage, ... }` (`Dispatcher.ets:124-140`)
5. **Capture pipeline**: �?`'处理失败: ' + errorMessage` (`AiService.ets:455-458`)
6. **Generation evaluation 循环** (`Dispatcher.evaluateStandardCandidate`, `:937-960`): truth-check 错误**非致�?* �?�?`TRUTH_CHECK_ERROR` issue (severity `hard`), repair 继续�?`best.hardIssueCount === 0` (`:666-669`)

**�?fallback KU**: ADR-0008 §Consequences + spec 011 §9 双锁定。`KnowledgeModel.ets:142-155` 显式 throw, `StructureNode` (`:54-62`) 映射 `CaptureGraphError{kind:'STRUCTURE_ERROR'}`, 不构�?fallback 对象�?
### 4.7 LlmClient 调用�?(JSON vs SSE)

文件: [`common/src/main/ets/llm/LlmClient.ets`](../../common/src/main/ets/llm/LlmClient.ets) + [`LlmGuard.ets`](../../common/src/main/ets/llm/LlmGuard.ets)

两路�?
- **JSON**: `callJsonInternal` (`LlmClient.ets:74-167`) �?返回 `LlmCallResult { text, toolCalls?, usage? }`
- **SSE**: `callStreamInternal` (`:216-402`) �?emit `StreamEvent[]`

路由在公�?`call()` (`:60-70`): `request.stream===true` �?SSE (要求 `onDelta`); 否则 JSON�?
调用方矩�?

| 调用�?| 路径 | 预算 / 温度 |
|---|---|---|
| `TypeClassifier.callClassifier` | JSON via `LlmGuard.callJsonWithRetry` | `maxTokens=800, timeoutMs=120000, temp=0.1` |
| `KnowledgeModel.callAi` | JSON via `LlmGuard.callJsonWithRetry` | `maxTokens=KNOWLEDGE_MAX_TOKENS=12000` |
| `KnowledgeModel.structureLightDraft` | JSON via `this.llm.call({responseFormat})` | `maxTokens = budgetedRequestTokens(request, 1200)` |
| `KnowledgeModel.callStandardArtifacts` | JSON via `this.llm.call({responseFormat:json_schema})` | `maxTokens = budgetedRequestTokens(request, 12000)` |
| `KnowledgeModel.callIndependentVerifier` | JSON | `maxTokens = budgetedTokens(tokenBudget, 1600)` |
| `KnowledgeModel.callDeepSectionDraft` / `repairIncrementalSections` / `callEvidenceRepair` | JSON | `maxTokens = budgetedRequestTokens(request, 2400)` |
| `ReplyService.complete` | JSON (SSE 失败 fallback) | `CHAT_REPLY_MAX_TOKENS=12000` |
| `ReplyService.stream` | SSE via `client.call({stream:true, onDelta})` | `CHAT_REPLY_MAX_TOKENS=12000` |
| `ToolCallingWorkflow.CallModelNode` | JSON with `tools=[...]`, `tool_choice='auto'` | `maxSteps=DEFAULT_MAX_STEPS=4` (�?§6.4) |

`max_tokens` 默认: `LlmConfig.DEFAULT_MAX_TOKENS` (`LlmClient.ets:84-85`)。DeepSeek `enableThinking=true`: body 抑制 `temperature`, �?`reasoning_effort='high'` (`:97-118`)�?
**30s 首字�?SSE fallback** (`LlmClient.ets:310-318`): 传输层恢�? 不是第二后端; reject `LlmError('LLM stream no data', 'STREAM_FAILED')`, `ReplyService.stream` catch �?`complete()` (spec 018 §7 允许)�?
### 4.8 持久化缝 �?`NoteDaoAdapter`

`agents` 侧契�? [`agents/src/main/ets/models/NoteDaoInterface.ets`](../../agents/src/main/ets/models/NoteDaoInterface.ets) (`insert / insertWithCommitKey? / update? / updateWithCommitKey?`).
`entry` 侧适配: [`entry/src/main/ets/adapters/NoteDaoAdapter.ets`](../../entry/src/main/ets/adapters/NoteDaoAdapter.ets) (�?4 个方�?�?
调用矩阵:

| 路径 | DAO 方法 | 写入 |
|---|---|---|
| CaptureGraph `persist` 节点 (�?preparedCandidate) | `dao.insert(unit)` (`PersistNode.ets:80`) | �?KU (source='capture_graph') |
| CaptureGraph `persist` 节点 (preparedCandidate, �?`commitKey`) | `dao.insertWithCommitKey(unit, commit)` (`:62-78`) | �?unit �?`commitKey`; �?`commitKey` 幂等 |
| CaptureGraph `persist` 节点 (`updateExisting===true`, `commitKey`, `expectedVersion`) | `dao.updateWithCommitKey(unit, expectedVersion, commit)` (`:24-51`) | 乐观�? 否则 `VERSION_CONFLICT` |
| Dispatcher `dispatchPreparedCandidate` (persist �? | `repository.saveCommitResult(commit)` (`Dispatcher.ets:1397`) | generation RDB commit-result |
| Dispatcher `dispatchGeneration` (preflight) | `repository.saveRun / saveCheckpoint / appendLifecycleLog` | generation 元数�?|

**幂等�?*:
- `preparedCandidate` �? `dispatchPreparedCandidate` invoke graph **�?*�?`existingCommit` by `commitKey` (`Dispatcher.ets:1329-1340`)。命中即�? 重复 `confirmDraft` 安全�?- `NoteDaoAdapter.insert` 自身**�?*�?`(noteId)` 幂等 �?幂等保证�?**checkpoint �?* (`commitKey`) + **order �?* (`preparedCandidate.candidateHash`)�?- `updateWithCommitKey` �?`expectedVersion` �? `AiService.ets:374-376` �?`VERSION_CONFLICT` 转为 re-plan 路径�?
---

## 5. 笔记生成完整调度�?
> **本节�?§4 关系**: §4 = Capture pipeline (image/file �?KU); **§5 = 生成 pipeline** (text instruction + sources �?draft �?confirm �?KU 入库)。两者都�?`Dispatcher.dispatch` 单入�? 但图形态不�?(§4.2 CaptureGraph vs §5.2 三种生成路由)�?*入库路径** �?§4 �?`PersistNode` 直写, �?§5 �?`PreparedCandidate` + commit key + version conflict 乐观锁�?
### 5.1 入口与三模式

笔记生成�?`ConversationWorkflow` 主导, 通过 `IntentClassifier` ([`entry/src/main/ets/services/IntentClassifier.ets:14`](../../entry/src/main/ets/services/IntentClassifier.ets) 类型 `'note_generation' | 'chat'`) 分流�?AiService:

| 入口 | IntentClassifier 决策 | AiService 方法 | Dispatcher 分支 | 用�?|
|---|---|---|---|---|
| 用户文字消息 | `note_generation` | `generateNoteDraftWithSources` (`:124-198`) | `dispatchGeneration` (create) | 从对�?OCR 材料生成新笔�?|
| 用户在草稿页�?重新生成" | (UI 触发) | `regenerateNoteDraft` (`:200-256`) | `dispatchIncrementalGeneration` | 增量更新已有笔记 |
| 用户在草稿页�?确认入库" | (UI 触发) | `confirmDraft` (`:352-386`) | `dispatchPreparedCandidate` | 草稿 �?KU 持久�?|

`IntentClassifier` 关键词前�?(`hasExplicitRegenerationIntent / hasExplicitNoteGenerationIntent`, `:34-35`) + 远程 LLM 兜底 + LlmGuard 校验重试 (`:59, 75-76`)�?
### 5.2 模式 1: create �?草稿生成 (Plan-and-Execute + Reflexion)

**入口**: `AiService.generateNoteDraftWithSources` (`AiService.ets:124-198`)

```
AiService.generateNoteDraftWithSources
  �?构�?NoteGenerationRequest { mode: 'create', runId, instruction, sources }
  �?Dispatcher.dispatch ({ generation: request }, { persist: false, generationRepository })
  �?  �?dispatchRequest 路由 �?dispatchGeneration (Dispatcher.ets:332)
  �?  ├─ normalizeBundle + selectGenerationRoute (light / standard / deep)
  ├─ �?budget: standardBudget / deepBudget / lightBudget (Dispatcher.ets:340)
  ├─ saveRun (NoteGenerationRun) �?generationRepository (:356)
  ├─ Pre-flight validation (:360-397):
  �?    - validateSourceBundle (源缺�?�?
  �?    - MISSING_SOURCE (无源片段) (:366)
  �?    - MISSING_INSTRUCTION (instruction �? (:369)
  �?    - MISSING_USER_FACT (instruction �?缺少"/"未知") (:372)
  �?    - SOURCE_BUDGET_EXCEEDED (deep route �?maxSourceChars) (:380-387)
  �?    - validateDeepOutline (deep route 计划 outline 完整�? (:392)
  �?    任何 hard issue �?preflight 失败, saveRun(status='failed'), �?{success:false, questions, stopReason}
  �?  ├─ 路由分发 (:444-466):
  �?    route=='light'    �?buildGenerationGraph (CaptureGraph: structure �?truth_check �?END)
  �?    route=='standard' �?dispatchStandardGeneration (:575-751)
  �?    route=='deep'     �?dispatchDeepGeneration (:753-923)
  �?  �?DispatchResult { success, data: KnowledgeUnit, generation: NoteGenerationResult,
                     bestCheckpointId, issues, incrementalManifest, ... }
  �?  �?AiService 包成 NoteDraftReadyEvent (:184-197)
     (runId, checkpointId, candidateHash, candidate: KnowledgeUnit,
      result, sourceCount, softIssueCount, sourceIds, pendingSourceIds,
      incrementalManifest, expectedVersion, incrementalInstruction)
```

**route 选择** ([`Dispatcher.ets:339`](../../agents/src/main/ets/core/Dispatcher.ets)): `selectGenerationRoute(bundle, instruction)` 按源材料�?+ 指令复杂度决定�?
#### 5.2.1 standard route �?Plan-and-Execute + Reflexion

`Dispatcher.dispatchStandardGeneration` (`Dispatcher.ets:575-751`):

```
dispatchStandardGeneration
  ├─ KnowledgeModel.structureStandardDraft (:235-258)  �?三阶�?  �?    ├─ callStandardArtifacts (LLM: outline + evidence + draft) (:691-720)
  �?    ├─ normalizeStandardResult (:785-844)
  �?    ├─ callIndependentVerifier (独立 LLM 验证) (:722-783)  �?不是 self-judge
  �?    └─ applyVerification (:846-869)
  �?  ├─ Reflexion repair loop (:666-669):
  �?    while (current.hardIssueCount > 0 && iteration < maxIterations):
  �?        ├─ KnowledgeModel.repairStandardDraft (:260-287)
  �?        �?    ├─ callEvidenceRepair (LLM 修复 contradicted 证据) (:676-681)
  �?        �?    └─ mergeVerifiedEvidence (:871-941)  �?supported 冻结, 只换 contradicted
  �?        ├─ 重新 callIndependentVerifier
  �?        └─ saveCheckpoint (iteration+1) (:651)
  �?  ├─ �?best (hardIssueCount 最少的轮次)
  ├─ best.hardIssueCount > 0 ? 失败 �?�?{success:false, errorMessage}
  └─ saveRun(status='completed') (:433) + �?{success:true, data, generation}
```

**Plan-and-Execute 核心**: outline + evidence + draft 三产�?*独立** LLM 生成 + **独立 verifier** (�?self-judge), 这是"标准�?的关键设计之一 (§5.5)�?
**Reflexion 核心**: 失败 �?修复 �?验证 �?直至 `hardIssueCount === 0`; **supported 证据冻结**, 只替�?contradicted �?避免无限修复循环�?
#### 5.2.2 deep route �?顺序深生�?+ ledger

`Dispatcher.dispatchDeepGeneration` (`Dispatcher.ets:753-923`):

```
dispatchDeepGeneration
  ├─ segmentSourceBundle (源切�?
  ├─ buildDeepOutline (LLM 生成 outline, pre-flight 已验�?:391)
  ├─ KnowledgeModel.structureDeepDraft (:289-373):
  �?    for each outlineSection:
  �?        KnowledgeModel.callDeepSectionDraft (LLM)
  �?        更新共享 ledger: formulas / terminology / conclusions (:306, 559-581)
  �?  ├─ Reflexion repair (per-section):
  �?    KnowledgeModel.repairDeepDraft (:375-451)
  �?    targets = issue.sectionId  (不重做整�?draft)
  �?  ├─ saveCheckpoint (:825)
  └─ saveRun(completed) + �?success
```

**ledger** = �?section 共享的事�?公式/术语�? 保证深生成时�?section 一致�?(e.g. 同名公式在多�?section 不被重定�?�?
### 5.3 模式 2: regenerate �?增量重生�?
**入口**: `AiService.regenerateNoteDraft` (`AiService.ets:200-256`)

```
AiService.regenerateNoteDraft
  �?需�?noteId (throws if empty :206-208)
  ├─ repository.getRegenerationBase(noteId) (:213)  �?取已�?KU �?baseVersion
  ├─ 构�?NoteGenerationRequest { mode: 'regenerate', targetNoteId, baseVersion, sources }
  �?Dispatcher.dispatch ({ generation: request }, { persist: false, generationRepository })
  �?  �?dispatchRequest �?dispatchIncrementalGeneration (Dispatcher.ets:190-304)
  �?  ├─ saveRun (:248)
  ├─ KnowledgeModel.repairIncrementalSections (:453-511)
  �?    �?只改 incrementalManifest 标出�?section, 不动其它
  ├─ saveCheckpoint (:283)
  └─ �?{ success, data, generation: { incrementalManifest, incrementalDiff, ... } }
```

**关键设计**: `incrementalManifest` (�?create 阶段就生�? 标出"哪些 section 用到新源", regenerate 只对这些 section 做局部修�? 其它 section 完全不动 �?避免"用户改了一句话, LLM 重写整篇"�?
### 5.4 模式 3: confirm �?草稿确认 �?入库

**入口**: `AiService.confirmDraft` (`AiService.ets:352-386`)

```
AiService.confirmDraft
  ├─ updateDraftCheckpoint (event, candidate) (:320-350)
  �?    ├─ repository.restore(runId) �?recovery
  �?    ├─ 找匹配的 previousCheckpoint (id + candidateHash 校验)
  �?    ├─ 构造新 checkpoint { id: runId:':user-edit', iteration+1, parentId }
  �?    └─ saveCheckpoint (含用户编�?
  �?  ├─ buildNoteDao (KnowledgeUnitWriteService + NoteDaoAdapter)
  �?  ├─ 构�?PreparedCandidate:
  �?    { runId, checkpointId, candidateHash, candidate,
  �?      commitKey = runId + ':' + checkpointId + ':' + candidateHash,
  �?      sourceIds, pendingSourceIds, expectedVersion,
  �?      updateExisting = incrementalPlan !== undefined && expectedVersion !== undefined,
  �?      incrementalManifest, incrementalDiff }
  �?  �?Dispatcher.dispatch ({ preparedCandidate }, { persist: true, dao, generationRepository })
  �?  �?dispatchRequest �?dispatchPreparedCandidate (Dispatcher.ets:1316-1406)
  �?  ├─ existingCommit = repository.getCommitResult(commitKey)  �?幂等检�?  ├─ �?existingCommit !== undefined:
  �?    立即�?{ success: true, data: committedCandidate, commitResult }
  �?  ├─ buildPreparedGraph (START �?truth_check �?(persist?persist:END) �?END)
  �?    �?跳过 capture/classify/structure 节点 (preparedCandidate.knowledgeUnit 已预�?
  �?  ├─ TruthCheckNode �?检�?user-edited candidate (§4.6 短路逻辑仍生�?
  �?  ├─ PersistNode (�?preparedCandidate 路由):
  �?    updateExisting===true + commitKey + expectedVersion
  �?      �?dao.updateWithCommitKey(unit, expectedVersion, commit)
  �?        (NoteDaoAdapter.ets:53-74; PersistNode.ets:24-51)
  �?    �?commitKey + �?updateExisting
  �?      �?dao.insertWithCommitKey(unit, commit)
  �?        (NoteDaoAdapter.ets:24-52; PersistNode.ets:62-78)
  �?  ├─ 乐观�? expectedVersion 不匹�?�?KnowledgeUnitWriteError.VERSION_CONFLICT
  �?    (KnowledgeUnitWriteService.ets:63, 131) �?�?�?  �?    翻译�?DispatchResult.errorCode='VERSION_CONFLICT'
  �?  └─ saveCommitResult(commit) �?generationRepository (:1397)
       �?NoteGenerationCommitResult �?generation RDB; �?commitKey 幂等
```

**AiService 错误处理** (`AiService.ets:374-376`):
```ts
if (!result.success || result.data === undefined) {
  const prefix = result.errorCode === 'VERSION_CONFLICT' ? 'VERSION_CONFLICT: ' : '';
  throw new Error(prefix + (result.errorMessage ?? '笔记确认失败'));
}
```
�?VERSION_CONFLICT 触发 UI 重规划路�?(ConversationWorkflow.replan)�?
**成功后清�?* (`AiService.ets:378-384`):
```ts
if (event.pendingSourceIds !== undefined && event.pendingSourceIds.length > 0) {
  await new AgentMemoryService(this.requireContext()).markPendingMaterialsUsed(event.pendingSourceIds);
}
```
�?标记 pending OCR 材料为已�? 避免被其�?run 重复引用�?
### 5.5 设计标准为何�?�?5 个证�?
笔记生成�?MindTrace �?*核心产品能力** (用户主要使用), 当前设计有意拔高标准, 5 个证�?

| # | 设计�?| 标准为何�?| 引用 |
|---|---|---|---|
| 1 | **Pre-flight validation** | 生成前必检 4 �?hard issue (MISSING_SOURCE / INSTRUCTION / USER_FACT / SOURCE_BUDGET_EXCEEDED + deep outline 验证), 任何一项不过直接返 failure, 不浪�?LLM 算力 | `Dispatcher.ets:360-397` |
| 2 | **Plan-and-Execute (3 产物独立生成)** | outline + evidence + draft 三份独立 LLM 调用, 而非"一�?LLM 写完整篇"�?*关键**: independent verifier **不是 self-judge**, 是独�?LLM 调用, 避免模型偏向自己的输�?| `KnowledgeModel.ets:691-720, 722-783` |
| 3 | **Reflexion repair loop, 修到 hardIssueCount=0** | 不止一次生�? 而是 verify→repair→re-verify 循环; supported 证据冻结 (`KnowledgeModel.ets:871-941`) 避免无限循环; 终止条件 = 0 hard issue | `Dispatcher.ets:666-669` |
| 4 | **Commit key + 乐观�?+ 版本冲突** | 草稿→入库用 `runId:checkpointId:candidateHash` 三元�?commitKey 幂等; `expectedVersion` 乐观锁防并发改写; VERSION_CONFLICT 不静默覆�? 显式抛错触发重规�?| `AiService.ets:361, 365` + `KnowledgeUnitWriteService.ets:63, 131` |
| 5 | **Incremental manifest 局部更�?* | regenerate 只动 incrementalManifest 标出�?section, 其它 section 完全冻结 �?避免"小改触发大改", 保护用户对未改部分的信任 | `KnowledgeModel.ets:453-511` + `AiService.ets:251` |

> **附加**: 真值检�?(`TruthCheckService`) �?confirm 阶段**仍然�?* (§5.4 �?6 �? `buildPreparedGraph` �?truth_check 节点) �?即使用户编辑�?draft, 4 项数学校验仍生效�?
### 5.6 未来 RAG 引入后的模式考虑 (brief)

当前笔记生成标准高的代价 = **算力消耗大** (standard route �?LLM 调用 + repair 循环) + **延迟�?* (深生成耗秒�?。若后续引入 RAG (e.g. **智慧化数据检�?*, API 20+, �?research �?§1 表第 3 �? 作为工具层扩�? 可考虑以下模式方向 (本文档不展开, 仅做指针):

| 候选模�?| 适用场景 | 备注 |
|---|---|---|
| **StreamingRAG** | 用户对话流中实时注入相关检索片�?| 需�?LlmClient SSE 路径�?`tool_call/tool_result` emit (§10.2 S3 drift) |
| **Multi-stepRAG** | 复杂笔记先生成查询计�?�?多轮检�?�?拼装 | �?Plan-and-Execute 兼容, 可在 outline 阶段前加 retrieval plan 节点 |
| **ToolCall-RAG** | `SearchNote` 工具正式接入笔记生成 (而非�?skill �? | 直接�?§10.2 H1/H2 (ToolLoop �?ConversationWorkflow) |
| **Verification-gated RAG** | 检索片段作�?evidence, 仍走 independent verifier + Reflexion | **保标准不�?*: RAG 只是新增 source 类型, verification gate 不变 |

> **重要约束 (未来 PR 应保�?**: RAG 引入**不得**降低 §5.5 五项标准 (pre-flight / 3-product Plan-and-Execute / Reflexion / commit key+版本 / incremental)。检索是新增 source 维度, **不是**用来取代 verification 的捷径�?
具体设计�?`docs/specs/` 出独�?ticket (建议命名 `0X-note-generation-rag-*.md`), 不在本文档展开�?
---

## 6. 兄弟 Workflow (共用 StateGraph 内核)

### 5.1 概述

| Workflow | 模块 | State / Step | 主要节点 / �?|
|---|---|---|---|
| `CaptureGraph` | `agents/graph/` | `AgentState` / `CaptureStep` (7 �? | �?§4 |
| `ToolCallingWorkflow` | `common/workflow/tool-calling/` | `ToolCallingState` / `ToolCallingStep` | `CallModelNode` + `ExecuteToolsNode` 循环, `maxSteps=4` (ReAct, §6.4) |
| `ConversationWorkflow` | `entry/workflows/conversation/` | `ConversationState` / `ConversationStep` | 9 节点 + 6 条件�? 多轮 chat + Router (§5.3) |
| `SkillIntentWorkflow` | `skill/workflows/intent/` | `SkillIntentState` / `SkillIntentStep` | route �?`execute_search` \| `unsupported` (Router) |

### 5.2 Dispatcher 装配�?3 �?graph 形�?
| Graph | 形状 | 用�?| file:line |
|---|---|---|---|
| `buildGraph` | `START �?capture �?classify �?(analysisOnly?END:structure) �?truth_check �?(persist?persist:END) �?END` | 默认 Capture pipeline | `Dispatcher.ets:1497-1531` |
| `buildPreparedGraph` | `START �?truth_check �?(persist?persist:END) �?END` | preparedCandidate 提交 | `Dispatcher.ets:1408-1430` |
| `buildGenerationGraph` | `START �?structure �?truth_check �?END` (�?persist �? | light route generation | `Dispatcher.ets:1432-1442` |

### 5.3 ConversationWorkflow state

[`ConversationState.ets:49-60`](../../entry/src/main/ets/workflows/conversation/ConversationState.ets): 字段 `request / sessionId / currentStep / intent? / memoryContext? / learnerProfileContext? / draftRunId? / draftCheckpointId? / draftCandidateHash? / draftStatus?`。无 spec 018 §4 禁项 (UIAbilityContext / ArkUI / callback / DAO / LlmClient / ToolRegistry)。`ConversationWorkflow` 类持 `ConversationWorkflowCallbacks` (构造注�? `:32`), **不在 state**�?
流式 delta: `ConversationWorkflowCallbacks` 提供 `appendAiMsg(id, event)` + `addAiMsgEmpty()`。`handleStreamReply` (`ConversationWorkflow.ets:317-371`) �?`StreamEvent` 直接调�?
### 5.4 ToolCallingWorkflow State 字段

[`ToolCallingState.ets:10-19`](../../common/src/main/ets/workflow/tool-calling/ToolCallingState.ets): `messages / definitions / maxSteps / stepCount / currentStep / lastResult? / toolCalls? / callOptions?`。全字段对齐 spec 018 §3。详�?ReAct 拓扑�?§6.4�?
### 5.5 SkillIntentWorkflow �?SearchNote 接�?
[`SkillIntentWorkflow.ets:68-70`](../../skill/src/main/ets/workflows/intent/SkillIntentWorkflow.ets): �?`target==='search_note'` �?`execute_search`; 其他�?`unsupported` 返回 `{ok:false, content:'Unsupported skill intent: '+action, errorKind:'UNSUPPORTED_INTENT'}`. 验证 spec 018 §"skill �?SearchNote 接�?�?
---

## 7. Tool 层架�?
> **本节引用路径** (top): `common/src/main/ets/tools/ToolRegistry.ets`, `common/src/main/ets/tools/ToolCatalog.ets`, `common/src/main/ets/tools/NoteQueryTools.ets`, `common/src/main/ets/tools/ToolLoop.ets`, `common/src/main/ets/workflow/tool-calling/*`, `common/src/main/ets/llm/LlmTypes.ets`, `agents/src/main/ets/mcp/tools/OcrTool.ets`, `skill/src/main/ets/skillability/SkillAbility.ets`
> **spec**: [`docs/specs/014-tool-calling-protocol.md`](https://github.com/YunC-GCT/MindTrace/blob/develop/docs/specs/014-tool-calling-protocol.md) · **ADR**: [`0010-mcp-tools-semantics.md`](https://github.com/YunC-GCT/MindTrace/blob/develop/docs/adr/0010-mcp-tools-semantics.md), [`0012-tool-calling-protocol.md`](https://github.com/YunC-GCT/MindTrace/blob/develop/docs/adr/0012-tool-calling-protocol.md)

### 6.1 全景 (一张图看完整工具面)

```
LLM provider (DeepSeek / Qwen, OpenAI 兼容)
  �?wire: tools / tool_choice / tool_calls
  �?LlmClient.call (唯一入口, LlmClient.ets:60-70)
  ├─ callJsonInternal (74-167)  �?body.tools (106-108); LlmResponseParser.extractToolCalls (46-55)
  └─ callStreamInternal (216-402) �?parseStreamEventsFromSseData (497)  ⚠️ 暂不 emit tool_call/tool_result
                                          �?Tool-calling workflow (common/workflow/tool-calling/)                �?  ToolLoop.run (ToolLoop.ets:21-24)                                  �?    └─�?ToolCallingWorkflow.run (ToolCallingWorkflow.ets:22-45)     �?          └─�?StateGraph (maxSteps*3+4)                             �?                ├─ call_model (CallModelNode.ets:12-35) tools=defs, tool_choice='auto'
                ├─ execute_tools (ExecuteToolsNode.ets:12-50) registry.execute �?ToolResult
                └─ max_steps_error �?LlmError 'TOOL_LOOP_MAX_STEPS'
                                          �?                                          �?                       common/src/main/ets/tools/
                         ToolRegistry + ToolCatalog + NoteQueryTools (P1: note_query / note_get / review_due_query)

两条工具调用通路:
  �?MCP 风格 (OcrTool): agents/src/main/ets/mcp/tools/OcrTool.ets �?不实�?AgentTool, 不进 ToolRegistry
     �?TypeClassifier.extractText (140-148) 同步�?new OcrTool().recognize(imageUri)
  �?ToolRegistry 风格: ToolCatalog.createReadOnlyRegistry() �?SkillAbility.handleWant
     �?SkillIntentWorkflow.run �?registry.execute('note_query', argsJson) (SkillIntentWorkflow.ets:38)
```

### 6.2 ToolRegistry �?注册中心 (spec 014 / ADR-0012)

文件: [`common/src/main/ets/tools/ToolRegistry.ets:1-77`](../../common/src/main/ets/tools/ToolRegistry.ets) (77 LOC)

```ts
// :11-14 �?ToolResult: 回喂 LLM 的字符串 (ReAct 惯例)
export interface ToolResult { ok: boolean; content: string; }

// :17-22 �?AgentTool 最小契�?export interface AgentTool {
  name: string;                  // 命名规则严于 OpenAI wire: ^[a-z][a-z0-9_]{0,63}$ (:25)
  description: string;
  parameters: Record<string, Object>;   // JSON Schema 对象
  execute(args: Record<string, Object>): Promise<ToolResult>;
}

// :27-76 �?4 公开方法
export class ToolRegistry {
  register(tool: AgentTool): void;                  // :31 重名/非法�?�?LlmError('TOOL_REGISTRY_ERROR')
  has(name: string): boolean;                       // :42
  listDefinitions(): LlmToolDefinition[];           // :46-54 �?{type:'function', function:{name,description,parameters}}
  execute(name: string, argsJson: string): Promise<ToolResult>;  // :57-76 容错执行
}
```

**关键设计**:
- **容错执行** (`:57-76`): 未知工具�?�?`{ok:false, content:'unknown tool: '+name}`; JSON.parse 失败 �?`{ok:false, content:'invalid tool arguments...'}`; 不抛异常 �?LLM 可能幻觉出未注册名�?- **注册时校验命�?* (`:35-37`): 不合�?`^[a-z][a-z0-9_]{0,63}$` �?`LlmError(kind='TOOL_REGISTRY_ERROR')`, 防发送后�?OpenAI 端点拒绝�?
**生产消费�?* (4 �?:

| 调用�?| file:line | 用�?|
|---|---|---|
| `ToolCallingWorkflow` | `ToolCallingWorkflow.ets:3, 12, 16-20` | 构造时注入, `buildGraph` 初始�?`definitions` (`:31`) |
| `ExecuteToolsNode` | `ExecuteToolsNode.ets:2, 6, 8, 24` | 构造时注入, `run` �?`call.function.name` 执行 |
| `SkillAbility` | `SkillAbility.ets:2, 27` | 通过 `ToolCatalog.createReadOnlyRegistry()` 取得, 转发�?SkillIntentWorkflow |
| `SkillIntentWorkflow` | `SkillIntentWorkflow.ets:1, 5, 7, 38` | 注入�?*�?*�?`'note_query'` 直接 `registry.execute` (`:38`), 不走 LLM |

> **DRIFT 提示**: spec 018 §1 (`:44`) �?Tool-calling 入口 = `ToolLoop.run`; **全仓生产代码�?ToolLoop 调用** (`grep "new ToolLoop"` 仅命中测�?`LlmToolCalling.test.ets:128,148,164,185` 与构建缓�?�?*唯一真实工具消费方是 skill/ �?SearchNote**。详�?§9.2 #1�?
### 6.3 ToolCatalog + NoteQueryTools (P1 只读工具)

**ToolCatalog** [`common/src/main/ets/tools/ToolCatalog.ets:1-27`](../../common/src/main/ets/tools/ToolCatalog.ets) (27 LOC):

```ts
// :18-26
export class ToolCatalog {
  static createReadOnlyRegistry(): ToolRegistry {    // :19
    const registry: ToolRegistry = new ToolRegistry();
    const tools: AgentTool[] = createReadOnlyNoteTools();   // 来自 NoteQueryTools.ets:250
    for (const tool of tools) { registry.register(tool); }
    return registry;
  }
}
```

- 静态工厂而非构造器 (`:19` 注释明示 "便于 ArkTS Hypium seam 测试注入", spec 014:11-13)
- 唯一调用�? `SkillAbility.ets:27` (生产)

**NoteQueryTools** [`common/src/main/ets/tools/NoteQueryTools.ets:1-253`](../../common/src/main/ets/tools/NoteQueryTools.ets) (253 LOC, 3 工具):

| 工具�?| file:line | name | 描述 | 关键 SQL/查询 |
|---|---|---|---|---|
| `NoteQueryTool` | `:50-126` | `note_query` | subject / review_status / keyword 过滤, 上限 20 �?| `contains('title', kw) or contains('content', kw)` (`:89-94`) |
| `NoteGetTool` | `:129-193` | `note_get` | �?id 取单�?+ 完整 content | `equalTo('id', id)` + 全字�?SELECT (`:157`) |
| `ReviewDueQueryTool` | `:196-247` | `review_due_query` | �?ReviewStatus 聚合计数 | `SELECT review_status, COUNT(*) GROUP BY review_status` (`:232`) |

注册工厂 `NoteQueryTools.ets:250-253`:

```ts
export function createReadOnlyNoteTools(): AgentTool[] {
  return [new NoteQueryTool(), new NoteGetTool(), new ReviewDueQueryTool()];
}
```

**Schema 归属警示** (`:5-6`): `knowledge_unit` 表结构由 `entry/src/main/ets/database/NoteDao.ets` 声明, 本文�?*只读直查**; 两端漂移时以 NoteDao 为准修这�?(ADR-0012 §Consequences)�?
**错误处理统一形状**: 所有工�?`ok:false, content:'store not ready'` �?`DatabaseHelper.getStore() === null` (`:72-76, 149-153, 218-222`); 写入�?`entry` 组合根负�?init�?
### 6.4 ToolLoop + ToolCallingWorkflow �?ReAct

**ToolLoop** [`common/src/main/ets/tools/ToolLoop.ets:1-25`](../../common/src/main/ets/tools/ToolLoop.ets) (25 LOC 薄壳): 内部完全委托�?`ToolCallingWorkflow`�?
```ts
// :14-24
export class ToolLoop {
  constructor(private llm: LlmCaller) {}
  async run(messages: ChatMessage[], registry: ToolRegistry, options?: ToolLoopOptions): Promise<LlmCallResult> {
    return await new ToolCallingWorkflow(this.llm, registry).run(messages, options);   // :22-23
  }
}
```

- **公开稳定入口** (spec 018 §3 "ToolLoop �?workflow, 不是 Tool, 也不是单�?Node") �?�?*生产消费方为�?* (�?§10.2 #1)�?- 注释 `ToolLoop.ets:6` 明说 "�?JSON 路径 (SSE 流式工具循环不在 spec 014)"�?
**ToolCallingWorkflow** [`common/src/main/ets/workflow/tool-calling/ToolCallingWorkflow.ets:1-69`](../../common/src/main/ets/workflow/tool-calling/ToolCallingWorkflow.ets):

```ts
// :9 �?默认上限
const DEFAULT_MAX_STEPS: number = 4;

// :22-45
async run(messages, options?): Promise<LlmCallResult> {
  const maxSteps = options?.maxSteps ?? DEFAULT_MAX_STEPS;
  if (maxSteps <= 0) throw new LlmError('...', 'TOOL_LOOP_MAX_STEPS');   // :27
  const initial: ToolCallingState = {
    messages: messages.slice(0),
    definitions: this.registry.listDefinitions(),                          // :31
    maxSteps, stepCount: 0, currentStep: 'START',
  };
  // graph.run 上限�?maxSteps*3+4, 给底�?StateGraph 余地
  const finalState = await this.buildGraph().run(initial, maxSteps * 3 + 4);   // :40
  if (finalState.lastResult === undefined) throw new LlmError('...', 'EMPTY_RESPONSE');   // :42
  return finalState.lastResult;                                            // :44
}
```

**State shape** [`ToolCallingState.ets:10-19`](../../common/src/main/ets/workflow/tool-calling/ToolCallingState.ets):

```ts
interface ToolCallingState {
  messages: ChatMessage[];
  definitions: LlmToolDefinition[];
  callOptions?: LlmCallOptions;
  maxSteps: number; stepCount: number;
  currentStep: ToolCallingStep;   // 'START' | 'call_model' | 'execute_tools' | 'max_steps_error' | 'END'
  lastResult?: LlmCallResult;
  toolCalls?: LlmToolCall[];
}
```

**图拓�?(3 节点 + 4 �?** `ToolCallingWorkflow.ets:47-68`:

| 节点 / �?| file:line | 行为 |
|---|---|---|
| `START �?call_model` | `:56` | 必走 |
| `call_model` | `:50` | �?LLM, �?`result.toolCalls` �?state |
| `call_model �?execute_tools` (cond) | `:57-62` | `toolCalls` 非空 �?`execute_tools`; �?�?`END` |
| `execute_tools` | `:51-52` | 追加 `assistant(tool_calls, content:'')` + �?call `registry.execute` + `tool(tool_call_id, content)` 消息 |
| `execute_tools �?call_model` �?`max_steps_error` (cond) | `:63-65` | `stepCount >= maxSteps` �?`max_steps_error`; 否则�?`call_model` |
| `max_steps_error` | `:53-55` | �?`LlmError(kind='TOOL_LOOP_MAX_STEPS')` |

**`stopWhen` 语义**: 终止由两个谓�?+ 上限组成 �?�?`toolCalls` 为空 (LLM 决策 "无需工具") �?自然 END; �?`stepCount >= maxSteps` �?抛错 (ReAct 失控防护)�?
**节点实现**:
- `CallModelNode` (`CallModelNode.ets:12-35`): `request.tools = definitions; request.tool_choice = 'auto'`; �?`LlmCaller.call`; `stepCount+1`; `toolCalls = result.toolCalls ?? []`
- `ExecuteToolsNode` (`ExecuteToolsNode.ets:12-50`): �?call `registry.execute(call.function.name, call.function.arguments)` + push `tool(tool_call_id, content)` 消息; **不增 stepCount** (CallModelNode 已增)

### 6.5 Wire 协议 (spec 014 / ADR-0012)

文件: [`common/src/main/ets/llm/LlmTypes.ets`](../../common/src/main/ets/llm/LlmTypes.ets)

**请求�?* (5 字段增量, 全可�? 向后兼容):

```ts
// :13-19 �?ChatMessage (新加 'tool' role + tool_call_id + tool_calls)
interface ChatMessage {
  role: 'system' | 'user' | 'assistant' | 'tool';
  content: string;
  reasoning_content?: string;
  tool_call_id?: string;                  // role='tool' 必填
  tool_calls?: LlmToolCall[];             // assistant 携带工具调用 (ToolLoop 回喂必需)
}

// :22-34 �?LlmRequestBody (OpenAI 兼容)
interface LlmRequestBody {
  model: string; messages: ChatMessage[];
  temperature?: number; max_tokens: number; stream: boolean;
  response_format?: LlmResponseFormat;
  enable_thinking?: boolean; thinking?: LlmThinkingConfig;
  reasoning_effort?: string;
  tools?: LlmToolDefinition[];            // :32 spec 014 可�?�?向后兼容
  tool_choice?: string;                   // :33 Phase 1 �?'auto' | 'none'
}

// :175-185 �?工具定义形状
interface LlmFunctionDefinition { name: string; description: string; parameters: Record<string, Object>; }
interface LlmToolDefinition { type: 'function'; function: LlmFunctionDefinition; }

// :200-215 �?LlmCallRequest (透传)
interface LlmCallRequest {
  messages: ChatMessage[]; stream?: boolean; onDelta?: LlmStreamCallback;
  temperature?: number; maxTokens?: number; model?: string; timeoutMs?: number;
  responseFormat?: LlmResponseFormat; enableThinking?: boolean;
  tools?: LlmToolDefinition[];            // :213
  tool_choice?: string;                   // :214
}

// :85-86 �?新增错误种类
type LlmErrorKind = ... | 'TOOL_LOOP_MAX_STEPS' | 'TOOL_REGISTRY_ERROR';
```

**响应�?�?`extractToolCalls`** [`LlmResponseParser.ets:46-55`](../../common/src/main/ets/llm/LlmResponseParser.ets):

```ts
// :46-55
private static extractToolCalls(parsed: LlmResponse): LlmToolCall[] {
  if (parsed.choices.length === 0) return [];
  const message = parsed.choices[0].message;
  if (message === undefined || message === null
      || message.tool_calls === undefined || message.tool_calls === null) return [];
  return message.tool_calls;
}
```

**关键设计**: **不依�?`finish_reason`** (spec 014 §1.51 行注�?。OpenAI 兼容端点在该字段上行为有差异 (有些�?`'tool_calls'`, 有些�?`'stop'` �?`message.tool_calls` 非空), 一律以 `message.tool_calls` 非空为准�?
### 6.6 LlmClient �?LLM provider 接线

文件: [`common/src/main/ets/llm/LlmClient.ets:60-167`](../../common/src/main/ets/llm/LlmClient.ets)

**唯一公共入口 `call`** (`:60-70`):
```ts
public async call(request: LlmCallRequest): Promise<LlmCallResult> {
  if (request.stream === true) {
    if (request.onDelta === undefined) throw new LlmError('...', 'STREAM_FAILED');
    await this.callStreamInternal(request, request.onDelta);
    return { streamed: true };
  }
  return await this.callJsonInternal(request);
}
```

**JSON 路径透传 `tools` / `tool_choice`** (`:106-111`):
```ts
if (request.tools !== undefined) body.tools = request.tools;       // :107
if (request.tool_choice !== undefined) body.tool_choice = request.tool_choice;   // :110
```

**SSE 流式路径 �?tool_call/tool_result 事件占位但未 emit**:
`parseStreamEventsFromSseData` (`LlmClient.ets:497-522`) 当前�?emit `thinking` �?`text`, tool_call / tool_result 路径未实�?

```ts
// :506-515
const reasoning: string = delta.reasoning_content ?? '';
if (reasoning.length > 0) { /* emit thinking */ }
const content: string = delta.content ?? '';
if (content.length > 0) { /* emit text */ }
// tool_calls / tool_result 不在当前 emit 范围 �?spec 014 §"Out of scope" 明确
//   "流式 (SSE) 工具循环" 不在 scope
```

�?结论: **SSE + 工具循环 = 空白**, 当前 ToolLoop 仅走 JSON 路径 (`ToolLoop.ets:6` 注释 + `CallModelNode.ets:21` �?`LlmCaller.call` 非流�?�?
### 6.7 MCP (OcrTool) vs ToolRegistry �?双工具面 (ADR-0010)

文件: [`agents/src/main/ets/mcp/tools/OcrTool.ets:1-427`](../../agents/src/main/ets/mcp/tools/OcrTool.ets)

| 维度 | ToolRegistry tools | OcrTool (MCP) |
|---|---|---|
| 实现 AgentTool | �?4 件套 (`ToolRegistry.ets:17-22`) | �?�?4 件套, 直接 `class OcrTool` (`OcrTool.ets:52`) |
| 注册�?ToolRegistry | �?via `ToolCatalog.createReadOnlyRegistry()` | �?不注�?|
| 调用�?| LLM 通过 tool_calls JSON �?ReAct 循环 | TypeClassifier 同步 `new OcrTool().recognize(imageUri)` (`TypeClassifier.ets:140, 146`) |
| 命名空间 | `common/src/main/ets/tools/` | `agents/src/main/ets/mcp/tools/` |
| ADR 依据 | ADR-0012 | ADR-0010 |

**OcrTool 接口** (`OcrTool.ets:52-109`):
- `recognizeBytes(imageBytes, fileName?)` (`:60-62`) �?识别字节
- `recognizeBytesWithEndpoint(...)` (`:64-96`) �?测试 seam
- `recognize(imageUri)` (`:98-109`) �?Capture 流水线的高层接口, 抛错而非 `ok:false`
- `recognizeImage(imageUri)` (`:111-174`) �?完整 OCR 流程 (本地 CoreVisionKit + server fallback)

**为什么单独存�?* (ADR-0010 §Consequences): ToolRegistry �?LLM 当工具调 (LLM 决策), OcrTool �?Capture 流水线当"流水线工�?�? **不是 LLM 选择的工�?*�?
### 6.8 skill 侧复�?(唯一生产消费�?

文件: [`skill/src/main/ets/skillability/SkillAbility.ets:1-48`](../../skill/src/main/ets/skillability/SkillAbility.ets)

```ts
// :20-46
private async handleWant(want: Want): Promise<void> {
  const request: SkillIntentRequest = new IntentRouter().fromWant(want);   // :21
  if (request.target === 'search_note') {
    await DatabaseHelper.init(this.context);                               // :25 �?skill 必须�?init
  }
  const registry: ToolRegistry = ToolCatalog.createReadOnlyRegistry();     // :27
  result = await new SkillIntentWorkflow(registry).run(request);            // :28
  // 包成 Want + abilityResult �?platform (小艺): :36-46
}
```

**Tool �?LLM 路径**: `SkillAbility.handleWant �?IntentRouter.fromWant (Want �?typed request) �?ToolCatalog.createReadOnlyRegistry �?SkillIntentWorkflow.run �?execute_search 节点直接 registry.execute('note_query', argsJson) �?terminateSelfWithResult`

**注意**: skill 路径**不走 LLM** (�?tool_call 决策), 是平�?Want 直连单工具执�?(复用 research �?§2.3 结论)。这�?ToolCallingWorkflow �?ReAct 循环是两�?*完全独立**的通路�?
### 6.9 工具面拓扑总结�?
| �?| 模块 | file:line | 公开方法 | 谁调�?|
|---|---|---|---|---|
| `ToolRegistry` | common | `tools/ToolRegistry.ets:27-76` | `register / has / listDefinitions / execute` | ToolCallingWorkflow, ExecuteToolsNode, SkillAbility |
| `ToolCatalog` | common | `tools/ToolCatalog.ets:18-26` | `static createReadOnlyRegistry()` | SkillAbility.handleWant (`:27`) |
| `ToolLoop` | common | `tools/ToolLoop.ets:14-24` | `run(messages, registry, options?)` | **零生产调�?* (仅测�? |
| `NoteQueryTool` / `NoteGetTool` / `ReviewDueQueryTool` | common | `tools/NoteQueryTools.ets:50-247` | `execute(args)` | ToolCatalog.createReadOnlyRegistry (`:21`) |
| `OcrTool` (MCP) | agents | `mcp/tools/OcrTool.ets:52-426` | `recognize / recognizeBytes / recognizeImage` | TypeClassifier.extractText (`:140-148`) |
| `CallModelNode` | common | `workflow/tool-calling/nodes/CallModelNode.ets:5-44` | `run(state)` | ToolCallingWorkflow.buildGraph (`:50`) |
| `ExecuteToolsNode` | common | `workflow/tool-calling/nodes/ExecuteToolsNode.ets:5-50` | `run(state)` | ToolCallingWorkflow.buildGraph (`:51`) |
| `ToolCallingWorkflow` | common | `workflow/tool-calling/ToolCallingWorkflow.ets:11-68` | `run(messages, options?)` | ToolLoop.run (`:22`), **零生�?* |
| `SkillIntentWorkflow` | skill | `workflows/intent/SkillIntentWorkflow.ets:4-85` | `run(request)` | SkillAbility.handleWant (`:28`) |

---

## 8. Per-agent 设计模式

### 7.1 模式标签词典 (8 �?

| 标签 | 核心特征 | MindTrace 中典型代�?|
|---|---|---|
| **ReAct** | 思考↔工具交错循环, 终止�?LLM 决策 + 上限 | ToolCallingWorkflow (§8.8) |
| **Reflexion** | 校验失败→修复→重试, 自我批评驱动 | KnowledgeModel.repair* (§8.3) |
| **Plan-and-Execute** | 计划→子任务→执�?| KnowledgeModel.structureStandardDraft |
| **Router / Classifier** | 输入路由到固定分�?| SkillIntentWorkflow (§8.10); ConversationWorkflow (kind/intent 分流) |
| **Single-shot LLM call** | 一�?LLM 调用, 无循�? 无记�?| TypeClassifier.classifyText (§8.2) |
| **Multi-turn chat with state** | 记忆 + 流式 + 意图切换 | ConversationWorkflow (§8.9) |
| **Pure function** | �?LLM, 无状态机 | TruthCheckService (§8.4); PromptBuilder (§8.5); OcrTool (§8.6) |
| **Pipeline / DAG orchestration** | 静态节�?+ 条件�?+ haltWhen | CaptureGraph (§8.7) |

### 7.2 TypeClassifier �?Single-shot LLM + Pure function fallback

**Pattern**: Single-shot LLM call (主路�? + Pure function fallback (rule-based)
**位置**: [`TypeClassifier.ets:1-363`](../../agents/src/main/ets/agents/TypeClassifier.ets)

- 公开 3 入口 (`classify / recognizeText / classifyText`), 内部统一�?`callClassifier` (`:212-231`) 单次 LLM 调用
- LLM 失败显式 catch (`:123-133`) 落到 `ruleFallback` (`:292-299`) �?5 类题 + 6 学科的关键词匹配 (`CATEGORY_RULES / SUBJECT_RULES :41-56`), 不调 LLM
- `recognizeText` �?*同步工具调用**而非 LLM tool_call: image/file payload �?`OcrTool.recognize` (`TypeClassifier.ets:140, 146`)

**Loop**: 无内循环 (LlmGuard `callJsonWithRetry` 最�?`DEFAULT_MAX_RETRIES=2` �? �?JSON 校验重试)
**Tool**: 同步�?`OcrTool.recognize`; LLM �?`LlmGuard.callJsonWithRetry` (`:224-229`), 预算 `maxTokens=800, timeoutMs=120000, temp=0.1` (`:18-20`)

### 7.3 KnowledgeModel �?Plan-and-Execute + Reflexion

**Pattern**: Plan-and-Execute (`structureStandardDraft` outline→evidence→draft) + Reflexion (外层 Dispatcher �?`repairStandardDraft` / `repairDeepDraft` / `repairIncrementalSections`)
**位置**: [`KnowledgeModel.ets:1-1252`](../../agents/src/main/ets/agents/KnowledgeModel.ets) (split �?~554 LOC)

- `structureStandardDraft` (`:235-258`) 三阶�? �?`callStandardArtifacts` outline+evidence+draft (`:691-720`); �?`normalizeStandardResult` 归一�?(`:785-844`); �?`callIndependentVerifier` 独立验证 (`:722-783`) �?�?`applyVerification` (`:846-869`) �?典型 **Plan-and-Execute** (Planner 生成 3 份产�?+ Executor 验证)
- `repairStandardDraft` (`:260-287`) **Reflexion**: verification 失败 �?`callEvidenceRepair` 修复 �?�?verify �?`mergeVerifiedEvidence` (`:871-941`) 保留 `supported` 证据冻结, 只替�?contradicted。形�?验证-修复-再验�?循环, 但循环在 Dispatcher 编排�?(`Dispatcher.dispatchStandardGeneration`, `Dispatcher.ets:585-751`), 修到 `best.hardIssueCount === 0` (`:666-669`)
- `repairDeepDraft` (`:375-451`): 同样 Reflexion 风格, 限定 `targets = issue.sectionId`, 不重做整�?draft
- `structureDeepDraft` (`:289-373`): 顺次 `callDeepSectionDraft` 每个 outlineSection, 维护共享 `ledger` (`formulas / terminology / conclusions :306, 559-581`)

**Loop**: KnowledgeModel 自身**无内循环** �?它的 repair 方法是被循环调用的纯转换; 真正 Reflexion 循环�?`Dispatcher.dispatchStandardGeneration`
**Tool**: **不调 AgentTool**; 通过 `LlmCaller` 多次�?LLM (`callStandardArtifacts / callIndependentVerifier / callDeepSectionDraft / callEvidenceRepair / callAi`)。预�?`KNOWLEDGE_MAX_TOKENS=12000`, `KNOWLEDGE_TIMEOUT_MS=300000` (`PromptBuilder.ets:10-11`)

### 7.4 TruthCheckService �?Pure function

**Pattern**: Pure function (4 项数学校�? 纯文�?�?文本+`truthFlag`)
**位置**: [`TruthCheckService.ets:1-283`](../../agents/src/main/ets/agents/TruthCheckService.ets)

- 公开�?`check(input) �?MvpTruthCheckResult` (`:32-34`); 4 检�? `checkBracePairing` (`:115-154`) + `checkDivisionByZero` (`:156-165`) + `checkEquation` (`:166-188`) + `checkLatexInternal` (`:189-231`)
- **CaptureGraph `truth_check` 节点的唯一实现** (`TruthCheckNode.ets:13`), **spec 015 后所有权已从 KnowledgeModel 移到 Capture pipeline**
- 返回�?`{truthFlag, details, correctedText}`, `TruthCheckNode` 映射�?`{passed, flags, message}` (`TruthCheckNode.ets:20-24`)

**Loop**: �?**Tool**: �?
### 7.5 PromptBuilder �?Pure function (Builder 不算 GoF 模式)

**Pattern**: Pure function (类只封装常量 + 单方�? 命名上像 Builder 但行为是函数)
**位置**: [`PromptBuilder.ets:1-58`](../../agents/src/main/ets/agents/PromptBuilder.ets)

- 公开 `build(input)` (`:19-21`) + `buildPrompt(ocrText)` (`:23-57`), 后者返�?*模板字符�?* (类别枚举 + 字段规范 + 渲染要求)
- 持有 7 个常�?(`KNOWLEDGE_INPUT_LIMIT` �?`:9-15`), 全部 `export const`, KnowledgeModel `KnowledgeModel.ets:88-96` import �?budget �?- �?GoF Builder 模式差异: �?*�?*分步构造复杂对�?(�?setter �?/ �?Director), 而是一次性返回字符串

**Loop**: �?**Tool**: �?
### 7.6 OcrTool �?Pure function (HTTP/SDK wrapper)

**Pattern**: Pure function (无状态工具类, 单一职责 = 图片 �?文本)
**位置**: [`OcrTool.ets:1-427`](../../agents/src/main/ets/mcp/tools/OcrTool.ets)

- 公开 3 入口 (`recognizeBytes / recognizeBytesWithEndpoint / recognize / recognizeImage :60-174`), 内部混合 CoreVisionKit 本地文本 (`textRecognition.recognizeText`, `:191-197`) + 本地 OCR 服务 fallback (`:267-278`)
- `recognize` (`:98-109`) 抛错 (�?`ok:false`), 因为它是 TypeClassifier �?*同步依赖**而非 AgentTool
- **不实�?AgentTool, 不进 ToolRegistry** (ADR-0010)

**Loop**: `recognizeBytesWithEndpoint` 重试 2 �?(`:74-88`), `requestFormulaWithRetry` 重试 2 �?(`:256-263`), `requestCombinedWithRetry` 重试 2 �?(`:268-276`) �?都是**传输层重�?*, 不是 ReAct/Reflexion
**Tool**: �?LLM

### 7.7 CaptureGraph �?Pipeline / DAG orchestration

**Pattern**: Pipeline / DAG orchestration (StateGraph 风格, 条件路由 + haltWhen)
**位置**: [`CaptureGraph.ets:1-99`](../../agents/src/main/ets/graph/CaptureGraph.ets)

- `CaptureGraph extends StateGraph<AgentState, CaptureStep>` 薄包�?(`:17-25`); `haltWhen` = `state.error !== undefined` (`:23`)
- 5 节点, 拓扑�?`Dispatcher.buildGraph` 完成, 详见 §4.2
- `addNode` �?try/catch (`:30-36`) 异常 �?`CaptureGraphError{kind:'NODE_ERROR'}`; `run` 终态化 `currentStep='END'` (`:58`)
- **不是** ReAct: 节点不基�?LLM 决策递归, �?*线�?+ 条件分支**的静态图; 终止条件�?`haltWhen` �?`addConditionalEdge` 路由函数 (`Dispatcher.ets:1524-1528`) 静态决�?
**Loop**: **无内循环** �?CaptureGraph 是单 pass DAG; 外层 `dispatchStandardGeneration` �?repair 循环时反�?invoke `buildGenerationGraph`, 这是 §7.3 �?Reflexion 循环, 不是 CaptureGraph 自身
**Tool**: **不直接调 AgentTool**; 节点通过注入 `TypeClassifier / KnowledgeModel / TruthCheckService / NoteDaoInterface` �?LLM �?DB

### 7.8 ToolCallingWorkflow �?ReAct

**Pattern**: **ReAct** (Reasoning + Acting 交错, `CallModelNode` �?`ExecuteToolsNode` 循环, LLM 决策 `toolCalls` 是否终止)
**位置**: [`ToolCallingWorkflow.ets:1-69`](../../common/src/main/ets/workflow/tool-calling/ToolCallingWorkflow.ets)

- 循环结构 (`:56-66`): `START �?call_model �?(toolCalls �? END : execute_tools) �?(stepCount>=maxSteps ? max_steps_error : call_model) �?END`
- LLM 决策循环终止 (`:57-62` `toolCalls.length === 0` �?END); 失控防护 `stepCount >= maxSteps` (`:63-65`) �?`TOOL_LOOP_MAX_STEPS`
- 每轮: `CallModelNode.run` �?LLM with `tools=[...], tool_choice='auto'` (`CallModelNode.ets:14-17`); `ExecuteToolsNode.run` 逐个 `registry.execute` + 回喂 OpenAI 格式 (`ExecuteToolsNode.ets:17-31`) �?教科�?ReAct 形状
- **�?Plan-and-Execute 区别**: 无独�?plan 阶段; LLM 在每�?inline 决策

**Loop**:
- 默认 `maxSteps=4` (`:9`), `maxSteps*3+4` �?StateGraph 余地 (`:40`)
- 终止: �?`toolCalls` �?�?END; �?`maxSteps` 触顶 �?抛错; �?未知工具/�?JSON �?`ok:false` 回喂, **�?*终止 (`ToolRegistry.ets:57-76` 容错) �?让模型自恢复 (`LlmToolCalling.test.ets:175-191`)

**Tool**: LLM via `LlmCaller.call` (CallModelNode `:21`); AgentTool via `ToolRegistry.execute` (ExecuteToolsNode `:24`); 协议 OpenAI 兼容, JSON 路径 (`ToolLoop.ets:6` 注释)
**生产消费�?*: **�?* (�?§10.2 #1)

### 7.9 ConversationWorkflow �?Multi-turn chat with state + Router

**Pattern**: Multi-turn chat with state (记忆 + 流式 + 意图路由) + Router / Classifier (kind/intent/responseMode 三层)
**位置**: [`ConversationWorkflow.ets:1-664`](../../entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets)

- `ConversationState` (`ConversationState.ets:49-60`) �?`sessionId / memoryContext / learnerProfileContext / draftRunId / draftStatus` 等多轮状态字�? **�?* UIAbilityContext/ArkUI/callback/DAO/LlmClient/ToolRegistry (符合 spec 018 §4)
- 9 节点 + 6 条件�?(`ConversationWorkflow.ets:124-232`):
  - `START �?(image?image_reply : regenerate?regenerate_reply : classify_intent)`
  - `classify_intent �?(note_generation?note_reply : load_reply_context)`
  - `load_reply_context �?save_reply_input �?(stream?stream_reply : complete_reply)`
- 多轮: `AgentMemoryService.saveMessage / getContextForReply / getContextForNoteGeneration` (`:524-578`) + `learnerProfileContext` + `summarizeSessionIfNeeded` (`:588-594`)
- **不是** ReAct: 节点执行**确定** (每个节点调什么服务是写死�? �?LLM 决策); 没有 tool_call 决策循环

**Loop**: 无内循环 (单次 run 是单 pass DAG); conversation 是多�?(外部多次 run)
**Tool**: **不直接调 AgentTool / ToolRegistry** (`ConversationWorkflow.ets:1-22` �?import); 通过 `ReplyService` �?LLM, 通过 `AiService` �?CaptureGraph 生成笔记

### 7.10 SkillIntentWorkflow �?Router / Classifier

**Pattern**: Router / Classifier (单层 action 路由, 不调 LLM)
**位置**: [`SkillIntentWorkflow.ets:1-86`](../../skill/src/main/ets/workflows/intent/SkillIntentWorkflow.ets)

- 4 节点 + 3 �?(`:29-74`): `START �?route_action �?(target==='search_note' ? execute_search : unsupported) �?END`
- 单层 Router: `state.request.target` 决定 execute_search �?unsupported (`:68-70`)
- **execute_search 不是 LLM tool_call**: 是直�?`registry.execute('note_query', argsJson)` (`:38`)
- **unsupported** 返回 `{ok:false, content:'Unsupported skill intent: '+action, errorKind:'UNSUPPORTED_INTENT'}` (`:58-62`), 对应 ADR-0011 "其余 6 �?action 明确 unsupported"

**Loop**: 无循�?**Tool**: **直接�?AgentTool** (`:38`); 不调 LLM; �?`'note_query'` 接�?
### 7.11 ReplyService �?Adapter (Stream + JSON fallback)

**Pattern**: Adapter pattern (封装 LLM 调用�?transport 选择: SSE 优先 + JSON 回退)
**位置**: [`ReplyService.ets:1-227`](../../entry/src/main/ets/services/ReplyService.ets)

- 公开 2 入口: `complete(context)` (`:49-51` �?`guardedComplete` JSON) + `stream(context, sink)` (`:68-146` �?SSE + JSON fallback)
- `stream` 内部 retry 1 �?(`:81-113` while loop, `streamAttempts < 2`), 首字节超时或 NETWORK_ERROR 才重�? 仍失�?�?`fallback()` (`:153-164`) �?`guardedComplete`
- 这是 **transport-level retry + fallback**, 不是 Reflexion (无自我批�?/ 无修复规�?
- 不实�?`StreamEvent` �?`tool_call / tool_result` emit (�?§7.6 一�?�?当前 SSE 不传工具循环)

**Loop**: `stream` �?retry `streamAttempts < 2` (`:81`); `fallback` 仅当 `shouldUseFallback(content)` = `content.trim().length === 0` (`:114, 166-168`) �?catch �?transport error (`:138-145`)
**Tool**: 不调 AgentTool; �?`LlmClient.call({stream:true, onDelta})` (`:83-100`) + `LlmGuard.callJsonWithRetry` (`:54-62`). 预算 `CHAT_REPLY_MAX_TOKENS=12000` (`:31`)

### 7.12 模式矩阵

| # | Agent / Workflow | Pattern | Has loop? | Max iter | Tool seam | State channels |
|---|---|---|---|---|---|---|
| 1 | `TypeClassifier` | Single-shot LLM + Pure function fallback | 内无 (LlmGuard JSON 重试 �?) | n/a | 同步 `OcrTool.recognize` (`:140, 146`); LLM `LlmGuard.callJsonWithRetry` (`:224-229`) | �?|
| 2 | `KnowledgeModel` | Plan-and-Execute + Reflexion (外层 Dispatcher 循环) | 内无 (�?Dispatcher 标准/深度 repair) | n/a | `LlmCaller.call` + `LlmGuard.callJsonWithRetry` (`:144-150`); 不调 AgentTool | �?(函数�? |
| 3 | `TruthCheckService` | Pure function | �?| n/a | �?| �?|
| 4 | `PromptBuilder` | Pure function (类惯用语) | �?| n/a | �?| �?|
| 5 | `OcrTool` | Pure function (HTTP/SDK wrapper) | 传输层重�?�? (`:74, 256, 268`) | 2 | �?(不实�?AgentTool) | �?|
| 6 | `CaptureGraph` | Pipeline / DAG orchestration | �?(�?pass DAG; haltWhen) | n/a | 不直�? 节点�?LLM/DB/OCR | `AgentState` 13 字段 |
| 7 | `ToolCallingWorkflow` | **ReAct** | �?显式循环 | `DEFAULT_MAX_STEPS=4` (`:9`) | `ToolRegistry.execute` (`:24`) + `LlmCaller.call` (`:21`) | `ToolCallingState` 8 字段 |
| 8 | `ConversationWorkflow` | Multi-turn chat with state + Router | 内无 (外多�? | n/a | 不调 AgentTool; LLM `ReplyService` (`:297, 337`) | `ConversationState` 9 字段 |
| 9 | `SkillIntentWorkflow` | Router / Classifier | �?| n/a | `ToolRegistry.execute('note_query', ...)` (`:38`); 不调 LLM | `SkillIntentState` 3 字段 |
| 10 | `ReplyService` | Adapter (Stream + JSON fallback) | retry �? (`:81`) | 2 | 不调 AgentTool; �?`LlmClient.call` + `LlmGuard.callJsonWithRetry` | 局部流式累�?(`:73, 94`) |

**模式分布**: 4 Pure function (TruthCheckService / PromptBuilder / OcrTool) + 2 Single-shot (TypeClassifier / ReplyService) + 1 ReAct (ToolCallingWorkflow) + 1 Plan-and-Execute+Reflexion (KnowledgeModel) + 1 Pipeline (CaptureGraph) + 1 Router (SkillIntentWorkflow) + 1 Multi-turn chat + Router (ConversationWorkflow)

**Loop 分布**: �?3 个有显式循环 (ToolCallingWorkflow=4 iter; ReplyService=2 iter; OcrTool=2 iter 传输重试), 其余 7 个无内循�?
**Tool 调用分布**: 5 个不�?AgentTool (TypeClassifier �?OcrTool MCP / KnowledgeModel �?LlmCaller / CaptureGraph 节点�?sub-services / ConversationWorkflow �?AiService+ReplyService / ReplyService �?LlmClient); 2 个直接调 (SkillIntentWorkflow �?`note_query`; ToolCallingWorkflow �?通用 ToolRegistry); 1 个同步工�?(TypeClassifier �?OcrTool MCP)

---

## 9. 决策一致性核�?
每条 = 当年出处 + 现状对照 + 结论�?
| # | 决策 | 当年出处 | 现状 | 结论 |
|---|---|---|---|---|
| 1 | 不用 LangGraph 运行�? 自建 StateGraph | ADR-0008 / research �?结论 | §3 + §4.1 | �?|
| 2 | �?dispatch 入口 | ADR-0003 / research �?§Implications | §4.4 (`Dispatcher.ets:98`) | �?|
| 3 | KnowledgeModel 拆为 PromptBuilder / StructureService / TruthCheckService | ADR-0006 / spec 015 | §4.5 + §8.3-8.5 | �?|
| 4 | LlmClient 合并�?`call()` 双路�?| ADR-0004 | §4.7 (`LlmClient.ets:60-70`) | �?|
| 5 | 失败不生�?fallback KU | ADR-0008 §Consequences / spec 011 §9 | §4.6 (`KnowledgeModel.ets:142-155`) | �?|
| 6 | StateGraph 不含 Checkpoint / Subgraph / HITL / Reducer / 并行 | spec 018 §"Out of Scope" | §4.1 (无对应类�? | �?|
| 7 | tool-calling State 必含 messages / stepCount / maxSteps / lastResult / toolCalls | spec 018 §3 | §7.4 (`ToolCallingState.ets:10-19`) | �?|
| 8 | Conversation State 不含 UIAbilityContext / ArkUI / callback / DAO / LlmClient / ToolRegistry | spec 018 §4 | §6.3 (`ConversationState.ets:49-60`) | �?|
| 9 | Conversation 流式 delta 走注入的 event sink | spec 018 §4 | §6.3 (`ConversationWorkflow.ets:317-371`) | �?|
| 10 | skill `SearchNote` 是唯一 wired action, 其余 unsupported | spec 018 / ADR-0011 | §8.10 (`SkillIntentWorkflow.ets:68-70`) | �?|
| 11 | ToolRegistry �?`common/` (不落 entry) | ADR-0012 §Chosen 1 | §7.2 (`ToolRegistry.ets:1`) | �?|
| 12 | P1 只读工具先于写工�?| ADR-0012 §Chosen 3 | §7.3 (`ToolCatalog` 只装�?readonly) | �?|
| 13 | OcrTool 不进 ToolRegistry, �?MCP 语义 | ADR-0010 | §7.7 (`OcrTool.ets:52` �?AgentTool 4 件套) | �?|
| 14 | OpenAI 兼容 wire 协议 (tools/tool_choice/tool_calls), 不依�?finish_reason | spec 014 §1.51 / ADR-0012 | §7.5 (`LlmResponseParser.ets:46-55`) | �?|
| 15 | ToolRegistry 容错执行 (未知工具/�?JSON �?ok:false, 不抛) | spec 014 §2 | §7.2 (`ToolRegistry.ets:57-76`) | �?|
| 16 | ToolLoop �?JSON 路径 (SSE 工具循环不在 scope) | spec 014 §3 + `ToolLoop.ets:6` 注释 | §7.6 | �?|

**16/16 一�?*。�?0 drift 都是实现细节 vs 措辞精度, 不与决策矩阵冲突�?
---

## 10. Drift 与开放项

�?§4-§8 当前实现对照 spec 011/014/015/018 / ADR-0008/0010/0011/0012 列出�?
### 10.1 �?drift (�?§9 决策红线, 仍建议修�?

| # | drift | 引用 | 修复 |
|---|---|---|---|
| 1 | spec 018 §6 措辞过时 (Conversation / SkillIntent 已生产化, 文档仍称 "subsequently reuse kernel") | `docs/specs/018-agent-workflow-architecture.md:85-89` | doc �?|
| 2 | Dispatcher 实际构建 3 �?graph 形�? spec 018 §2 只暗示未明列 | `Dispatcher.ets:1408, 1432, 1497` + §6.2 | doc �?|
| 3 | spec 011 §"Implementation Decisions 2" 未明�?`analysisOnly �?END` 早退�?| `Dispatcher.ets:1525` + §4.2 | doc �?|
| 4 | `CaptureGraphError.cause?: Object` 改为 `unknown` (ArkTS 严格类型收紧) | `AgentState.ets:30` + §4.3 | code (P3) |
| 5 | spec 018 §"验收" 待勾 "Hypium + 真机验收" 一�?| spec:137 | test/QA |
| 6 | research �?§6.5: `docs/agents/api-version.md` 文档漂移 (声称 compileSdk=9, 实际 6.1.1(24)) | `api-version.md` 全文 | doc (P2, **动态做** �?�?SDK 时间线同步改) |
| 7 | research �?§6.6: `harmonyos-kits-survey-2026-09-05.md §2` AIEngine / `@hms.ai.llm` 表述失实 | kits-survey §2 | doc (**动态做** �?标存疑持续更�? |
| 8 | `analyze()` �?`routeDispatch()` wrapper 已标"待删", D2 教学日志 §8 tickets #13/#14/#17 实施情况 | `d2-capturegraph-teaching-2026-09-05.md:208-211` | issue tracker 核销 |
| 9 | **ToolRegistry schema 漂移风险未消�?*。`NoteQueryTools.ets:5-6` 文件头注释说 "�?NoteDao 为准修这�?, 但无 CI 守门; `knowledge_unit` 17 列在 NoteQueryTools (`:97, 157`) �?entry NoteDao 同时声明 | `NoteQueryTools.ets:5-6` + §7.3 | **动态做** �?NoteDao 改时同步对齐 + �?AST 守门 |

### 10.2 �?drift (�?§9 决策矩阵潜在冲突, 需处置)

| # | drift | 引用 | 修复方向 |
|---|---|---|---|
| **H1** | **ToolLoop / ToolCallingWorkflow 零生产消费方**。spec 018:44 �?ToolLoop �?Tool-calling 稳定入口, 但全�?`new ToolLoop` 仅命�?`LlmToolCalling.test.ets:128,148,164,185` + 构建缓存; **没有任何生产代码调它**。`ConversationWorkflow` 不接 (spec 018:74 "工具循环只调�?ToolLoop" 未落�? | spec 018:44, 74; 实测 grep �?§7.2 �?| **待做 (§10.5 包装方式 MCP vs Kit/Tool 调研�?**: �?ToolCallingWorkflow �?ConversationWorkflow (答复/笔记生成); 或改 spec 018 §1 表格降级 ToolLoop �?"infrastructure, not yet wired" |
| **H2** | **ConversationWorkflow 不接 ToolLoop**。`ConversationWorkflow.ets:1-22` import 列表�?`ToolRegistry / ToolLoop`, spec 018:74 �?"工具循环只调�?ToolLoop; 不得复制两者逻辑", 当前 reply_service 仍是 `LlmClient.call` 直调 | spec 018:74; `ConversationWorkflow.ets:1-22` | **待做 (§10.5 包装方式调研�?**: �?ToolLoop �?ConversationWorkflow.handleCompleteReply/handleStreamReply; ToolCall 决策�?LLM 在对话内 inline �?|
| **S3** | **SSE + 工具循环 = 空白**。`StreamEvent` 类型�?4 值全定义 (`LlmTypes.ets:129`), �?`parseStreamEventsFromSseData` (`LlmClient.ets:497-522`) �?emit `thinking / text`, �?emit `tool_call / tool_result`; `ToolLoop.ets:6` 注释明说 "SSE 流式工具循环不在 spec 014" | `LlmTypes.ets:129`, `LlmClient.ets:497-522`, `ToolLoop.ets:6` | **待做 (§10.5 调研�?**: �?spec 014 extension / �?spec; �?`parseStreamEventsFromSseData` �?delta �?`tool_calls` �?emit `tool_call` 事件 |
| **S4** | **ToolLoop 零事件出�?*。`run()` 只返回最�?`LlmCallResult` (`ToolCallingWorkflow.ets:41-44`), 中间 tool_call/tool_result 不对外发事件, 无法驱动 UI 过程展示 | `ToolCallingWorkflow.ets:22-45` | **待做 (§10.5 调研�?**: �?`ToolLoopOptions.sink?: (event: StreamEvent) => void`, ExecuteToolsNode.emit tool_call/tool_result |
| **S5** | **P1 只读工具未在 entry/agents 注入**。`SkillAbility.ets:27` 唯一生产消费�? `entry/src/main/ets/` 全文 grep `ToolRegistry / ToolLoop / ToolCatalog` 无任�?match (�?§7.2 �?. spec 014 §"P1 首批工具" 明确 "已落�? 但应用方只在 skill | `agents/src/main/ets/Index.ets` + `entry/src/main/ets` grep | **待做 (§10.5 调研�?**: spec 014 后增�?"应用�?wiring" 章节; 或在 EntryAbility 启动�?`ToolCatalog.createReadOnlyRegistry()` 缓存 |

### 10.5 用户决策矩阵 (2026-09-16 当面裁决)

�?user 当面裁决 (§10.2 H1/H2/S3/S4/S5 + research �?§6 排除�?+ spec 015 P3 + spec 011/018 措辞修正 + spec 014 schema CI), 11 项处置如�?

| # | �?| 裁决 | 处置方式 |
|---|---|---|---|
| 1 | PushKit (隐私 + 运营成本) | **不做** | 排除, 不入任何 spec/plan |
| 2 | 端云同步 (API 23+, AGC + 真机 + 中国大陆) | **待定, 依据具体情况** | 复赛后视用户增长�?AGC 开通成本评�?|
| 3 | FunctionComponent 拉起小艺智能�?(AGC 限制) | **待定, 依据具体情况** | �?#2, 复赛后视演示形态需�?|
| 4 | 端侧 LLM (API 24 手机端无) | **不做, 不留痕迹** | capturegraph doc 中不�? research �?/ harmonyos-kits-survey 作为外部事实记录保留 |
| 5 | ToolLoop �?ConversationWorkflow (H1) | **需要做** | §10.6 包装方式 MCP vs Kit/Tool 调研后实�?|
| 6 | SSE tool_call/tool_result emit + ToolLoop 事件出口 (S3/S4) | **需要做** | �?#5, 同一 ticket 联动 |
| 7 | P1 工具�?entry/agents 注入 (S5) | **需要做** | �?#5, ToolLoop 落地后自然接�?|
| 8 | NoteQueryTools 写工�?(P2) | **需要做** | �?#5, 统一写入 gate 已完�? 工具本体待包装方式定后开 |
| 9 | `CaptureGraphError.cause?: Object �?unknown` (spec 015 P3) | **动态做** | 随下�?ArkTS 类型收紧或大�?`AgentState.ets` 时同步修�?+ 测试断言同步更新 |
| 10 | spec 018 §6 / §1.74 措辞修正 + spec 011 "Implementation Decisions 2" `analysisOnly→END` 明列 | **动态做** | 随代码改动同步更�?doc, 复赛 / 决赛前最后一�?doc 校对一起做 |
| 11 | ToolRegistry schema CI 守门 (NoteQueryTools vs NoteDao) | **动态做** | NoteDao 改时同步对齐 + �?AST 守门测试 |

### 10.6 包装方式调研 �?MCP vs Direct Tool (background agent 2026-09-16 完成)

**调研来源**: [`docs/research/tool-packaging-mcp-path-2026-09-16.md`](https://github.com/YunC-GCT/MindTrace/blob/develop/docs/legacy/mindtrace/research/tool-packaging-mcp-path-2026-09-16.md) (legacy) + [`docs/research/tool-packaging-direct-kit-path-2026-09-16.md`](https://github.com/YunC-GCT/MindTrace/blob/develop/docs/legacy/mindtrace/research/tool-packaging-direct-kit-path-2026-09-16.md) (legacy)

#### 10.6.1 两种路径的本质区�?
| 维度 | **MCP 路径** (`mcp/tools/OcrTool.ets` 模式, ADR-0010) | **Direct Tool 路径** (`common/tools/` ToolRegistry, ADR-0012 / spec 014) |
|---|---|---|
| **实现 contract** | 普�?class, 公开业务方法 (`recognize / recognizeBytes / recognizeImage`) | `implements AgentTool` 4 件套 (`name` + `description` + `parameters` JSON Schema + `execute(args)`) |
| **命名规则** | 无强�?(类名 / 方法名自�? | 严于 OpenAI wire: `^[a-z][a-z0-9_]{0,63}$` |
| **失败形状** | **抛错** (e.g. `OcrTool.recognize` `OcrTool.ets:101, 106` throw) | **不抛**: 返回 `{ok:false, content:'...'}` (ToolRegistry `ToolRegistry.ets:57-76` 容错执行) |
| **调用�?* | 同步直调 (e.g. `TypeClassifier.ets:140-148` `new OcrTool().recognize`) | LLM �?`tool_calls` JSON 决策, �?ReAct 循环 |
| **是否�?ToolRegistry** | **�?* (ADR-0010 + CONTEXT.md:111 显式排除) | **�?* �?ToolCatalog.createReadOnlyRegistry() 装配 |
| **命名空间** | `agents/src/main/ets/mcp/tools/` | `common/src/main/ets/tools/` |
| **协议�?* | 无标准协�? 调用方直�?| OpenAI 兼容 wire (`tools` / `tool_choice` / `tool_calls` �?`LlmTypes.ets:32-33, 224`) |

**核心判据**:
- **调用方是 LLM 还是代码?** LLM 决策 �?Direct Tool; 代码同步�?�?MCP
- **失败形状抛错还是容错?** 抛错 �?MCP (调用�?try/catch 已知失败形状); 容错 �?Direct Tool (LLM 需�?`ok:false.content` 自恢�?
- **需不需要外部系统暴�?** 需�?MCP server (小艺开放平�? research �?§4) �?MCP; �?app �?LLM �?�?Direct Tool

#### 10.6.2 #5-#8 决策�?(两项 agent 一致推�?

| # | drift | **推荐路径** | 理由 (�?agent 一�? |
|---|---|---|---|
| **#5 H1** | ToolLoop �?ConversationWorkflow | **Direct Tool** | `ToolLoop.run` �?`ToolRegistry` 参数; MCP-style `throw` �?*破坏 ReAct 自恢�?* (`ToolRegistry.ets:57-76` 容错设计) |
| **#6 S3** | SSE `tool_call` / `tool_result` emit | **Direct Tool** | 事件描述 `tool_calls.name` (AgentTool 词汇); MCP-style 工具**不发 `tool_calls`** |
| **#6 S4** | ToolLoop 事件出口 (`ToolLoopOptions.sink`) | **Direct Tool** | 扩展 `LlmClient.ets:497-522` `parseStreamEventsFromSseData` + �?sink; �?MCP 替代方案 |
| **#7 S5** | P1 只读工具�?entry/agents 注入 | **Direct Tool** | `NoteQueryTools.ets:50-247` 已是 ToolRegistry 形�? 直接 `ToolCatalog.createReadOnlyRegistry()` �?`EntryAbility.onCreate` 装配 |
| **#8 P2** | NoteQueryTools 写工�?(`note_create / note_update / note_delete`) | **Direct Tool** (�?`WriteToolFacade` 注入 `entry/KnowledgeUnitWriteService`, 复用 `NoteDaoAdapter` 验证�? | 统一写入 gate 要求**单一边界**�?`ToolRegistry.execute`; spec 014:134 / ADR-0012:13 写工具是 P2 路径; MCP 路径无法承载 entry 侧写入门 |

**结论**: **5 项全�?Direct Tool** �?MCP 路径**保留给未来的 pipeline 工具** (同步预处�? 音频→文�?/ 视频→文�?/ CoreVisionKit 其它形�?, **�?*用来承载 LLM 工具循环�?
#### 10.6.3 MCP 路径保留场景 (当前 + 未来)

- **当前**: `OcrTool` (`mcp/tools/OcrTool.ets`, ADR-0010 唯一实例) �?Capture pipeline 同步 OCR, 抛错, 不经 LLM 决策
- **未来候�?* (任何**同步 + 抛错 + 代码直调**的预处理工具):
  - **音频→文�?* (ASR via CoreSpeechKit 或自�?
  - **视频→关键帧** (VideoKit / MediaKit)
  - **图片增强 / 去噪** (ImageKit)
  - **公式识别 fallback** (MathPix / 二次 OCR)
- **判定**: 工具**早于** LLM 介入 capture pipeline + 抛错形状合�?try/catch �?MCP; 工具**晚于** LLM 决策 / �?LLM �?�?Direct Tool

#### 10.6.4 �?drift (Direct Tool agent 检�? 5 �?

| # | drift | 引用 | 修复 |
|---|---|---|---|
| **D1** | `LlmCallResult.toolCalls` �?JSON 路径填充, SSE 路径只靠 sink 透传 | `LlmClient.ets:74-167, 216-402` | �?`tool_calls` 累积字段; 或保�?sink 是唯一通道 (UI 接收方合�? |
| **D2** | `LlmCallOptions` �?`tools` 字段 �?`ReplyService.complete` �?`LlmGuard.callJsonWithRetry` �?*没有 tools 通路** | `LlmGuard.ets:37-66` + `ReplyService.ets:54-62` | `LlmCallOptions` �?`tools?: LlmToolDefinition[]` + `LlmGuard.callJsonWithRetry` 透传 |
| **D3** | `validateChatAnswerJson` 假设 JSON response shape, **不支�?tool-loop chat** | (待定�? grep `validateChatAnswerJson`) | chat �?tool-loop 时走不同 validate 路径, 或放�?schema |
| **D4** | `TextIntent` 词汇�?`'chat_with_tools'` | `IntentClassifier.ets:14` | 加新 intent �?(若分类器能识�?"用户想用工具" 的语义差�? |
| **D5** | NoteDao �?NoteQueryTools schema drift �?dynamic-only �?P2 写工具会**加剧** 风险 | `NoteDaoAdapter.ets` + `NoteQueryTools.ets` | §10.1 #9 CI 守门必须�?P2 写工具前落地 |

#### 10.6.5 实施顺序 (复赛后第一优先 ticket)

按依赖关�?
1. **#7 S5** (最简): `EntryAbility.onCreate` �?`ToolCatalog.createReadOnlyRegistry()` 缓存; `ReplyService` 构造注�?(1-2 行改�? �?这步**立刻** �?ToolLoop �?1 个生产消费方 (但暂未在 ConversationWorkflow 调用)
2. **#6 D2 + S4**: `LlmCallOptions.tools` + `ToolLoopOptions.sink` (前置 D2 才能�?ReplyService �?tools)
3. **#5 H1 + H2**: ConversationWorkflow �?`tool_call_reply` 节点 + `ReplyService.stream/complete` �?`ToolLoop.run` (主线改动, 需 Hypium 全绿)
4. **#6 S3**: SSE `parseStreamEventsFromSseData` �?emit `tool_call` / `tool_result` (依赖 D1 + ToolLoop sink)
5. **#8 P2**: 写工�?(依赖 §10.1 #9 CI 守门先行落地)

**推论**: #5/#6/#7 �?*一�?ticket** (ToolLoop 落地 + 工具层事件化); #8 �?*另一�?ticket** (写工�? �?CI 守门)�?


### 10.3 已核�?/ 不可�?(�?research �?�?

| # | �?| 来源 |
|---|---|---|
| A | AgentExtensionAbility / A2A / `createA2AServer` / `agentConstant` = API 26 (roadmap), 不在 API 24 | research �?�?25/48/49 |
| B | `@InsightIntent{Link, Page, Function, Form, Entry}` 五类 (�?"三类 @Intent") | research �?�?8 |
| C | 工作�?条件分支" = 选择器节�?+ 变量组件 (无独立节�? | research �?�?37 |
| D | CodeGenie 提示词库起始 6.1.0 Beta2 (�?6.0.2 Release) | research �?�?2 |
| E | OcrTool 不进 ToolRegistry (符合 ADR-0010 + CONTEXT.md:111) | `OcrTool.ets:52` + `ToolCatalog.ets:19-26` |
| F | ToolRegistry �?`common/` (符合 ADR-0012 §Chosen 1) | `common/src/main/ets/tools/ToolRegistry.ets:1`; `common/Index.ets:210` |
| G | P1 只读工具先于写工�?(符合 ADR-0012 §Chosen 3 "写工具赛�?) | spec 014 §4 + ADR-0012 |
| H | skill �?SearchNote 接�? 其余 UNSUPPORTED_INTENT | `SkillIntentWorkflow.ets:57-66` + ADR-0011 |

### 9.4 仍未核实

| # | �?| 来源 |
|---|---|---|
| α | Intents Kit 真机白名单流�?(仅第三方论坛�?`hagservice@huawei.com`) | research �?§8 |
| β | `@langchain/langgraph/web` 能否�?ArkTS 引擎稳定�?(无官方声�?/ 无社区案�? | research �?§8 |
| γ | localChatModel / RAG �?AGC 权益申请入口 | research �?§8 |
| δ | Cloud Foundation Kit 云数据库模块起始 API | research �?§8 |
| ε | 7 �?skill intent action 语义, 队员确认状�?| ADR-0011 §Open item + CONTEXT.md:119 |

---

## 11. 词汇 (�?CONTEXT.md 对齐)

| �?| 含义 | 引用 |
|---|---|---|
| **agent** | 4-way 消歧: MindTrace (app) / agents/ (HSP) / `Agent*` (用户�?service class) / sub-agent (私有协作�? | CONTEXT.md:168-177 |
| **CaptureGraph** | ArkTS 原生 LangGraph 风格 workflow; 不是架构全名 | CONTEXT.md:85 |
| **Order** | capture �?classify �?structure �?truth_check �?persist pipeline; 代码层是 `currentStep` + `CaptureStep` | CONTEXT.md:23 |
| **Dispatcher** | `dispatch(req, options)` 唯一公共入口; sub-agents 私有 | CONTEXT.md:81 + `Dispatcher.ets:98-100` |
| **DispatchOptions** | `analysisOnly / persist / includeRawText / dao` (+ spec 015/v2 加的 `generationRepository / knowledgeModel` DI) | CONTEXT.md:94 + `Dispatcher.ets:68-75` |
| **NoteDaoAdapter** | entry 侧适配 `agents/NoteDaoInterface`, 唯一实现 | CONTEXT.md:101 |
| **CaptureGraphError** | `kind, message, step, retriable, cause?` (cause �?`Object`, 待收�?`unknown`) | CONTEXT.md:91 + `AgentState.ets:25-31` |
| **MCP 工具 (mcp/)** | `OcrTool` �?MCP 风格工具, **�?*�?ToolRegistry 成员; �?`TypeClassifier.extractText` 直调 | CONTEXT.md:111 + ADR-0010 |
| **StreamEvent** | `{type, payload}` with `type �?{thinking, text, tool_call, tool_result}`; thinking 来自 `reasoning_content` delta | CONTEXT.md:123 + `LlmTypes.ets:129` |
| **Token Budget** | `ReplyService.CHAT_REPLY_MAX_TOKENS=12000` (对话); `KNOWLEDGE_MAX_TOKENS=12000` (KnowledgeModel) | CONTEXT.md:127 + `PromptBuilder.ets:10` |
| **截断处理** | 流式 `finish_reason === 'length'` �?final text event �?`\n\n + TRUNCATION_MARKER` | CONTEXT.md:131 + `LlmClient.ets:517-520` |
| **小艺 skill** | skill/ HSP, 7 �?declared action �?`SearchNote` wired | CONTEXT.md:119 + `SkillAbility.ets:24-28` |
| **AgentTool** | 工具注册契约: `{name, description, parameters, execute(args)}`, 命名 `^[a-z][a-z0-9_]{0,63}$` | `ToolRegistry.ets:17-22, 25` |
| **ToolResult** | `{ok: boolean, content: string}` �?ReAct 工具回喂格式 | `ToolRegistry.ets:11-14` |
| **ReAct** | 思考↔工具交错循环, 终止�?LLM 决策 + `maxSteps` 上限 | ToolCallingWorkflow + §8.8 |
| **Reflexion** | 校验失败→修复→重试, 自我批评驱动 | KnowledgeModel.repair* + §8.3 |
| **Plan-and-Execute** | 计划→子任务→执�?| KnowledgeModel.structureStandardDraft |

---

## 12. 来源

### 11.1 合并�?(�?research / teaching, 留为决策历史)

| 文件 | 路径 |
|---|---|
| �?baseline | [`docs/legacy/mindtrace/research/agent-framework-comparison-2026-09-02.md`](https://github.com/YunC-GCT/MindTrace/blob/develop/docs/legacy/mindtrace/research/agent-framework-comparison-2026-09-02.md) |
| �?Python sidecar proposal (not adopted, �?§3.2) | [`docs/legacy/mindtrace/research/langgraph-migration-2026-09-02.md`](https://github.com/YunC-GCT/MindTrace/blob/develop/docs/legacy/mindtrace/research/langgraph-migration-2026-09-02.md) |
| �?full chain map | [`docs/legacy/mindtrace/research/capturegraph-processing-chain-2026-09-16.md`](https://github.com/YunC-GCT/MindTrace/blob/develop/docs/legacy/mindtrace/research/capturegraph-processing-chain-2026-09-16.md) |
| �?tool layer + patterns | [`docs/legacy/mindtrace/research/capturegraph-tool-layer-and-patterns-2026-09-16.md`](https://github.com/YunC-GCT/MindTrace/blob/develop/docs/legacy/mindtrace/research/capturegraph-tool-layer-and-patterns-2026-09-16.md) |
| D2 实施日志 | [`docs/agents/d2-capturegraph-teaching-2026-09-05.md`](https://github.com/YunC-GCT/MindTrace/blob/develop/docs/agents/d2-capturegraph-teaching-2026-09-05.md) |

### 11.2 权威规范 (spec / ADR)

- [`docs/adr/0003 / 0004 / 0006 / 0008 / 0010 / 0011 / 0012`](https://github.com/YunC-GCT/MindTrace/blob/develop/docs/adr/)
- [`docs/specs/011-capturegraph-arkts-refactor`](https://github.com/YunC-GCT/MindTrace/blob/develop/docs/specs/011-capturegraph-arkts-refactor.md) · [`014-tool-calling-protocol`](https://github.com/YunC-GCT/MindTrace/blob/develop/docs/specs/014-tool-calling-protocol.md) · [`015-knowledge-model-decomposition-v2`](https://github.com/YunC-GCT/MindTrace/blob/develop/docs/specs/015-knowledge-model-decomposition-v2.md) · [`018-agent-workflow-architecture`](https://github.com/YunC-GCT/MindTrace/blob/develop/docs/specs/018-agent-workflow-architecture.md)

### 11.3 正交 (被本文档排除, 单独引用)

- [`docs/research/agent-toolkit-and-skill-dispatch-2026-09-06.md`](https://github.com/YunC-GCT/MindTrace/blob/develop/docs/research/agent-toolkit-and-skill-dispatch-2026-09-06.md) �?工具�?/ skill 调度, **与本文档无关**
- [`docs/research/langgraph-mapping-verification-2026-09-06.md`](https://github.com/YunC-GCT/MindTrace/blob/develop/docs/research/langgraph-mapping-verification-2026-09-06.md) �?LangGraph 概念 �?鸿蒙 Kit API 核查, **不涉�?CaptureGraph 处理�?*

### 11.4 代码引用 (�?

| 文件 | 行区�?|
|---|---|
| `common/src/main/ets/workflow/StateGraph.ets` | 1-88 |
| `common/src/main/ets/workflow/tool-calling/{ToolCallingWorkflow,ToolCallingState,nodes/{CallModelNode,ExecuteToolsNode}}.ets` | 1-69 / 1-45 / 1-51 |
| `common/src/main/ets/tools/{ToolRegistry,ToolCatalog,ToolLoop,NoteQueryTools}.ets` | 1-77 / 1-27 / 1-25 / 1-253 |
| `common/src/main/ets/llm/{LlmClient,LlmGuard,LlmTypes,LlmResponseParser}.ets` | 60-522 / 5-66 / 13-225 / 26-55 |
| `agents/src/main/ets/graph/{CaptureGraph,AgentState,nodes/*.ets}.ets` | 1-99 / 1-98 / �?7-84 |
| `agents/src/main/ets/core/Dispatcher.ets` | 68-1531 (关键段已逐节�? |
| `agents/src/main/ets/agents/{KnowledgeModel,TruthCheckService,PromptBuilder,TypeClassifier}.ets` | 关键段已逐节�?|
| `agents/src/main/ets/mcp/tools/OcrTool.ets` | 1-427 |
| `agents/src/main/ets/models/NoteDaoInterface.ets` | 全文 (�? |
| `entry/src/main/ets/services/{AiService,AgentChatService,ReplyService}.ets` | 关键段已逐节�?|
| `entry/src/main/ets/workflows/conversation/{ConversationWorkflow,ConversationState,ConversationTypes}.ets` | 32-371 (关键�? |
| `entry/src/main/ets/adapters/NoteDaoAdapter.ets` | 15-74 |
| `skill/src/main/ets/{skillability/SkillAbility.ets,workflows/intent/{SkillIntentWorkflow,IntentRouter}.ets}` | 1-48 / 1-86 |
| `CONTEXT.md` | 23, 81, 85, 91, 94, 101, 111, 119, 123, 127, 131, 168-177 |

---

## Appendix A. 维护说明

- **本文�?* �?CaptureGraph 处理�?+ 工具�?+ 设计模式�?*唯一权威研究**; �?5 份已�?`docs/legacy/mindtrace/research/` (其中 d2-capturegraph-teaching 留在 docs/agents/ 不移 �?是教学日志不�?research)
- **更新触发**:
  - CaptureGraph / Dispatcher / KnowledgeModel / ToolRegistry 任一重大变更 �?�?`docs/research/` 开�?dated 调研, 把本文档�?"see also"
  - spec 011 / 014 / 015 / 018 修订 �?先看 §9 决策矩阵是否仍成�?  - 新工作流接入 (当前 4 �? Capture / ToolCalling / Conversation / SkillIntent) �?§6 补充 + §8 加模�?+ §9 加决策项
  - �?agent 加入 �?§8 加一�? §8.12 加一�? §10.2 H1/H2 (ToolLoop / ToolLoop wiring) 重评
  - **笔记生成重大变更** (route 算法 / verification 策略 / incremental 粒度) �?§5 同步更新; 引入 RAG 时按 §5.6 约束
- **drift 推进**:
  - §10.2 H1/H2 各开 P1 ticket (ToolLoop �?ConversationWorkflow 是复赛后路径)
  - §10.2 S3-S5 + §10.1 9 条按优先级排�?- **未核�?(α/β/γ/δ/ε)**: 不主动开 ticket, 等外部信�?(AGC 权益 / 鸿蒙 7 文档 / 队员确认) 落地后核
- **附录历史**: Appendix B 仅作 git archaeology �? 不影响新人阅�? 若内容过�? �?"see also" 而非删除

---

## Appendix B. 实施链路 (D2 历史, 2026-09-05 ~ 09-08)

来源: [`docs/agents/d2-capturegraph-teaching-2026-09-05.md`](https://github.com/YunC-GCT/MindTrace/blob/develop/docs/agents/d2-capturegraph-teaching-2026-09-05.md) (教学日志完整�?

### B.1 D2 范围与边�?
**�?*: ArkTS 轻量 CaptureGraph 运行�?+ AgentState/CaptureNode 契约 + KnowledgeModel 拆为 PromptBuilder / StructureService / TruthCheckService �?façade + Dispatcher 装配 CaptureGraph + 唯一入口 `dispatch(req, opts?)` + LlmErrorKind �?`NORMALIZE_KEYWORD_REJECTED` + 文档允许 hvigor CLI 作为合法 build 入口�?
**不做**: 产品能力增量 / Python LangGraph / Checkpoint / HITL / Subgraph / AI 自修复循环�?
### B.2 Commit �?(按时间顺�? 12 �?

```
050349e docs(research): add HarmonyOS Kit survey
9dec5fc docs(specs): add CaptureGraph ArkTS refactor spec
48c7c65 docs(agents): allow hvigor CLI as build entry point
0ec3f3b fix(common): add LlmErrorKind.NORMALIZE_KEYWORD_REJECTED
6f0085b feat(agents): add CaptureGraph runtime and Capture nodes
4d83f3b refactor(agents): add KnowledgeModel service facades
a2e0ffa refactor(agents): wire Dispatcher to CaptureGraph with compatibility wrappers
1a27723 test(agents+lint): add CaptureGraph unit tests and AST behavior tests
b1fce56 refactor(agents): single dispatch entry; buildGraph accepts NoteDaoInterface
f3eaa92 refactor(entry): wire AiService to CaptureGraph via NoteDaoAdapter
6ffc93b test(agents+lint): align AST tests with single-dispatch and Adapter pattern
a42e3d0 test(agents): align Hypium tests with ArkTS 1.1 strict
cc99a5b fix(graph): preserve last step in final state when persist runs
b068df5 test(agents): use PersistTracker to verify persist node runs
e944c0a test(agents): replace assertUndefined with assertEqual/assertTrue (Hypium compat)
7fca898 test(agents): drop flaky error undefined check; rely on tracker and currentStep
8b52f9a test(agents): use module-level tracker and captureText assertion for persist
```

### B.3 关键踩坑 (本节是教学日�?§6 的精简)

| �?| 根因 | 对策 |
|---|---|---|
| `LlmErrorKind` 联合类型遗漏 | `LlmConfig.ets` �?`'NORMALIZE_KEYWORD_REJECTED'`, 联合里没�?| enum-like 联合类型修改�?grep 所�?`throw new LlmError(...)` 站点 |
| `agents/Index.ets` 未导出新类型 | `entry` `import { NoteDaoInterface, KnowledgeUnitExt } from 'agents'` 失败 | 新增跨模块接口后**必须**同步 `Index.ets` |
| Hypium `assertUndefined()` 不支�?| Hypium 1.0.25 链式 `.assertUndefined()` �?`actualValue is [object Object]` | �?`assertEqual(undefined)` �?`assertTrue(undefined)` |
| `tracker.ran` 断言闭包捕获失败 | TS 编译路径弱化内层 `const` 捕获 | 副作用状态提到模块级 `const moduleTracker` |
| hvigor CLI daemon 环境继承 | IDE 外终端首次跑 daemon 时空环境, �?SDK/Java 路径, daemon 一旦启动后续改环境不生�?| 每次新会�?`export DEVECO_SDK_HOME / JAVA_HOME / PATH`, 改完 `hvigorw --stop-daemon` |
| PR base 选错 | 第一次用 `--base main`, 违反 AGENTS.md 红线 6 | 默认 base = `develop` |
| `assembleHap -p module=...` �?`assembleApp` 区别 | `assembleHap` 可叠�?`-p module=agents`; `assembleApp` **不能**叠加 | Hypium �?`:agents:default@UnitTestArkTS`, 只能 DevEco GUI 触发 |

### B.4 验证

- `hvigor assembleHap`: BUILD SUCCESSFUL (首次 59s 401ms, 增量 9-19s)
- `node --test scripts/arkts-lint/tests/*.test.mjs`: 83/83 通过 (D2 时点)
- DevEco GUI Hypium: 3/3 通过

