# MindTrace 分层架构设计（v5 · 经评审修正；§17 为 v7 目标态，已按 10-27 外评审修订）

> 五层：L1 入口 → L2 Agent 编排 → L3 能力（MCP / RAG / 模型网关）→ L4 数据 → L5 基础设施。
> v5 依据 Codex 高推理评审修正三处硬伤：StateGraph 并无 checkpoint/interrupt、文搜图与工程 API 版本冲突、白名单不可信。
> §17 的 v7 目标态经 2026-10-27 第二轮外评审修订（§14.1），总体判定「有条件可落地」。
> v1 范围仍是：**全面 Kit 化、复习移出、MCP 只留接口、卡片只读**。

---

## 0. v1 范围锁定

### 做

| 项 | 说明 |
|---|---|
| 小艺意图入口 | Intents Kit + Want；应用内 Want 作为验收基准 |
| 批量选图 | PhotoViewPicker 多选，上限 20 |
| OCR | Core Vision Kit 通用文字识别，全量走 Kit |
| 文搜图 | textSearchImage 建索引 + 语义检索（设备已支持 API 26） |
| 生成 | DeepSeek 结构化笔记 |
| 确认落库 | 预览确认 + 事务 + 幂等键 |
| 展示 | 卡片 + 笔记页 |
| MCP | **只留接口**，不接任何服务 |

### 不做（v2 及以后）

复习与间隔重复、MCP 实际接入（math-solver / ocr-cloud）、自建 HNSW + BM25 + rerank、Live View 实况窗、MindSpore 端侧模型、受限权限（全库扫描）。

---

## 1. 分层总览

```
L1  入口层        小艺语音 · 卡片 · 应用内入口
        ↓
L2  Agent 编排层  Planner · ReAct · Memory · Guardrails · Tracer
        ↓
L3  能力层        MCP 工具 · RAG · 模型网关
        ↓
L4  数据层        RDB · 向量/知识库 · 关键词索引 · 文件
        ↓
L5  基础设施       端侧 / 云 · 权限 · 观测
```

一条规矩：**上层只调下层接口，不跨层。**

---

## 2. L1 入口层

| 组件 | 职责 |
|---|---|
| 小艺语音 | 接收一句话，识别意图（Intents Kit） |
| 卡片 | 结果回显（Form Kit），读投影不算数 |
| 应用内入口 | 调试与兜底 |

入口层不做业务判断，只把原始请求交下去。

---

## 3. L2 Agent 编排层

| 功能块 | 职责 | 关键设计 |
|---|---|---|
| Plan 节点（图内） | 拆任务步骤 | **必须是图的首节点**，不允许外部调用绕过 |
| 图执行器（自建 StateGraph） | 现状仅 88 行：node / route / halt，**无 checkpoint、无 interrupt、无 resume** | 续跑与确认门禁须自建批次状态机 |
| Memory | 会话 / 任务 / 长期记忆 | 按 Agent 隔离，可删除 |
| Guardrails | 确认门禁、敏感拦截 | 写库前必须人工确认 |
| Tracer | 每步输入输出、耗时、token | 支撑调试与指标 |

### 3.0 用 LangGraph 的工作流模型，执行器自建

L2 的编排**语义**来自 LangGraph，运行时是自己写的 ArkTS 执行器（`common/workflow/StateGraph`，约 88 行串行执行）。ADR-0008 采纳的是 LangGraph 的工作流模型与词汇，明确拒绝的是 **runtime 依赖**（Python sidecar / langgraphjs）——ArkTS strict 跑不了 Node，HAP 也塞不进一个进程外服务。所以「图引擎」在这里指 `StateGraph` 这个类，不是鸿蒙系统能力，也不是 npm 包。

| LangGraph 概念 | 在这个工程里的对应 | 现状 |
|---|---|---|
| `StateGraph` | `common/workflow/StateGraph`（`addNode` / `addEdge` / `addConditionalEdge` / `run`） | 已有；串行执行，`run` 每次重置 `nodeRuns`，默认上限 128 |
| `State` | `AgentState`，逐字段 copy（ArkTS 禁止 spread） | 已有 |
| Node | `CaptureNode = (state) => Promise<state>` | 已有 |
| Conditional Edge | 分类失败 / 校验失败的错误分支 | 已有 |
| `ToolNode` | `ToolLoop`（同一内核，`maxSteps` 上限） | 已有 |
| `Checkpointer` | **不引入**（ADR-0008 明确 non-goal）。恢复靠业务级 checkpoint：`NoteGenerationRepository` 的 run / checkpoint / `commitKey` | 业务级已有，runtime 级不做 |
| `interrupt()` | **不引入**。人工确认是图外动作：预览 → 确认 → 提交，确认结果作为下一次 run 的输入 | 图外已有 |

代价要说清楚：断点续跑和人工确认**要自己造**，不是 LangGraph 原生送的。v1 的做法是业务级 checkpoint + 图外确认；只有当真的需要「进程重启后从第 7 张图继续」时，才值得为 runtime checkpoint 单开 ADR。

### 3.0.1 Plan 为什么必须在图里，不能放在图外

你担心的“这一步会被跳过”是真问题，而且有三条跳过路径：

| 跳过方式 | 后果 |
|---|---|
| Plan 放在图外，调用方直接 `run(steps)` | plan 从未执行，日志里也没有这一步 |
| 条件边从 route 直接连到 ocr | 正常路径绕开 plan，只有异常才走 |
| v1 把三步写死在代码里 | plan 节点空转，v2 想换动态规划要改结构 |

三条约束把它堵死：

1. **`route → plan` 是唯一入口**，图里没有任何一条边能直接到 `ocr`
2. **plan 必须产出非空 steps 和 plan_id**，否则整张图终止，不许“空计划继续”
3. **v1 的 plan 可以是静态计划**（固定三步），但它必须被执行、写 checkpoint、留记录——这样 v2 换成 LLM 规划时，图的形状不变

图的形状：

```
route → plan（批次级，只跑一次）
      → gallery_pick → fanout per image
            └ 子图：ocr → generate → checkpoint
      → verify →（图外确认）→ write → end
```

要点：**规划是批次级的，不是每张图规划一次**；单张图跑的是 plan 之后的子图。

### 3.1 场景扩展：不要为每个功能改内核

这是接入复习之前必须先定的一件事。**Agent 内核只做一件事：按场景选 Workflow，按 Workflow 授权工具。**

```
请求
 → 场景识别（batch_note / review / chat）
 → 选 Workflow
 → Workflow 声明：用哪些工具、哪些要确认、失败怎么办
 → ReAct 在授权范围内循环
```

| 场景 | Workflow | 允许的工具域 |
|---|---|---|
| 批量生成笔记 | BatchNoteWorkflow | gallery.* / ocr.* / note.write / llm.* |
| 复习 | ReviewWorkflow | note.read / review.* / llm.* |
| 对话问答 | ChatWorkflow | rag.* / note.read / llm.* |

**新增复习 = 新增一个 Workflow + 一组工具，内核零改动。** 如果做不到这一点，说明内核把场景写死了，两周内一定会返工。

### 3.2 工具注册按域划分

| 域 | 工具 | 读写 |
|---|---|---|
| gallery | pick / listRecent | 读 |
| ocr | recognize / recognizeFormula | 读 |
| note | read / search / write / update | 读 + 写 |
| review | due / plan / grade / record | 读 + 写 |
| rag | addDocument / retrieve / answer | 读 + 写 |
| llm | complete / stream / json | — |

写类工具一律挂 Guardrails，不经确认不能落库。

### 3.3 数据只能通过端口访问

Agent **不许直接碰 RDB**，否则复习、搜索、导出每加一个场景都要改一遍 SQL。定义三个读端口：

| 端口 | 方法 | 给谁用 |
|---|---|---|
| NoteReadPort | `list(filter)` / `get(id)` / `search(query)` | 复习、对话、导出 |
| ReviewPort | `due(now)` / `mastery(noteId)` / `record(...)` | 复习 |
| KnowledgePort | `units(topic)` / `related(id)` | 知识星系、RAG |

写操作走 `NoteWritePort` / `ReviewWritePort`，必须经确认门禁。

---

## 4. L3 能力层

### 4.1 MCP 清单（具体接哪些）

| MCP 工具 | 干什么 | 替代不了的部分 | v1 |
|---|---|---|---|
| `ocr-cloud` | 公式转 LaTeX、版面还原 | Kit 只出纯文本 | 可选（低置信度时） |
| `rerank` | 检索结果精排 | 端侧 RAG 若用 Kit 自带，则不需要 | 视 RAG 方案 |
| `math-solver` | 符号计算、步骤校验 | 复习批改要判对错，LLM 不可靠 | v2 |
| `doc-parser` | PDF/Word 结构解析 | 端侧只有 OCR | v2 |
| `web-search` | 联网补充资料 | — | 不做 |

原则：**MCP 只补 Kit 覆盖不到的能力，不用来搬图库、RDB 这种端侧数据。**

### 4.2 模型网关（端侧优先，回退必须标注）

**as-built（2026-10-24）**

```
ModelRouter                      入口：一次回答只能选一条路
 ├─ LocalChatProvider            系统端侧对话模型 localChatModel（PC/2in1），isReady() 判定
 └─ ReplyService → LlmGuard → LlmClient   用户配置的云端模型（DeepSeek / Qwen / …）
```

| 场景 | 走哪条 | 气泡尾部 |
|---|---|---|
| 端侧就绪 | `LocalChatProvider.ask()` | 无标记，`source=on_device` |
| 端侧未就绪 / 推理失败，但配了云端 | `ReplyService.complete()` | `（已降级：<原因>）` |
| 两条都不可用 | 抛错 | 明确中文原因，不返回假内容 |

**流式与非流式同一套路由**：`ConversationReplyAdapter.complete()` 与 `.stream()` 都先问路由；流式在端侧走 `askStream` 增量，否则走云端 SSE。两条路径都打 `[StreamRoute] source=on_device|remote`，真机一眼可查。

**思考模式按模型能力下发（不是一刀切）**

| 能力 | 判定 | 关闭 | 开启 | 首字节看门狗 |
|---|---|---|---|---|
| `toggle` | DeepSeek / Qwen | `thinking:{type:'disabled'}` / `enable_thinking:false` | `enabled` + `reasoning_effort` | 关 30s / 开 60s |
| `always_on` | o1/o3/reasoner 类 | 不存在「关」 | 强制开启，`effort` 默认 `medium` | 60s |
| `unsupported` | 未知模型 | 一个思考字段都不写 | 同左 | 30s |

聊天默认走 `toggle` 的关闭档：真机首字 741–1357 ms；开着思考时首字 8–30 s，会被看门狗误判成断流。

**边界（踩过的坑）**：`LocalChatProvider` 只允许放在 `entry`，**不能经 `common` barrel 导出**。`@kit.DataAugmentationKit` 限 PC/2in1 + 企业资质，一旦被带进 `AgentExtAbility` 所在的扩展进程，会让网络栈初始化失败（`proxy SendRequest failed 201` / `http handover manager init fail`），A2A 的 LLM 调用永不返回。

**为什么端侧是「能力位」不是「开关位」**：真正落地需要模型选型、量化、tokenizer、采样策略四件事，属独立迭代；做成可插拔接口后，默认路径行为明确（降级可见），主链路不被阻塞。

### 4.3 RAG

见第 5 节。

### 4.4 鸿蒙 Kit 清单（原子能力）

| Kit | 能力 | 用途 | 版本/限制 | v1 |
|---|---|---|---|---|
| **Core Vision Kit** | 通用文字识别 | 题目文字 OCR | 端侧、免网络 | ✅ |
| Core Vision Kit | 文搜图 `textSearchImage` | 按描述找图 | **API 26**；真机支持，工程需同步升级 compileSdk | ✅ v1 |
| Core Vision Kit | 主体分割 / 多目标识别 | 裁题、定位 | 精度一般 | 可选 |
| **Vision Kit** | DocumentScanner | 拍纸质题自动裁边 | 是 UI 组件 | 可选 |
| Vision Kit | AI 识图 | 图像理解 | — | 不用 |
| **Data Augmentation Kit** | 知识库 / 知识检索 / RAG（`ChatLLM` 需应用自己实现，不含模型） | 端侧 RAG 框架 | 无内置生成模型，见 4.2 | ⚠️ |
| **ArkData RelationalStore** | RDB | 笔记、复习计划 | 已有 13 张表 | ✅ |
| **Form Kit** | 卡片 | 结果回显 | 已有 | ✅ |
| **Intents Kit** | 意图声明与调用 | 小艺入口 | 需审核 | ✅ |
| **Agent Framework Kit** | 拉起智能体 / A2A | 入口 | 仅手机平板 | 可选 |
| **Background Tasks Kit** | reminderAgentManager | 复习提醒 | 代理提醒 → 通知 | 复习用 |
| **Notification Kit** | 通知 | 提醒落地 | — | 复习用 |
| **Live View Kit** | 实况窗 | 批量进度 3/20 | API 11+ | 可选 |
| MindSpore Lite Kit | 端侧推理 `.ms` | 自研模型 | 工程量大 | ❌ |
| Core Speech Kit | 语音识别 | 应用内语音输入 | 小艺已覆盖 | 可选 |

**结论**：v1 真正要接的是四个——Core Vision Kit（OCR）、Data Augmentation Kit（RAG）、RelationalStore、Intents Kit。其余按需要再加，别一次全上。

---

## 5. RAG 子架构

### 5.1 写入链路

```
原始材料（图片 / 文档 / 笔记）
  → 解析        OCR 文本、版面、公式
  → 清洗        去噪、统一符号
  → 分块        按题目边界，300–500 字，重叠 10%
  → 元数据      来源 ID、页码、题号、学科、时间
  → 向量化      embedding
  → 建索引      向量 + 关键词
  → 版本        内容指纹去重，增量更新
```

### 5.2 检索链路

```
query
  → 查询理解    同义、术语归一、学科识别
  → 多路召回    向量 top20 ＋ BM25 top20 ＋ 元数据过滤
  → 融合        RRF
  → 重排        cross-encoder，取 top 5
  → 阈值过滤    低于分数线丢弃
  → 上下文组装  按 token 预算裁剪，保留来源编号
  → 生成        带引用的回答
```

三条原则：召回宽、重排严；引用可回原文；没有重排的 RAG 等于关键词搜索。

### 5.3 治理

去重（内容指纹）、权限（按用户/空间隔离）、失效（原图删除同步删索引）、反馈（采纳率回流调阈值）。

### 5.4 端侧怎么落地：先 Kit，后自建

**Data Augmentation Kit 本身就提供知识库、知识检索、RAG 和端侧问答模型**，流程里包含问题分解、查询改写、知识检索、检索生成。所以：

| 方案 | 适用 | 代价 |
|---|---|---|
| **A. Data Augmentation Kit** | 标准知识库问答，想快 | 分块与元数据过滤的可控性受 Kit 限制 |
| B. 自建 HNSW + BM25 + rerank | 需要自定义分块、强元数据过滤、可解释排序 | 工作量大，两周做不完 |

**v1 选 A**：把笔记写进 Kit 的知识库，检索走它的接口。自建方案留作 v2，等出现“元数据过滤不够用”的真实需求再换。架构图里 RAG 层画成 `RAG 接口 → Data Augmentation Kit`，自建作为虚线备选。

---

## 6. L4 数据层

| 存储 | 存什么 | 归属 |
|---|---|---|
| RDB · `knowledge_unit` | **笔记主体**：标题、正文、标签、学科、章节、SM-2 复习字段 | Agent 写，App 读 |
| RDB · `kg_edge` | 关系边：同知识点 / 相似 / 前后置 | Agent 写，App 读 |
| RDB · `study_plan` | 复习计划条目（到期、完成状态） | App 写，Agent 读 |
| RDB · `note_generation_run` / `_checkpoint` | 批次与断点 | Agent 写 |
| RAG · `rag_chunk` / `rag_embedding` | 笔记文本与向量 | Agent 写，检索读 |
| 文件 | 原图、附件 | 应用沙箱，App 只读 |

**没有 `note` 表**：笔记就是 `knowledge_unit`。也没有 `note_link` 与 `review_item`——关系边是 `kg_edge`，复习字段内嵌在 `knowledge_unit` 里（`next_review_at`、`interval_days`、`ease_factor`、`repetitions`）。

**读写分离**：Agent 是唯一写入方，App 只读；用户动作（改笔记、标记已复习）是 App 唯一的写入口。

---

## 7. L5 基础设施

- 运行环境：端侧应用进程 + 小艺开放平台（云端编排）
- 权限：图库 Picker（零权限），受限权限不进 v1
- 观测：trace、token、时延、失败分类

---

## 8. 复习场景（v2，不在本次验收）

### 8.1 链路

```
小艺「今天该复习什么」
  → ReviewWorkflow
  → ReviewPort.due(now)          读 RDB：到期条目
  → 组题（note.read + llm）
  → 用户作答
  → review.grade（v1 用 LLM，v2 换 math-solver）
  → ReviewPort.record(掌握度)
  → 更新下次到期时间
  → reminderAgentManager 设定提醒
```

### 8.2 数据要补什么

| 表/字段 | 说明 |
|---|---|
| `review_item` | note_id、下次到期、间隔、难度、连续正确次数 |
| `review_log` | 每次作答：时间、对错、耗时、评分 |
| `mastery` | 按知识点聚合的掌握度（0–1） |

RDB 不用大改，**加两张表 + 一个聚合字段**即可。关键是读接口先定好，不然复习接进来会到处写 SQL。

### 8.3 调度算法

v1 用 SM-2（间隔 × 难度因子），规则简单、可解释；v2 再考虑 FSRS。算法放在 `review.plan` 工具里，不写进 UI。

---

## 9. 与现状的差距

口径：提交 `028975e` 的真实代码，不写目标态。

| 层 | 已有 | 缺 |
|---|---|---|
| L1 | 小艺 A2A 真机已通（P0 有回复与验收日志）；`AgentExtAbility` 35s 单一 deadline、0 重试、回执短路；7 个 action 声明 | A2A **不经过 Dispatcher**（直调 `ReplyService`），「小艺触发整理」是新增接线；skill 侧 7 个 action 仍只有声明 |
| L2 | `Dispatcher` 四分支 + `CaptureGraph` 五节点 + `ToolLoop`；`KnowledgeModel` 已是 102 行 facade | 没有端口层：`skill/SkillAbility` 自己 `DatabaseHelper.init()` 并建只读 ToolRegistry，`entry` 的 `NoteEvidenceService` 直连 RDB 与 `kg_edge`；没有 RunContext / EventSink；没有统一 Trace |
| L3 | Core Vision Kit OCR（`SERVER_FALLBACK_ENABLED=false`）、文搜图常驻 Worker、模型网关 catalog / resolver / discovery 多提供商 | MCP 只有 `OcrTool`，没有 schema 发现与权限；RAG 只有 `rag_embedding` 建表，没有检索实现 |
| L4 | RDB 13 张表（`knowledge_unit` / `kg_edge` / `study_plan` / 生成 run） | `review_item` / `review_log` 未建表；`similar` 边未生成（`embedding: []`）；`study_plan` 是待办，不是复习计划 |
| L5 | 分阶段日志（capture 五段耗时）、A2A 日志（requestId / taskId / attempts / 耗时） | 没有跨工作流统一 Trace：`runId` / `parentRunId` 串不起来，node / tool / approval / commit 事件不落盘 |

「小艺真机未通」「观测为零」这两个说法已过期，别再引用。

---

## 10. 图怎么画

### 10.1 主图：五条横带

| 层 | 框内节点 |
|---|---|
| L1 | 小艺开放平台（注册/审核）、小艺语音、卡片、应用内入口 |
| L2 | 场景路由、图执行器（自建 StateGraph）、Memory、Guardrails |
| L3 | **鸿蒙原生 Kit 能力（一个框：识别 / 文搜图 / 知识库·RAG）**、模型网关、MCP 接口 |
| L4 | RDB、知识库、文件 |
| L5 | 端侧/云、权限、观测 |

### 10.2 子图一：RAG 两条链路（写入 / 检索）

### 10.3 子图二：复习链路（due → 组题 → 作答 → 判分 → 记录 → 提醒）

---

## 11. 已定（v1）

| 项 | 结论 |
|---|---|
| 文搜图 | 纳入，设备支持 API 26 |
| 能力来源 | 全面 Kit 化，MCP 只留接口 |
| 复习 | 不做，留到 v2（第 8 节保留设计） |
| 进度展示 | 卡片够用，不用 Live View |
| 优先级 | 功能跑通与验收优先，性能与自建方案延后 |

### 验收标准（功能口径）

| # | 验收项 | 通过条件 |
|---|---|---|
| A1 | 入口 | Want 能拉起应用并解析参数（上限 20）；小艺真机入口作为加分项 |
| A2 | 选图 | Picker 多选 20 张，返回 URI 列表且去重 |
| A3 | OCR | 20 张全部走 Core Vision Kit，输出文本与置信度，失败进清单 |
| A4 | 生成 | 每条笔记含标题、题干、知识点、来源图片 ID |
| A5 | 确认 | 预览页默认全选、可逐条取消；确认后事务写库（确认态由批次状态机记录） |
| A6 | 幂等 | 同一张图重复确认，RDB 不产生重复记录（按 批次ID+图片指纹 去重） |
| A7 | 失败隔离 | 单张失败不影响整批；整批 0 成功才判失败 |
| A8 | 展示 | 卡片与笔记页可见新笔记，能回到来源图 |
| A9 | 文搜图 | 真机已支持；D1 先把 compileSdk 升到 26 并跑通 `import`，再验收「建索引 + 描述性 query 召回」 |
| A10 | 应用内续跑 | 进程存活时从批次中断处继续；跨会话（小艺对话回「继续」）留到 v2 |
| A11 | 可溯源 | 笔记能跳回来源图，三个字段完整；**区域高亮待 Core Vision 探针确认后决定** |

十一条全过，v1 算功能验收通过。

---

## 12. v1 增补：确认交互 + 可溯源笔记

### 12.1 确认交互放哪：卡片只读，不进图

元服务卡片是**结果展示**，不是控制面，不接图引擎。确认动作放在这三处之一：

| 位置 | 做法 | 优先级 |
|---|---|---|
| **小艺对话窗口** | 图在 `confirm` 前 `interrupt()`，用户在对话里回「继续 / 取消」 | 首选，最自然 |
| **应用内浮窗** | 复用现有 `AgentFloatWindow`，弹确认条 | 次选，调试友好 |
| **通知** | Notification Kit 带操作按钮 | 兜底，容易被忽略 |

卡片只负责显示「已生成 18 条，2 条失败」，点开进详情页，**不承担任何状态变更**。

这样还有个好处：卡片是元服务，进程和权限都独立，让它去改图状态反而多一层信任问题。

### 12.2 可溯源笔记

每条笔记必须能回到它的来源像素。

RDB 变更（`knowledge_unit` 表加三列，迁移版本 13 → 14）：

| 字段 | 类型 | 说明 |
|---|---|---|
| `source_image_id` | TEXT | 来源图片 ID（对应文件表） |
| `source_region` | TEXT | 区域坐标 `x,y,w,h`，可空 |
| `ocr_confidence` | REAL | 识别置信度 0–1，可空 |

三条规则：

1. **没有来源的笔记不允许创建**——手工新建的要标记 `source=manual`
2. **区域坐标可空**，但图片 ID 必填
3. **RAG 引用复用同一组字段**，保证“检索结果 → 原文位置”是一条路

### 12.3 为什么这两条值得占两周的时间

- 确认交互：把“系统级入口”从口号变成可演示的交互，且依赖 LangGraph 的 `interrupt()`，别人用普通流水线做不出来
- 可溯源：这是 AI 笔记和 AI 玩具的分界线。面试被问“AI 生成的笔记可信吗”，答案不是“我们提示词写得好”，而是“每条都能点回原图”

---

## 13. 安全边界：白名单 + 沙箱 + RDB 防护

卡片不碰图之后，安全模型要补上这三层。

### 13.1 白名单（谁能触发写）

| 方向 | 规则 |
|---|---|
| 入站 | 小艺意图只负责**触发与跳转**，不携带写权限；写操作只能由应用内 UI 发起 |
| 出站 | 工具不允许直接写库，必须经过 `confirm` 节点 |
| 配置 | 白名单只用于「允许哪些 action 唤起应用」，不用于授权写库 |

**`Want` 里的调用方信息不可信**：它由发起方构造，不能当身份凭证。所以不靠 bundleName 鉴权，改成：小艺唤起 → 应用内展示来源 → 用户确认 → 才允许写。

### 13.2 沙箱

- Picker 给的是临时授权 URI，**先复制进应用沙箱再处理**，不要长期持有相册访问
- 处理完删除原图副本，只留缩略图与指纹
- 不申请全库读取权限（受限权限那条已经排除）

### 13.3 RDB

| 项 | 做法 |
|---|---|
| 加密 | 建库时开启 RDB 加密，密钥由系统密钥库托管 |
| 访问 | 只允许通过 Port / DAO，禁止跨模块裸 SQL |
| 导出 | 必须用户显式操作，且导出前二次确认 |
| 日志 | 不落正文，只落内容 hash 与长度，避免日志泄题 |

### 13.4 卡片与元服务的边界

- 卡片**只读**，不持有写权限，也不进图引擎
- 卡片数据来自投影表（snapshot），不直接查业务表
- 卡片刷新由应用主动推送，不反向触发业务

---

## 14. 评审修正记录（v5，2026-10-23）

来源：Codex `gpt-6-astra` @ high。评审原文已随架构文档收敛一并删除，需要时从 git 历史取（`git show 028975e^:docs/architecture/codex-architecture-review-2026-10-23.md`）。

| # | 问题 | 证据 | 处理 |
|---|---|---|---|
| 1 | StateGraph 没有 checkpoint / interrupt / resume | `common/src/main/ets/workflow/StateGraph.ets` 仅 88 行，只有 node / route / halt | 续跑与确认门禁改由**批次状态机 + 草稿表**实现 |
| 2 | 文搜图要 API 26，工程是 API 24 | `build-profile.json5`：`targetSdkVersion 6.1.1(24)` | 真机支持，**D1 把 compileSdk 升到 26** 并跑通 `import`，A9 保留在 v1 |
| 3 | Want 里的调用方信息不可信 | 参数由发起方构造 | 小艺只触发与跳转，**应用内确认是唯一写入口** |
| 4 | 失败语义不清 | 事务覆盖不到文件、Kit 索引、卡片 | 批次 ID + 图片指纹；RDB 原子提交，索引与卡片是可重试副作用 |

保留的不同意见：

- **Plan 节点保留**（静态计划，不接 LLM）：成本约 50 行，保住图的形状，v2 换动态规划不用改结构
- **A10 不取消**，收窄为应用内续跑；跨会话续跑留 v2

### 14.1 v7 目标态外评审（2026-10-27）

来源：Codex `gpt-6-astra` @ max，只读代码，全文 `docs/architecture/review-v7-2026-10-27.md`。总体判定**有条件可落地**，本轮据此改了五处：

| # | 评审意见 | 处理 |
|---|---|---|
| 1 | §17.5 契约只有端口名与归属，缺 `commitKey` / 版本 / 幂等 / 取消语义 | 重写：先列六个必填项，再逐端口写「至少要定义」 |
| 2 | §17.6 迁移顺序依赖倒置：子图先于端口，卡片排在 publish 之后 | 重排：ADR → 契约与 adapter → 行为基线 → 内核 spike → 薄包装 → 逐条迁 → 调用方切换 → A2A |
| 3 | §3.0 把 LangGraph 写成运行时，与 ADR-0008 冲突 | 改为「LangGraph 工作流模型 + 自建 ArkTS 执行器」，Checkpointer / interrupt 标为不引入 |
| 4 | §9「小艺真机未通、观测为零」已过期 | 按 `028975e` 重写差距表，并补「A2A 不经过 Dispatcher」 |
| 5 | §16.1 / §16.4 把 `study_plan` 叫复习计划、说 `review_item` 已建表 | 更正为待办清单；`review_item` / `review_log` 未建表；相似边未生成 |

评审另指出：`CaptureGraph` 五节点已存在、`KnowledgeModel` 已是 102 行 facade，所以 v7 的第一项内核差距是「子图作为节点接入」，不是「还没有子图」。

---

## 15. 落地路径：最终要在小艺开放平台完成

小艺开放平台**不在运行时链路里**，它是注册、审核与分发面。代码写完不等于能用，最后必须走完这套：

| 步骤 | 做什么 | 卡点 |
|---|---|---|
| 1 | AGC 上架应用（Release 签名，包名与工程一致） | 意图注册要求关联已上架应用 |
| 2 | 小艺开放平台创建智能体：名称、描述、角色指令、关联应用包名 | 描述写不好会影响意图识别 |
| 3 | 意图注册：action 字符串与 `module.json5` **逐字一致** | 差一个字母 `onNewWant` 静默不触发 |
| 4 | 提交审核 | **3–5 个工作日**，必须 D1 就提 |
| 5 | 真机联调：Release 包装机 → 小艺唤起 → 校验参数与回传 | 模拟器不支持 |
| 6 | 上架与灰度：智能体可见范围、版本回滚 | — |

配套要求：

- **D1 必须提交审核**，否则 D12 想演示小艺入口时还在等审核
- 审核期间用应用内 Want 跑通全链路，验收基准不变
- 小艺入口的验收放在真机 Release 包上，Debug 包不算

### 15.1 对架构图的影响

L1 入口层旁边挂一个「小艺开放平台 · 注册/审核」的角标即可，不要把它画成运行时节点——它不参与任何一次请求，只决定这个入口能不能上线。

---

## 16. 应用侧读模型：知识视图

### 16.1 三个视图，三种读法

| 视图 | 读哪张表 | 关键设计 |
|---|---|---|
| 笔记列表与详情 | `knowledge_unit` | 分页；按时间、学科、章节过滤 |
| 知识星系 | `kg_edge` + `knowledge_unit` | 只读预计算的边，渲染时不计算 |
| 待办（当前叫「复习计划」） | `study_plan` | 标题、完成状态、优先级、关联笔记、due date；**是待办清单，不是间隔复习计划** |
| 复习记录 | 未建表 | `review_item` / `review_log` 都不存在，v2 接 SM-2 时再建 |

### 16.2 关系边怎么产生

| 边类型 | 产生方式 | 现状 |
|---|---|---|
| 同知识点 | 同章节最近 20 条，增量补边（`KnowledgeUnitChapterEdgeEffect`） | **已实现**：`relation_type=same_unit` |
| 相似 | 向量余弦超过阈值（如 0.82） | **未实现**：`embedding: []`，字段在但恒空；`rag_embedding` 只有建表，没有检索 |
| 前后置 | 章节顺序推导，或人工标注 | v2 |

### 16.3 两条硬规则

1. **边落表，渲染不算。** 20 条笔记实时算没问题，2000 条每次进星系都重算会卡死。
2. **新增只做增量。** 新笔记只和同知识点内最近 N 条比，不做全库两两比较。

### 16.4 v1 的取舍

- 星系只出**一类**边：同知识点。相似边未生成（`embedding: []`），前后置留 v2。
- `review_item` / `review_log` **未建表**，v1 不接 SM-2；`study_plan` 是待办。
- 写入口不是「只有用户动作」：手工编辑与 AI 写入都走 `KnowledgeUnitWriteService`，AI 写入还会触发 `KnowledgeUnitPostCommitEffects` 的卡片刷新。口径应按 **数据 owner + 谁发起写 + 读投影** 三个维度描述，而不是「App 只读」。

---

## 17. 目标态（v7）：产品分支的模块与流程

> 本节由 `docs/architecture/agent-application-architecture-design-2026-10-20.md` 收敛而来（原文已删除，历史见 git）。
> 它描述**目标态**，与 §9「与现状的差距」配对看：前者说要去哪，后者说现在在哪。

### 17.1 分层与模块职责

| 层 | Module | 组件 |
|---|---|---|
| 接入 | `entry` / `skill` / `cardservice` | APP、小艺、卡片 |
| 主 Agent | `agents` | `Dispatcher` 主图（preflight / route / HITL / publish） |
| 专业 Agent | `agents` | `NoteAgent`、`ReviewAgent`、`MathVideoAgent`（子图） |
| 框架内核 | `common` | `AgentRuntime`、`StateGraph`、`ToolLoop`、`RunContext`、`EventSink`、`State/Reducer`、`Checkpoint`、`Trace` |
| 能力 | `common` | MCP Host、RAG Layer、Model Gateway、Data Access |
| 存储 / 消费 | `entry` / `common` / `cardservice` | App Store（notes / plans / vectors）、Card Snapshot 投影、APP 展示、卡片 |

- **entry**：页面 / 浮窗 / ViewModel / 平台适配（Reminder、BackgroundTask、FormCard、权限、Picker）；App Store 的笔记、计划、视频产物；组合根（RDB、DAO / Port、Dispatcher 装配）。不写 prompt、不跑 Agent 循环、不直接碰 MCP/RAG。
- **agents**：`Dispatcher` 持主图与顶层状态，负责路由、子图调用、HITL、汇总；子 Agent 各管一段（Note：`classify → structure → verify`；Review：`plan → ask → grade`；Video：`outline → script → render`）。不直接写 RDB、不直接发 HTTP/LLM。
- **common**：内核 + 能力。`AgentRuntime` 执行图、管取消与事件；`StateGraph` 提供 Node/Edge/conditional edge/`run(maxNodeRuns)`；`ToolLoop` 是 ReAct ToolNode（`maxSteps=4`）；`MCP Host` 管 Tools/OCR/Query 的 schema、发现、执行与权限；`RAG Layer` 管 ingest → retrieve → citation；`Model Gateway` 即 `LlmClient`/`LlmGuard`。
- **skill**：Want 解析、Intent Router、参数校验、调 `Dispatcher`、呈现结果、深链回 APP 确认；不写业务规则。
- **cardservice**：只读 `CardSnapshotStore`，不调 Agent、不查库。

**数据归属（10-27 评审补充）**：RDB schema 与平台实现（RDB / Preferences / 文件）归 `entry`；端口接口与 DTO 归 `common`；「App Store」不是独立模块，而是笔记 / 计划 / 视频三个领域的持久层——写入只经端口，且必须带审批结果与 `commitKey`。`agents` 与 `skill` 都不直接触碰 RDB。

### 17.2 Dispatcher 主图与子图

```text
preflight → route → invoke → verify → HITL → publish
```

- `preflight` 校验 payload / source / 预算 / 权限；`route` 是条件边；`invoke` 同步调子图拿 artifact；`verify` 做 schema / truth / 业务约束；`HITL` 走预览确认；`publish` 写 App Store。
- 与现状的关系：现在是 `Dispatcher.dispatch` 的四条固定分支（preparedCandidate / regenerate / generation / capture），目标是把模式判断下沉进 `NoteAgent` 子图，主图只保留「选哪个 Agent、何时确认、何时发布」。
- 粒度原则：一个 Agent = 一个目标 + 一份上下文 + 一个 run；分类/结构化/校验是 `NoteAgent` 的内部阶段，不再拆成三个 Agent。

| 子图 | 阶段 | 输出 | 可复用 | 现状 |
|---|---|---|---|---|
| NoteAgent | classify → structure → verify | NoteDraft / KnowledgeUnit | TypeClassifier、KnowledgeModel、CaptureGraph | **已存在**：`CaptureGraph` 五节点（ocr → classify → structure → truthcheck → persist），`Dispatcher` 持有 |
| ReviewAgent | plan → ask → grade | StudyPlan / ReviewSession | NoteReviewService（StudyPlan 数据新增） | 待建 |
| MathVideoAgent | outline → script → render | VideoArtifact / mp4 | 无（渲染走外部服务） | 待建 |

> 补充（2026-10-27 复核）：`KnowledgeModel` 已在 10-13/10-14 拆完——现在只有 102 行 facade，实际实现分别在
> `CaptureStructurer`（618 行）、`DraftComposer`（523）、`DeepDraftComposer`（361）、`IncrementalPatchComposer`、
> `TruthCheckService`（249）、`PromptBuilder`。ADR 0006 里「870 LOC 待拆」是当时的现状描述，票 #209–#214 的
> 拆分工作在代码里已经落地，剩下的是核对与关票，不是重写。

### 17.3 内核差距（按优先级）

1. **Subgraph 调用**：子图作为节点接入，而不是函数硬调；现状 `CaptureGraph` 已是 `StateGraph` 实例，但由 `Dispatcher` 直接 `new` 并喂节点，还不是「子图作为节点」；
2. **RunContext**：runId / parentRunId / cancel / budget（当前只有 `CancellationToken`）；
3. **EventSink**：node / tool / token / approval 事件（当前只有 `progressSink` 与 #235 加的按节点耗时回调 `NodeTimingSink`）；
4. **State / Reducer**：typed channel 取代手写 `copyAgentState`；
5. **Checkpoint**：保持业务级（草稿 / 确认），要做 runtime checkpoint 需单独 ADR。

### 17.4 端到端信息流

```text
APP 输入 / 小艺 Want
  → Dispatcher（preflight / route）
  → NoteAgent（classify → structure）
  → 工具 / 模型 / 知识（MCP/OCR · Model · RAG）
  → Verify → HITL → App Store（notes / plans / vectors）
  → 卡片（读投影） / APP 展示
```

上图画的是目标态。现状有两处必须写清楚，否则会误判工作量：

- **小艺这条不在这张图里**：`AgentExtAbility` 收到 A2A 请求后直调 `ReplyService`，回执命中则直接读 `receipts/last-capture.json` 返回，两条路径都**不经过 `Dispatcher`**。要让「小艺触发整理」走主图，是新增接线，得先定 request/result 映射。
- **确认在图外**：预览 → 用户确认 → 提交是三次独立调用，不是 `interrupt()`；这正是 §3.0 说的「业务级 checkpoint + 图外确认」。

分支：Review 走 `plan → ask → grade → StudyPlan → App Store`；Video 走 `outline → script → render → mp4 → App Store`。注意 `study_plan` 当前是待办不是复习计划，ReviewAgent 的领域模型要先定（见 §16.1）。

产物链：图片 → OCR text/formula → `ClassificationResult` → `KnowledgeUnit`/NoteDraft → verified draft → approval → note/plan/video 行 → embeddings → Card Snapshot。

### 17.5 跨模块契约

外评审（`docs/architecture/review-v7-2026-10-27.md`）判定：下面第一版只有端口名和归属，**不足以解耦**。所以每个写契约先回答六个问题，缺一条就不算契约：

| 必填项 | 为什么 |
|---|---|
| `operationId` / `commitKey` | 重放时同一操作只生效一次（`NoteGenerationRepository` 已有 `commitKey` 先例） |
| `expectedVersion` / CAS | 双写与陈旧写入的唯一防线（`NoteDao` 已有版本冲突先例） |
| 结构化错误码 + 可重试标记 | A2A 回执、HITL、取消都要按错误类型分流，不能压成一个 `Error` |
| 幂等重放结果 | 重放要返回「首次结果」，不是「已存在」 |
| 取消语义（未提交 / 已提交） | 节点前后的 `CancellationToken` 检查撤不掉已经落库的写 |
| 版本与时间戳 | 卡片投影、embedding、边都是 post-commit effect，必须能判断落后于哪个提交 |

| 契约 | 归属 | 现状 | 至少要定义 |
|---|---|---|---|
| `Dispatcher.dispatch` | agents | 四分支已存在，返回扁平结果 | `NoteCommand`（capture / generation / regenerate / preparedCandidate / analysisOnly）+ discriminated `NoteOutcome`（needsInput / readyPreview / committed / failed(code, retryable) / cancelled） |
| `NoteReadPort` / `NoteWritePort` | 接口 common，实现 entry | 直连 DAO，无端口 | `commitKey`、`expectedVersion`、`approvedCheckpointHash`（防 Agent 绕过 HITL）、幂等重放、`committed/cancelled` 判定 |
| `StudyPlanReadPort` / `StudyPlanWritePort` | 同上 | `StudyPlanDao` 裸 CRUD | **先定领域**：待办 vs 间隔复习；再定评分 / 掌握度 / 复习记录 |
| `ArtifactStorePort` | 同上 | 无 | `artifactId`、媒体类型、URI、校验和、保留与删除、部分失败的清理 |
| `CardSnapshotStore` | common | Preferences 静态读写，无 schema version | projection schema version、`updatedAt`、原子替换、刷新失败可重试 |
| `RunStore` | common | 无（只有 `NoteGenerationRepository` 的 run 行） | `runId` / `parentRunId` / `eventId`、单调 `sequence`、status + version、checkpoint、恢复与取消合同 |

Token 事件只记数量与耗时，**不落正文**（沿用日志脱敏约束）。

依赖方向固定为 `entry / skill / cardservice → agents → common`；`common` 不反依赖业务 module，`cardservice` 不 import `entry`。注意 `scripts/process-boundary/check.mjs` 只查「进程可达的 Kit」，**不查模块依赖方向**——方向现在靠 review 守，后续应给 gate 加一条检查。

### 17.6 迁移顺序

外评审判定原顺序**依赖倒置**：步 3–4 迁子图、步 6 才定义端口，子图只能去依赖旧 DAO；卡片又排在 publish 之后，而卡片是 `NoteDao` 提交后的 post-commit effect。改成：

1. **ADR 先写**：修订 0008 只放开 Subgraph 一项（Checkpoint / HITL 保持业务级）；`NoteCommand` / `NoteOutcome` 单独一份 ADR——错误与终态语义一旦散进代码就收不回来。
2. **契约与 adapter 先落地**：六个 Port + entry 实现 + 契约测试（幂等重放、版本冲突、取消判定）。**在子图之前**。
3. **行为基线**：四条 dispatch 路径各录一份输入 / 输出 / 错误，作为「迁完没变」的唯一判据。
4. **内核 spike**：父子图共享 runId / deadline / cancel、累计 node 预算、domain error 透传；Worker 只传可序列化数据。3–5 天，不通过就停在这里。
5. **NoteAgent 薄包装**：只包现有节点与服务，TruthCheck 留在图边界；先迁 **capture 一条**。
6. **再迁** generation / regenerate / preparedCandidate，每条一个切片、同切片删旧实现。
7. **调用方切换**：skill 调 `Dispatcher`，cardservice 只读投影；「提交成功但卡片刷新失败」的重试语义在这之前定死。
8. **A2A**：不纳入本轮就保留独立契约与 smoke；要纳入，先定 request/result 映射和 35s deadline / 单帧快照 / 回执短路的验收，不能靠 skill Want 替代。

旧实现删除必须与新接线在**同一切片原子完成**，不允许新旧 runtime 并行或长期 feature flag。

### 17.7 尚未拍板

外评审对七项各给了表态，逐项记在下面（全文见 `docs/architecture/review-v7-2026-10-27.md`「附」）：

| 待拍板 | 外评审意见 | 现在的状态 |
|---|---|---|
| AgentRuntime 归属 | 通用执行机制留 common，业务生命周期与错误归 agents | 建议采纳 |
| 是否新增 `AgentFacade` | 只在能隐藏多用例 / 版本时新增，不做 `Dispatcher` 的空转发壳 | 建议暂不新增 |
| Subgraph 实现方式 | 共享 RunContext 的子图节点组合，**不要伪装成 Tool**（重试与输出语义不同） | 建议采纳 |
| Checkpoint 层级 | 保持业务级；runtime checkpoint 单开 ADR 并先定序列化兼容 | 采纳 |
| 笔记 / 计划的数据归属 | RDB 与平台实现归 entry，接口在 common，写操作经审批 + 幂等 Port | 建议采纳，需与「App Store 归谁」一并写进 §17.1 |
| Video 是否端侧只产脚本 | 暂缓 mp4 renderer，先定「只产脚本」与产物隐私 / 存储 / 取消 | 待产品拍板 |
| ReviewAgent 是否负责出题评分 | 不要直接展开 `study_plan`，先定待办 vs 间隔复习 | 待产品拍板 |
