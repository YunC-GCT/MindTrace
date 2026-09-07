# MindTrace → LangGraph 迁移方案

> **日期:** 2026-09-02
> **范围:** 把 MindTrace 的 agent 流水线从当前自定义 `Dispatcher` 迁移到 **LangGraph** 需要做哪些调整
> **项目:** MindTrace (`<本地仓库根>`)
> **作者:** 后台 research agent(被主 agent 替换完成;原 agent 因超时被中断,主 agent 接手)
> **前置文档:** [agent-framework-comparison-2026-09-02.md](./agent-framework-comparison-2026-09-02.md) — 已确认 MindTrace **当前不是** 基于 LangGraph

---

## 执行摘要

| 指标 | 值 |
|---|---|
| 总工作量 | **3-5 人周**(1 名工程师,4-6 周) |
| 风险等级 | **中高**(涉及每个 agent 代码路径;重写 Dispatcher;有回归风险) |
| 推荐分阶段 | **渐进式** — 一次迁移一个 sub-agent,加 feature flag |
| 阻塞依赖 | 无(LangGraph 是独立库) |
| 栈决策 | **Python (LangGraph)** vs **TypeScript (langgraphjs)** — 见 §6 |
| 需要的新文档 | 1 个 ADR(采用 LangGraph)、4 个 spec 更新、1 个新 spec(新 state schema) |

**主要建议**: 采用 **Python 中的 LangGraph** 作为独立服务。MindTrace 的 HarmonyOS 前端继续用 ArkTS;agent 运行时迁移到 Python 后端,通过 HTTP 与 ArkTS 通信。这隔离了重写范围,并与 2026 年 AI/agent 代码的自然栖息地一致。

---

## 1. 当前状态(迁移前)

MindTrace 的 agent 流水线是 **自定义 Dispatcher + sub-agent 管道**(详见 [前一阶段 research](./agent-framework-comparison-2026-09-02.md))。

### 1.1 组件清单

| 组件 | 文件 | 行数 | 公共 API |
|---|---|---|---|
| 编排器 | `agents/src/main/ets/core/Dispatcher.ets` | 159 | `analyze(req)`, `dispatch(req)`, `routeDispatch(req)` |
| Sub-agent 1 | `agents/src/main/ets/agents/TypeClassifier.ets` | 363 | `classify(payload, ctx)`, `recognizeText(payload, ctx)` |
| Sub-agent 2 | `agents/src/main/ets/agents/KnowledgeModel.ets` | 929 | `structure(ocrText, ...)`(god class) |
| LLM 客户端 | `common/src/main/ets/llm/LlmClient.ets` | ~500 | `call(messages)`, `callStream(messages)`, `callSseTokens(messages)` |

### 1.2 当前数据流(根据 `Dispatcher.ets:97-152`)

```
AiService.capture(imageUri, userText)
  │
  ▼
new Dispatcher().dispatch(req)                   // Dispatcher.ets:97
  │
  ├─ Step 1: new TypeClassifier().recognizeText()  // Dispatcher.ets:105
  │           │
  │           └─ LlmClient.callStream()  (或 callSseTokens)
  │
  ▼
recognized.text  (字符串)
  │
  ├─ Step 2: new KnowledgeModel().structure()       // Dispatcher.ets:129
  │           │
  │           └─ LlmClient.call()  (或 callStream)
  │
  ▼
KnowledgeUnit
  │
  ▼
DispatchResult
```

**同步**、**线性**、**无状态机**、**无 checkpoint**、**无中断**。

### 1.3 当前设置的问题(从 LangGraph 角度看)

- ❌ 没有**状态机** — 状态隐含在局部变量中
- ❌ 没有**checkpoint** — 如果 `KnowledgeModel.structure` 中途失败,整个 `dispatch` 失败
- ❌ 没有**条件路由** — 每张照片都走相同的流程
- ❌ 没有 **HITL(人在环)** — 无法暂停等待用户确认
- ❌ 没有**并行节点** — `TypeClassifier` 和 `KnowledgeModel` 严格串行
- ❌ 没有**子图组合** — 无法复用管道
- ❌ 没有**可观测性** — 无内置 tracing;只能手动加 `console.log`
- ❌ 没有**持久化** — 每次 dispatch 从头开始(无记忆)

---

## 2. 目标状态(迁移后)

一个 **LangGraph `StateGraph`**,镜像当前流水线但增加上面的框架特性。

### 2.1 目标架构(在 Python 中,作为 HTTP 后端)

```
ArkTS 前端(HarmonyOS 设备)
  │
  │  HTTP POST /dispatch
  ▼
LangGraph 服务(Python,运行在服务器上)
  │
  │  从 build_graph() 编译的图
  ▼
StateGraph: ocr_text → classify → structure → [conditional] → END
                │             │              │
                ▼             ▼              ▼
            LLM 调用      LLM 调用        验证
            (子图)        (子图)          (函数)
                │             │              │
                └───── State ─────────────────┘
                       (TypedDict)
```

### 2.2 目标 state schema(`src/graph/state.py`)

```python
from typing import TypedDict, Optional, Literal

NoteType = Literal["概念", "定理", "公式", "证明题", "计算题"]
DispatchStep = Literal["ocr", "classify", "structure", "validate", "done"]

class AgentState(TypedDict, total=False):
    # 输入(由 entry 节点设置)
    image_uri: Optional[str]
    user_text: Optional[str]
    source: str

    # 流水线状态
    ocr_text: str                  # 由 OCR 节点填充
    category: NoteType             # 由 classify 节点填充
    confidence: float
    knowledge_unit: dict           # 由 structure 节点填充

    # 元数据
    current_step: DispatchStep
    error: Optional[str]           # 失败时设置
    duration_ms: int
```

### 2.3 目标节点(`src/graph/nodes.py`)

```python
from langgraph.graph import StateGraph
from .state import AgentState

def ocr_node(state: AgentState) -> AgentState:
    """OCR / 文本提取。镜像 TypeClassifier.recognizeText()。"""
    ...

def classify_node(state: AgentState) -> AgentState:
    """5 类分类。镜像 TypeClassifier.classify()。"""
    ...

def structure_node(state: AgentState) -> AgentState:
    """KnowledgeUnit 构造。镜像 KnowledgeModel.structure()。"""
    ...

def validate_node(state: AgentState) -> AgentState:
    """健全性检查。替换 KnowledgeModel 的隐式验证。"""
    ...

def build_graph():
    workflow = StateGraph(AgentState)
    workflow.add_node("ocr", ocr_node)
    workflow.add_node("classify", classify_node)
    workflow.add_node("structure", structure_node)
    workflow.add_node("validate", validate_node)
    workflow.set_entry_point("ocr")
    workflow.add_edge("ocr", "classify")
    workflow.add_edge("classify", "structure")
    workflow.add_edge("structure", "validate")
    workflow.add_edge("validate", "__end__")
    return workflow.compile()
```

---

## 3. 组件迁移

### 3.1 `Dispatcher` → LangGraph `StateGraph`

| 方面 | 之前 | 之后 |
|---|---|---|
| 代码 | 159 行 TS,3 个公共方法 | ~50 行 Python 图定义 + entry HTTP handler |
| 状态 | 局部变量 | TypedDict(类型化、可检查) |
| 持久化 | 无 | `MemorySaver`(进程内)或 `PostgresSaver`(持久) |
| 实现时间 | n/a | 3-5 天(含 LangGraph 学习曲线) |
| 风险 | n/a | 中(重写 orchestrator) |
| 迁移步骤 | n/a | (1) 加 `src/graph/` 骨架。(2) 实现 `ocr_node` 作为对 `TypeClassifier.recognizeText` HTTP 调用的包装。(3) 加 feature flag。(4) 翻 flag。(5) 移除 `Dispatcher.dispatch` 调用。 |

### 3.2 `TypeClassifier` → LangGraph `classify_node`

| 方面 | 之前 | 之后 |
|---|---|---|
| 代码 | 363 行 TS,2 个方法 | 50 行 Python `classify_node` 调用 LLM + 解析 JSON |
| 状态 | 局部变量 | `state["category"]`, `state["confidence"]` |
| 复用 | 仅通过 `Dispatcher.dispatch` | 在任何未来流程中可作为子图复用 |
| 时间 | n/a | 2-3 天(主要是移植逻辑) |
| 风险 | n/a | 低(sub-agent,容易 A/B) |
| 迁移步骤 | (1) 把 JSON Schema + 解析移植到 Python。(2) 加单元测试。(3) 从 `classify_node` 调用。 |

### 3.3 `KnowledgeModel`(god class)→ LangGraph `structure_node` + `validate_node`

| 方面 | 之前 | 之后 |
|---|---|---|
| 代码 | 929 行,1 个方法 (`structure`) | 2 个节点:`structure_node` (~150 行) + `validate_node` (~50 行) |
| 状态 | 隐式 | `state["knowledge_unit"]` |
| 复用 | 无 | 两个节点都可在任何图中复用 |
| 时间 | n/a | 3-5 天(根据 ADR-0006 + spec 003,god class 已在拆分) |
| 风险 | n/a | 中(保留 929 行行为) |
| 迁移步骤 | (1) 把 `structure()` 移植到 Python(保留输出 schema)。(2) 提取 `truthCheck` 到 `validate_node`(原本内联在 `KnowledgeModel`)。(3) 加 characterization tests。(4) 把两个节点接入图中。 |

### 3.4 `LlmClient`(3 个方法)→ LangChain `ChatModel`

| 方面 | 之前 | 之后 |
|---|---|---|
| 代码 | ~500 行 TS,3 个方法 | 替换为 LangChain 的 `ChatOpenAI` / `ChatAnthropic` 等 |
| 流式 | 手动 SSE 解析(`callSseTokens`) | LangChain `ChatModel.stream()` 内置 |
| 复用 | MindTrace 中 2 个调用者 | 所有 LangGraph 节点都使用 |
| 时间 | n/a | 1-2 天(用 `langchain.chat_models.init_chat_model` 替换 TS LlmClient) |
| 风险 | n/a | 低(成熟路径) |
| 迁移步骤 | (1) 加 `langchain-core` + provider SDK。(2) 移除 `LlmClient.ets`(或为旧调用者保留)。 |

---

## 4. 要引入的 LangGraph 概念

根据 [agent-glossary.md](../agents/agent-glossary.md),MindTrace 将采用这些通用概念:

| 概念 | 在 MindTrace 中的用途 |
|---|---|
| **StateGraph** | 整个流水线(`ocr → classify → structure → validate`) |
| **TypedDict state** | `AgentState`(见 §2.2) |
| **Node** | 每个流水线阶段一个(共 4 个) |
| **Edge (normal)** | `ocr → classify → structure → validate → end` |
| **Conditional edge** | 可选:如果 `validate` 失败,路由到 `fallback` 节点进行重试 |
| **Checkpointer** | `MemorySaver`(开发)或 `PostgresSaver`(生产)— 每个线程的状态,用于 HITL 和恢复 |
| **Thread** | 一个用户照片 = 一个 `thread_id`(UUID) |
| **Command** | 用于 HITL(例如,用户确认低置信度分类) |
| **Tool** | 如果模型支持 vision,可以用 tool-call 替代 OCR 步骤 |
| **Subgraph** | 可以将 `ocr + classify` 打包为在其他流程中复用的子图 |

---

## 5. 迁移策略

### 5.1 推荐:在 Python 中作为边车服务采用

**为什么是 Python 而不是 langgraphjs?**

- LangGraph 是 Python 原生;langgraphjs 较不成熟,集成较少
- AI/agent 代码位于 Python 生态系统(LangChain、LlamaIndex 等)
- ArkTS 前端是表现层 + I/O;agent 逻辑最好放在 Python
- 这与当前的 OCR 服务(Python FastAPI)匹配 — 相同的运维模型

**架构**:

```
┌────────────────────┐     HTTP     ┌────────────────────┐
│  ArkTS Frontend     │ ──────────→ │  Python LangGraph    │
│  (HarmonyOS device) │              │  Service (server)    │
│  AiService.capture() │              │  POST /dispatch      │
└────────────────────┘              └────────────────────┘
```

### 5.2 分阶段(渐进,4-6 周)

**阶段 1:基础(1 周)**

- (a) 创建 `services/agent-runtime/`(新 Python 项目)
- (b) 添加 LangGraph + LangChain + provider SDK
- (c) 实现 `AgentState` + `build_graph()` 含 stub 节点
- (d) 添加 FastAPI 端点 `POST /dispatch` 返回 `DispatchResult`
- (e) 为图添加单元测试

**阶段 2:迁移一个 sub-agent(1 周)**

- (a) 把 `TypeClassifier.classify` 移植到 Python
- (b) 在图中接入 `classify_node`
- (c) 添加 feature flag:`USE_LANGGRAPH_FOR_CLASSIFY=1`(调用 Python,否则调用 ArkTS)
- (d) 在真实数据上做 A/B 测试
- (e) 发布

**阶段 3:剩余 sub-agents + 主流程(1-2 周)**

- (a) 把 `KnowledgeModel.structure` 移植到 Python(`structure_node` + `validate_node`)
- (b) 移植 OCR 步骤(调用 `OcrTool` HTTP)
- (c) 接入完整图
- (d) 添加 `MemorySaver` checkpointer
- (e) 为低置信度分类添加 HITL interrupt
- (f) 将 feature flag 翻到 100%

**阶段 4:清理(1 周)**

- (a) 移除 `Dispatcher.ets`、`TypeClassifier.ets`、`KnowledgeModel.ets`、`LlmClient.ets`
- (b) 移除 ADR-0003(Dispatcher 单入口)和 ADR-0004(LLMClient 合并)— 都被 LangGraph 取代
- (c) 更新 ADR-0006(KnowledgeModel 拆分)— 部分过时;保留经验教训
- (d) 更新 spec 003 / 004 / 005 / 007 — 都描述旧架构
- (e) 新 ADR:"采用 LangGraph 作为 agent 运行时"
- (f) 新 spec:"Agent state schema 和图定义"

---

## 6. 待决问题

开始迁移前需要用户回答:

1. **Python vs langgraphjs?** — 推荐:Python(见 §5.1)
2. **服务部署?** — 与 OCR 服务并排?独立?Kubernetes?
3. **LLM 调用成本?** — 当前模型?迁移到更便宜/更快的?(超出本 research 范围,但影响设计)
4. **持久化?** — `MemorySaver`(进程内,开发)或 `PostgresSaver`(持久,生产)?— 影响 HITL 设计
5. **HITL 阈值?** — 当 `confidence < 0.8` 时,暂停等待用户确认?— 影响 UX
6. **现有 ArkTS 代码怎么办?** — 作为后备保留,还是完全移除?
7. **多语言支持?** — agent 运行时需要同时支持中文和英文 prompt 吗?(MindTrace 大概率需要)
8. **state schema 版本化?** — `AgentState` 会演进;如何处理旧 checkpoint?

---

## 7. 结论

MindTrace 的 agent 流水线**已准备好迁移到 LangGraph**:当前自定义 Dispatcher 很小(159 行),sub-agent 边界清晰,所以重写范围受控。最大风险是 **KnowledgeModel god class**(929 行),需要拆分为 `structure_node` + `validate_node` 加上 state schema。

**推荐**:在 Python 中作为边车服务采用 **LangGraph**,渐进地,4-6 周。每个阶段可独立发布。

**启动前置条件**:用户回答 §6 中的 8 个待决问题(特别是 Q1 和 Q2 — Python vs langgraphjs,以及服务部署)。

---

## 8. 主要来源引用

| 论断 | 来源 |
|---|---|
| Dispatcher 是 159 行,3 个方法 | `agents/src/main/ets/core/Dispatcher.ets:55, 63, 97, 155` |
| 流水线顺序:`recognizeText → structure` | `agents/src/main/ets/core/Dispatcher.ets:105, 129` |
| TypeClassifier 是 363 行 | `agents/src/main/ets/agents/TypeClassifier.ets`(第 1-363 行) |
| KnowledgeModel 是 929 行 god class | `agents/src/main/ets/agents/KnowledgeModel.ets`(第 1-929 行);在 ADR-0006 中标记 |
| LlmClient 有 3 个方法 | `common/src/main/ets/llm/LlmClient.ets`(根据 spec 005) |
| MindTrace 不是基于 LangGraph | [agent-framework-comparison-2026-09-02.md](./agent-framework-comparison-2026-09-02.md)(commit daa5114) |
| Dispatcher 合并为单入口 | ADR-0003 |
| LLMClient 合并 | ADR-0004 |
| KnowledgeModel 拆分 | ADR-0006, spec 003 |
| LangGraph Python API | https://langchain-ai.github.io/langgraph/(StateGraph、nodes、edges、checkpointers) |
| Agent-glossary 定义(Node、State、Edge 等) | `docs/agents/agent-glossary.md` |

---

## 9. 下一步

1. 用户审查本 research 并回答 §6 中的 8 个待决问题
2. 如果用户批准:创建新 ADR "采用 LangGraph 作为 agent 运行时"(这是开始编码的门槛)
3. 阶段 1(基础)可与新 ADR 并行开始
4. 阶段 1 之后:编写 spec "Agent state schema 和图定义"(所有后续代码的规范参考)

本 research 文档是入口。代码尚未修改。

---

## 10. 维护说明

**何时更新此文件:**

- 每个阶段完成后:用实际花费的工作量更新 §5.2
- 如果用户回答 §6 中的问题:相应更新建议
- 如果 LangGraph 主版本发布:重新验证 API 示例
- 如果现有 ADR (#3、#4、#6)被取代:交叉链接到新 ADR

**文件版本提升条件(任一):**

- 工作量估算变化 > 20%
- 分阶段策略变化(渐进 → 大爆炸)
- 新的待决问题被回答
- 某个阶段完成(标记 ✅)

当前版本:1.0(初始)。最后更新 2026-09-02。

**重要**:本 HTML 是 `langgraph-migration-2026-09-02.md` 的渲染版本。修改时**先改 .md**(权威源),再重新生成 .html。两个文件必须保持同步。
