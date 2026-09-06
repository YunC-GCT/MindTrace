# 鸿蒙 Agent 工具供给与 skill 调度调研 — 2026-09-06

> **调研问题**(复赛阶段提出): ① 增删查改(CRUD)类 agent 工具, 鸿蒙生态有没有现成 Kit/机制可用? ② LangGraph 等框架能否直接拿来改造使用(对照 [ADR-0008](../adr/0008-capturegraph-self-built-runtime.md))? ③ `skill/` 模块(小艺 skill 预留位, 见 [agent-tools inventory](../architecture/agent-tools-inventory-2026-09-06.md) F4 裁决)如何做合理的意图调度设计?
> **方法**: 3 个后台 research agent 对一手信源(developer.huawei.com 官方文档/API 参考/版本说明、langchain-ai 官方仓库与文档、npm registry、GitHub)逐条核实; 其中华为文档中心经官方 Markdown 端点抓取 30+ 页并核对全量 sitemap(40,754 条 URL)。**版本基线已核实: HarmonyOS 6.1.1 = API 24**(本项目 build-profile 的 target, [官方版本索引](https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/overview-allversion); 6.1.0=API 23, 6.0.0=API 20, 7.0=API 26)。
> **前置文档**: [agent-framework-comparison-2026-09-02](./agent-framework-comparison-2026-09-02.md) · [langgraph-migration-2026-09-02](./langgraph-migration-2026-09-02.md)(其 Python sidecar 建议已被 ADR-0008 否决) · [harmonyos-kits-survey-2026-09-05](./harmonyos-kits-survey-2026-09-05.md)。

## 0. 结论速览

| # | 问题 | 裁决 |
|---|------|------|
| 1 | CRUD 工具有没有现成 Kit? | **没有"把 RDB 暴露给 AI"的自动机制**。底座是自家 ArkData RDB(已是现状); 官方增量 = vectorStore(API 18+)、智慧化数据检索(API 20+, Phone 可用)、RDB 端云同步(API 23+)。"把能力给系统 AI 调用"的官方路径是 **Intents Kit(API 11+)+ 小艺开放平台 MCP 上架**, 不是数据 Kit |
| 2 | LangGraph 能否直接引入? | **维持 ADR-0008**: 1.4.14 主入口依赖 `node:async_hooks`, `/web` 入口避开了它但依赖 @langchain/core+zod 动态类型栈, ArkTS strict 无法集成, 全网零鸿蒙案例。但 **3 个设计应吸收**: checkpointer 5 方法接口、interrupt 异常+重放、Command/goto 条件路由 |
| 3 | 有没有系统级 LLM API? | **手机端 API 24 无**(且官方无"AI Kit"这个 Kit): 端侧 LLM 两条路径均不可用于本项目(localChatModel 仅 PC/2in1+企业; CANN LM Engine 仅 Kirin X90)。**现有 LlmClient 云端 OpenAI 兼容路线是手机端唯一可行路线** — 初赛设计被调研证实, 不需要推翻 |
| 4 | skill/ 怎么调度? | 意图声明的 7 个 action 中 6 个被拓扑卡住(DAO/编排都在 entry, HSP 不可依赖 HAP)。解法与 tools/ 工具层(F1)合流: **ToolRegistry 落在 common/agents, app 内 LLM 与 skill 意图共用同一工具面** |
| 5 | 初赛旧设计要不要改? | 核心设计全部站得住(自研图运行时/云端 LLM/自研 OCR); 要改的是 4 个具体点: LlmRequestBody 加 tools 字段、ToolRegistry 位置、ReminderFacade 实现选型、两处文档失实(api-version.md 版本漂移、kits-survey §2 AI Kit 表述) |

## 1. Q1 — CRUD 工具的鸿蒙 Kit 供给面

**结论**: ArkData 是"存储+同步+共享"底座, 但官方**没有**任何"把应用数据自动暴露给系统 AI 当工具调用"的机制; 系统级调用走 Intents Kit 与小艺开放平台 MCP 上架(见 §4)。

| 能力 | Kit/模块 | 最低版本 | Phone 可用? | 对 tools/ CRUD 工具层的意义 |
|---|---|---|---|---|
| 关系库 CRUD + FTS 全文检索(ICU 中文分词) | ArkData `relationalStore` | API 9/10+ | ✅ | 现状即底座; FTS 可做笔记关键词检索工具 |
| 向量数据库(floatvector + gsdiskann, L2/余弦) | ArkData `relationalStore` vectorStore | **API 18+** | ✅(运行时 `isVectorSupported()` 检测) | 替换 `knowledge_unit.embedding` 的 `"[]"` 占位(审计 #16 关联); 语义查重/相似题检索工具 |
| 智慧化数据检索(倒排+向量多路召回, RRF 融合, 直接检索应用自己的 RDB) | Data Augmentation Kit `retrieval` | **API 20+** | ✅(唯一支持 Phone 的该 Kit 能力) | 零训练把 SearchNote 意图升级为混合检索; 是 skill `SearchNote` 的最佳后端 |
| RDB 端云同步(华为云空间 Cloud Kit 托管) | ArkData `setDistributedTables(DISTRIBUTED_CLOUD)` + `cloudSync` | **API 23+** | ✅(仅中国大陆, AGC 开通云空间, 真机 ≥6.1.0) | "笔记多端一致"最低成本路径; 复赛加分项但依赖 AGC 配置与真机 |
| 跨设备直连同步(不经云) | ArkData 分布式表 / 分布式对象 | API 8/10+ | 需多设备组网 | 对本项目价值有限(演示成本高), 不推荐 |
| 端侧问答模型 `localChatModel`(Qwen25-7B) | Data Augmentation Kit | API 20+ | ❌ 仅 PC/2in1 + **仅企业开发者**; 且无 system prompt/JSON mode 控制参 | 不可用于本项目(手机+学生个人开发者) |
| 端侧 RAG(知识加工+RagSession, LLM 自带) | Data Augmentation Kit `rag` | API 20+ | ❌ 仅 PC/2in1 | `ChatLLM` 抽象类允许接自家云端 LLM — 赛后若做 PC/2in1 版可评估 |
| 代理提醒 `reminderAgentManager` | Background Tasks Kit | API 9+ | ✅(需 AGC 权益; API ≤25 单应用 30 个) | **ReminderFacade 实现选型首选**(ADR-0009 契约不变, 实现映射到它) |
| 日历日程 `calendarManager` | Calendar Kit | API 10+ | ✅(读写日历权限) | ReminderFacade 的补充/替代(复习计划写进系统日历, 可见性更好) |
| 实体抽取(固定类型清单) | Natural Language Kit | API 12+ | ✅ | 仅轻量预结构化; 无自定义分类, 不能替代题型分类 |

要点: "agent CRUD 工具层继续以自有 relationalStore 封装为唯一事实源" — 这与 ADR-0008 的自研哲学一致; Kit 的角色是**给工具层提供更强的后端能力**(vectorStore/FTS/混合检索/端云), 而不是替代工具层。

## 2. Q2 — LangGraph 直接引入评估(对照 ADR-0008)

**裁决: 维持 ADR-0008 的"采纳设计、拒绝运行时"**, 调研以 2026-09 事实复核了当年的三条拒绝理由:

1. **主入口确需 Node**(`@langchain/langgraph` 1.4.14: engines `node>=18`; 源码直接 `import { AsyncLocalStorage } from "node:async_hooks"`) — ADR 理由成立。来源: [npm registry](https://registry.npmjs.org/@langchain/langgraph/latest)、[langgraph-core/src/node.ts](https://github.com/langchain-ai/langgraphjs/blob/main/libs/langgraph-core/src/node.ts)。
2. **一处表述需修正**: 官方提供 [`@langchain/langgraph/web`](https://github.com/langchain-ai/langgraphjs/blob/main/examples/how-tos/use-in-web-environments.ipynb) 浏览器入口, **不** import async_hooks — ADR 里 "requires the Node runtime" 对主入口成立、对 `/web` 入口不准确。但 `/web` 入口的调用链仍依赖 `@langchain/core`+`zod` 的重度动态 JS(禁 any/动态属性访问的 ArkTS strict 无法集成), 且**全网无任何 ArkTS/HarmonyOS 运行案例**(GitHub `gh search` "langgraph arkts/harmonyos" 0 结果, 2026-09-06)。结论不变。
3. **条件路由演进佐证本项目词汇正确**: LangGraph 1.x 把条件路由收敛为节点返回 `Command({goto})` + `Send`(fan-out), 1.4.14 类型声明中已无 `addConditionalEdges` — 本项目 CaptureGraph 的 conditional edge 词汇与上游主流方向一致(设计采纳没白采纳)。

**值得"拿设计不拿代码"的三个模式**(全部零运行时依赖, 可在 ArkTS strict 手写, 属于 ADR-0008 预留的 "mechanical swap" 口子内):

| 模式 | LangGraph 事实 | 对 CaptureGraph 的启示 |
|---|---|---|
| **Checkpointer 接口** | `BaseCheckpointSaver` 仅 5 个抽象方法: `getTuple/list/put/putWrites/deleteThread`; 状态 JSON 可序列化, thread_id 索引([源码](https://github.com/langchain-ai/langgraphjs/blob/main/libs/checkpoint/src/base.ts)) | 未来若做"复习会话恢复/Order 断点续跑", 先在 `agents/graph/` 定义 5 方法接口, 用 RDB 实现 — 不必引入框架 |
| **interrupt 异常+重放** | `interrupt(payload)` 抛特殊异常 → 存 checkpoint 暂停 → resume 时**整个节点从头重放**(副作用需幂等)([HITL 文档](https://docs.langchain.com/oss/javascript/langgraph/human-in-the-loop)) | 本项目 TruthCheck 失败即短路(ADR-0008); 若未来要"用户确认后再 persist", 这是可抄的控制流模式 |
| **Command/goto 条件路由** | 条件边由节点返回值表达(纯数据), 而非注册时的回调分支 | CaptureGraph 的条件边实现可对齐此形状, 降低未来换运行时的迁移成本 |

**工具循环的参考实现**(给 F1 spec 用, 都不引包): ① [Vercel AI SDK v7 tool-calling 循环](https://ai-sdk.dev/docs/foundations/tools) — tool 定义(JSON Schema+execute)→ tool_calls → 执行 → 结果回喂 → `stopWhen: isStepCount(n)` 终止; ② [LangGraph prebuilt ToolNode](https://github.com/langchain-ai/langgraphjs/blob/main/libs/langgraph-core/src/prebuilt/tool_node.ts) 源码(含 retryPolicy/errorHandler); ③ [@standard-schema/spec](https://github.com/standard-schema/standard-schema)(1.1.0, 零依赖) 的接口模式可照写为工具参数校验; ④ MCP 规范([2026-07-28 版](https://modelcontextprotocol.io/specification/latest), JSON-RPC 2.0)语言无关 — 官方 TS SDK 不可移植, 按 spec 自实现最小 client 与项目 OcrTool 思路一致(呼应 [ADR-0010](../adr/0010-mcp-tools-semantics.md) 的开放注记)。

## 3. Q3 — 系统级 LLM 现实核查(重要纠正)

**结论: 手机端 API 24 没有任何系统级 LLM API, 官方也不存在名为 "AI Kit" 的 Kit**(文档中心全量 sitemap `ai-kit` 0 命中, `sdk/ai-kit` 404; AI 能力按 Kit 拆分)。由此:

- ✅ **初赛核心设计被证实**: `LlmClient` 云端 OpenAI 兼容路线是手机端唯一可行路线, 不存在"换成系统端侧模型"的选项。分类/结构化任务的系统提示词+JSON mode 控制(`response_format: json_object` + LlmGuard)只有自控 API 能做到。
- ⚠️ **纠正 [harmonyos-kits-survey-2026-09-05](./harmonyos-kits-survey-2026-09-05.md) §2**: 其声称的 `@kit.AIEngine`(textGenerator/embedding)与 `@hms.ai.llm` 两条端侧 LLM 接入路径**未获官方 API 文档支持**(疑为当时的推测或营销口径), "接 AIEngine 是复赛最强叙事点"的判断不能作为 spec 依据。真实可用的"端侧 AI"官方叙事是: CoreVisionKit(已用)+ 智慧化数据检索(API 20+, Phone)+ Natural Language Kit(API 12+)。
- 方向性: HarmonyOS 7(API 26)官方宣传将开放 "Agent、Skill 及端侧 AI 能力", 且 A2A 协议(`AgentExtensionAbility`)从 API 26 起 — 均在目标 API 之外, 记入 roadmap 不入 spec。

## 4. "被系统 AI 调用"的官方机制(小艺侧)

两层, 都不依赖数据 Kit:

1. **Intents Kit 意图框架(API 11+, 目标 API 24 可用)**: 用 `@InsightIntent` 装饰器/配置文件把应用功能与数据实体注册为系统意图, 小艺语音/智能推荐卡片触发, `InsightIntentExecutor` 在 app 内执行; `ExecuteMode` 支持 UIAbility 前台/后台([insightIntent API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-app-ability-insightintent), [意图开发指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-insight-intent2))。注意: 真机调试社区反馈需向华为申请白名单(存疑, 见 §8)。
2. **小艺开放平台 MCP 协议上架**: [官方指导](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/intents-kit-listing-mcp-protocol) — 注册 MCP URL + 鉴权 → 平台自动拉取工具清单 → 审核 → 发布到小艺对话/智能体/插件市场。即 **app 以 MCP Server 形式向小艺注册 tools** — 这为 ADR-0010 保留的 `mcp/` 语义提供了最终归宿: 未来把 ToolRegistry 包成 MCP Server 即可上架。
3. **app 内拉起智能体**(补充形态): Agent Framework Kit `FunctionComponent`(API 20+, Phone 可用, 需在小艺开放平台创建智能体并关联应用, 仅中国大陆+真机)可在 app 内一键呼出半屏智能体对话([指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/hmaf-function)) — 可作为演示的"小艺入口"低成本形态。

## 5. skill/ 调度设计

`skill/src/main/module.json5` 已声明 7 个 Intent action(这是全仓唯一权威定义, W1/W3 计划文档未展开语义), `skill/oh-package.json5` 自述 "MindTrace xiaoyi skill" 且依赖 `common`+`agents`。

### 5.1 拓扑约束(设计的第一性事实)

skill 是 HSP, **不可依赖 entry HAP**; 依赖声明只放行 `common`+`agents`。据此: LLM 层(LlmClient/LlmGuard/LlmConfig)、OcrConfig、DatabaseHelper(RDB 单例)、Dispatcher/CaptureGraph/OcrTool 全部可达; 而 **4 个 DAO 实现、AiService、AgentChatService、ImageUriResolver 全部在 entry — 不可达**。

### 5.2 意图 → 能力映射(现状 vs 缺口)

| Intent action | 语义(从命名推断, 待队员确认) | 现状可达路径 | 缺口 |
|---|---|---|---|
| `SetPreferences` | 设置偏好(endpoint/key/模式) | LlmConfig/OcrConfig(common)✅ | 无 — 唯一现成全通 |
| `SearchNote` | 搜笔记 | ❌ | DAO 在 entry; 需查询工具下沉 common/agents |
| `RecommendReview` | 今日复习推荐 | ❌ | 同上 + 推荐逻辑位置 |
| `KGRelated` / `KGCrossTime` | 知识图谱相关 / 学情统计 | ❌ | 同上(prerequisites/related 边、ReviewRecord 聚合) |
| `CaptureNote` | 拍题/文本 → 入库 | Dispatcher(agents)可达, 但 persist 需注入 NoteDaoInterface 实现 | DAO 实现在 entry → 写库链路断 |
| `VoiceReview` | 语音讲解问答 | ❌ | 对话编排(AgentChatService)在 entry |

### 5.3 调度器形状与核心洞察

```
小艺/系统入口 ──▶ SkillAbility (want.action 解析)
                    └─▶ IntentRouter (skill 内, 纯函数路由表)
                          ├─ 读类意图 ──▶ ToolRegistry.query* ──▶ ArkData(common DatabaseHelper)
                          ├─ 写类意图 ──▶ 显式参数 + 确认语义 ──▶ ToolRegistry / Dispatcher
                          └─ 对话类意图 ──▶ LlmClient(common, SSE) 轻量编排
```

**核心洞察 — 统一工具面**: F1 的 ToolRegistry 不应放在 entry, 应放 **common 或 agents**(skill 可达)。这样同一个工具面服务两个调用者: app 内 LLM(function-calling 执行循环)与小艺意图(IntentRouter)。`tools/` CRUD 工具层因此从"给某个 LLM 用的函数包"升级为 **agent 能力的唯一事实源**; 未来把它包成 MCP Server 即可走小艺开放平台上架(§4.2), 与 ADR-0010 保留 `mcp/` 语义的开放注记闭环。**落地顺序**: F1 spec(协议+registry 位置)→ skill IntentRouter 只接读类意图(SetPreferences 先行)→ DAO 下沉/查询工具进 registry → 写类意图最后开。

## 6. 初赛旧设计调整清单(按复赛优先级)

| 序 | 调整 | 类型 | 依据 |
|---|---|---|---|
| 1 | `LlmRequestBody`/`LlmCallRequest` 增加可选 `tools`/`tool_choice` 字段 + `LlmResponse` 解析 `tool_calls`(OpenAI 兼容, 向后兼容不动现有调用方) | 代码(小)+spec | F1 前置; OpenAI 兼容协议自带, 手机端无系统替代(§3) |
| 2 | ToolRegistry/Tool 接口落位 **common 或 agents**(不是 entry) | spec 决策 | §5.3 统一工具面; skill 拓扑约束 |
| 3 | ReminderFacade 实现选型: `reminderAgentManager`(API 9+, 需 AGC 权益, 单应用 30 个上限)为主, Calendar Kit(API 10+)为补充 | 代码(复赛冲刺序 2) | §1; ADR-0009 契约不变 |
| 4 | `SearchNote` 后端选型: 智慧化数据检索(API 20+)或 RDB FTS; `embedding` 占位用 vectorStore(API 18+)落地 | spec(赛后或复赛末) | §1; 审计 #16 关联 |
| 5 | **修正 [api-version.md](../agents/api-version.md)**: 其声称 compileSdk=9、"API 12+ 特性不能用", 与 build-profile 实际 `6.1.1(24)` 漂移 — 影响开发决策(如 lint 规则是否该放行 API 12+ 特性), 需先由团队确认 SDK 升级时间线再改文档 | 文档(P2) | 本地核查 2026-09-06 |
| 6 | **标注 kits-survey §2 的 AIEngine/@hms.ai.llm 表述失实风险**(见 §3), 防止被后续 spec 引用 | 文档 | 官方 sitemap 核查 |
| 7 | 端云同步(API 23+)与 FunctionComponent 拉起智能体(API 20+): 都依赖 AGC 配置+真机+中国大陆, 复赛前仅评估开通成本, 不进冲刺序 | 决策记录 | §1/§4 |

## 7. 建议下一步

1. **F1 spec(tools/ 工具调用协议)**按 §6.1-6.2 的裁决起草: 协议字段 + ToolRegistry 落位 common/agents + 工具循环参考形状(Vercel AI SDK/ToolNode 模式)。可走 to-spec 流程。
2. **skill/ 起草 spec**(小艺意图调度): 先向队员核实 7 个 action 的语义与设备/开发者账号约束(个人 vs 企业、AGC 权益、调试白名单), 再定 IntentRouter 分期(读类先行)。
3. 把 §6.5/6.6 两个文档修正项记入 issue tracker(triage 标签 `ready-for-human`, 因为需要团队确认 SDK 时间线)。
4. ADR-0008 增补一行修正说明(`/web` 入口表述)可在下次触碰该 ADR 时顺带完成, 不单独立项。

## 8. 未能核实 / 存疑(汇总, 详见各分项调研)

- Intents Kit 真机调试白名单流程: 仅第三方论坛提及(hagservice@huawei.com), 官方文档未复核到。
- `@langchain/langgraph/web` 产物能否在 ArkTS 引擎上以纯 JS 形式稳定运行: 无官方声明、无社区案例(ADR 修正表述仅指"不依赖 Node 内建 API", 不构成可行性)。
- localChatModel / RAG 的 AGC 权益申请入口与流程; CANN LM Engine 是否需白名单。
- Cloud Foundation Kit 云数据库模块起始 API 版本; ArkData "应用数据向量化" 指南正文机制。
- 小艺开放平台 5 种编排模式中 "OpenClaw" 的具体形态细节。
- `skill/module.json5` 7 个 action 的语义为命名推断, 需队员确认; `entity.system.intent` entity + 自定义 action 是否满足 Intents Kit 注册要求(装饰器式 vs skills 声明式)需在 DevEco 实测。

## 9. 调研产出口径

本报告由 3 个后台 research agent 的一手信源核实汇总(华为官方文档 30+ 页全文抓取 + sitemap 全量核对; LangGraph.js 官方仓库/npm/API 文档; MCP 官方规范), 分项报告全文保存在本会话记录; 本文件是入库的汇总结论版。只读调研, 除本文件外无其它仓库写入。
