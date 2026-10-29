# 第三方鸿蒙应用能否「调用小艺/智能体」并把文本回答取回自己的界面

> 调研日期：2026-10-24 · 目标工程：`D:/HMgent/MindTrace`（Stage 模型 / targetSdk 26）
> 本机环境：DevEco Studio 26.0.0.851 · SDK `HarmonyOS 26.0.0`（`sdk/default/sdk-pkg.json` → apiVersion 26 / 26.0.0.105）
> 扫描范围：`sdk/default/hms/ets/api`（195 个 d.ts/d.ets）+ `sdk/default/openharmony/ets/api`（561 个）= **756 个声明文件**
> 来源口径：本机 SDK 声明（文件:行号）> developer.huawei.com 官方文档/官方 API 参考 > 官方示例仓。二手博客只当线索，未采信。

---

## 0. 结论

**不能。** 截至 HarmonyOS 26.0.0（API 26）SDK 与本次可读的官方文档，**不存在任何「第三方应用 → 小艺/智能体」的文本请求 API**，也就没有「取回回答」「流式回调」这两件事。

官方在这一层的设计方向是**反的**：三种机制（意图 / Skill / 端侧 A2A）全部是「应用把能力外化给系统智能体（小艺）调用」，调用方是小艺，应用是服务端 / 被调方。

| # | 问题 | 结论 | 关键依据 |
|---|---|---|---|
| 1 | 全 SDK 有无「向智能体发文本并拿文本」的 API | **无**（除端侧问答模型 `localChatModel`，但它不是小艺，且仅 PC/2in1 + 企业开发者） | §1、`@hms.data.localChatModel.d.ts:118,142` |
| 2 | Agent Framework Kit 能否只取文本 / 流式 / 无 UI | **都不能**。组件即 UI；回调只有「对话框开/关」两个 void 事件 | §2、`@hms.ai.AgentFramework.d.ets:52,77,268` |
| 3 | insightIntent 能否调小艺并回传 | **不能**。意图调用发起者是 HarmonyOS，应用只能「返回结果」 | §3、官方《意图框架概述》+ `insightIntentProvider.d.ts:43,58` |
| 4 | 小艺开放平台是否给第三方应用暴露可调 endpoint | **未找到一手来源**。平台侧文档一律把第三方定位为服务端（被小艺调），云 A2A 规范页为 SPA，本次无法读正文 | §4 |
| 5 | 有无「唤起小艺并拿到回答」的官方 sample/codelab | **无**。官方只有「拉起」示例，没有「取回」示例 | §5 |

**一句话给决策**：小艺是「入口」，不是「模型 API」。要让聊天用上模型，现阶段只有自建云侧 LLM（工程现状 `LlmClient`）；想加小艺入口就用 `FunctionComponent`，但回答留在小艺的半屏对话框里，应用拿不到。

---

## 1. 全 SDK 扫描（Q1）

扫描关键词：`agent|assistant|intent|aiEngine|llm|generat|complet|nlu|insight|dialog|model`（文件名/内容），以及 `sendMessage|sendQuery|sendText|queryAgent|generateText|chatCompletion|streamText|onToken|onChunk|onStream`（内容）。

**第二组关键词有 13 个文件命中，逐个核过：12 个是无关模块的同名方法**（`@ohos.rpc`、`@ohos.inputMethod*`、`@ohos.telephony.sms`、`@hms.core.iap` 等）；**唯一相关的 `@hms.ai.A2A.d.ts` 命中全部来自注释**（`SendMessage` / `SendStreamingMessage` / `CancelTask` 是在描述协议方法名，见该文件 :423、:430），**没有对应的函数声明**。所以「向智能体发送文本」的 API 数量是 0。

命中的、与「AI 能力」相关的模块全集：

| 模块 | 能力 | 方向 | 应用能否拿到生成的文本 | 出处 |
|---|---|---|---|---|
| `@hms.ai.AgentFramework` | 拉起指定 `agentId` 的智能体（图标/按钮 + 系统半屏对话框） | 应用 → 小艺（仅 UI） | ❌ 只有 open/close 事件 | `@hms.ai.AgentFramework.d.ets:40,52,77,268` |
| `@hms.ai.A2A` | **只**能建 A2A 服务端 | 小艺 → 应用 | ❌ 只有 `createA2AServer` | `@hms.ai.A2A.d.ts:460,477,503,513` |
| `@hms.data.localChatModel` | 端侧问答模型：`init()` + `chat(info, config, cb)`，`isStream`/`isFinished` 支持流式 | 应用 → 系统端侧模型 | ✅ **能拿文本、能流式**，但见下方约束 | `@hms.data.localChatModel.d.ts:38,105,118,142` |
| `@hms.data.rag` | 知识库 RAG + 流式问答 | 应用 → 应用自选 LLM | ⚠️ 文本由**应用自己实现**的 `ChatLLM.streamChat` 产出 | `@hms.data.rag.d.ts:188,208,458,497` |
| `@ohos.data.intelligence` | 文本/图像 embedding、文本切分、查询支持的云模型 | 应用 → 向量化 | ❌ 无生成能力 | `@ohos.data.intelligence.d.ts:39,52,291,300` |
| `@ohos.ai.mindSporeLite` | 端侧推理运行时（自带 `.ms` 模型） | 应用 → 自有模型 | ❌ 不内置 LLM | 该文件整体 |
| `@hms.ai.insightIntent` | `shareIntent` / `deleteIntent` / `deleteEntity` / `getSid` | 应用 → 系统（共享数据） | ❌ 无问答 | `@hms.ai.insightIntent.d.ts:41,63,81,168` |
| `@ohos.app.ability.InsightIntentExecutor` | 系统调起意图时执行，`onExecute*` 返回 `ExecuteResult` | 系统 → 应用 | ❌（反向回传） | `InsightIntentExecutor.d.ts:76,99,125` |
| `@ohos.app.ability.insightIntentProvider` | `sendExecuteResult` / `sendIntentResult` | 应用 → 系统（回传结果） | ❌（反向回传） | `insightIntentProvider.d.ts:43,58` |
| `@ohos.app.agent.AgentExtensionAbility` + `AgentHostProxy` | 应用实现「端侧智能体」服务端，`onConnect/onData/onAuth`，用 `proxy.sendData()` 回 | 小艺 → 应用 | ❌（应用是被调方） | `AgentExtensionAbility.d.ts:63,74,85`；`AgentHostProxy.d.ts:40` |
| `@ohos.bundle.skillManager` | 查询 Skill 元数据（`getSkillInfo(s)ForSelf` 等） | 读元数据 | ❌ | `@ohos.bundle.skillManager.d.ts:102,118` |
| `@hms.ai.nlp.textProcessing` | 分词 / 实体抽取 | 分析 | ❌ 无生成 | `@hms.ai.nlp.textProcessing.d.ts:129,147` |

### 唯一「端侧 + 文本 + 流式」的那条路：`localChatModel`

- API：`init(): Promise<boolean>`（:118）、`chat(info: QuestionInfo, config: Config, callback: AsyncCallback<Answer>): Promise<void>`（:142）
- 流式：`Config.isStream`（:38）为 `true` 时增量回调；`Answer.isFinished`（:105）标记是否最后一片；`Answer.questionId` 用于并发对齐
- 约束（官方指南原文）：
  1. **当前端侧模型问答仅支持 PC/2in1 设备类型**
  2. **当前端侧模型问答仅对企业开发者提供申请能力**
  - 来源：<https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/dataaugmentation-localchatmodel>（"约束与限制"）
- 定位：官方《Data Augmentation Kit 简介》写明它是「uses HiAiMgr to connect to large language models (LLMs)」，即**系统端侧问答模型**，**不是小艺智能体**，也没有 system prompt / 工具调用 / 多轮会话对象
  - 来源：<https://developer.huawei.com/consumer/en/doc/harmonyos-guides/dataaugmentation-introduction>
- 对手机端 + 学生/个人开发者的项目：**不可用**（与 `docs/research/agent-toolkit-and-skill-dispatch-2026-09-06.md` §F1 结论一致）

> 附带说明：`@hms.data.rag` 的 `ChatLLM` 是 `abstract class`（:188），`streamChat` 是 `abstract`（:208）——即 **RAG 只提供检索与编排，LLM 必须应用自己接**。这也从侧面证明：系统没有把「某个可用的 LLM」借给应用。

---

## 2. Agent Framework Kit 的能力边界（Q2）

### 2.1 Kit 入口确实存在

`@kit.AgentFrameworkKit`（不是 `@hms.ai.AgentFrameworkKit`）：

- 文件：`sdk/default/hms/ets/kits/@kit.AgentFrameworkKit.d.ts:11-13`
- 它把两个 d.ts 的符号**原样再导出**，全部 19 个符号见 `hms/ets/build-tools/ets-loader/kit_configs/@kit.AgentFrameworkKit.json`：
  `AgentController, BaseOptions, FunctionController, FunctionOptions, ButtonType, FunctionComponent, Role, TaskState, Part, Message, Artifact, TaskStatus, Task, OnDataCallback, createA2AServer, ProxySender, Server, RequestContext, TaskArtifactParam`
- 也就是说：**Kit 里没有任何「客户端」符号**，19 个符号中与服务端相关的占 13 个。

### 2.2 完整 API 面（就是全部，没有隐藏成员）

| 类型 | 成员 | 说明 | 行号 |
|---|---|---|---|
| `AgentController` | `isAgentSupport(ctx, agentId): Promise<boolean>` | 只回 bool | :40 |
| | `on/off('agentDialogOpened', Callback<void>)` | 回调**无参** | :52 / :65 |
| | `on/off('agentDialogClosed', Callback<void>)` | 回调**无参** | :77 / :90 |
| `FunctionController` | `extends AgentController {}` | **空实现**，注释原文 "This API is reserved" | :102 |
| `FunctionComponent`（`@Component struct`） | `agentId: string`、`onError: ErrorCallback`、`options?: FunctionOptions`、`controller?: FunctionController`、`build()` | 唯一 4 个可配项 | :268-315 |
| `FunctionOptions` | `title/titleFontSize/iconSize/iconColors` + `queryText?: string` + `controlSize/buttonType/isShowShadow/backgroundColor/titleColors` | `queryText` = 预置**首句**提问 | :160-215 |

- 错误码只有 `1022400010`（参数）/`1022400014`（内部）；`isAgentSupport` 另有 `1022400011`（隐私协议未同意）/`1022400012`（未登录华为账号）/`1022400013`（网络）——见 `hmaf-function-component` API 参考。
- 来源（官方 API 参考，逐条与 d.ets 对应）：<https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/hmaf-function-component>

### 2.3 三个「有没有」逐条回答

| 问 | 答 | 依据 |
|---|---|---|
| 有没有「无 UI」用法 | **没有**。`FunctionComponent` 本身就是 UI（无 title → 图标；有 title → 按钮），点击后弹**系统半屏智能体对话框**，页面在系统侧 | 官方指南《通过Function组件拉起智能体》"场景介绍"：<https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/hmaf-function> |
| 有没有「只取文本」 | **没有**。控制器只有 opened/closed 两个 `Callback<void>`，无 message/result/answer 回调；`FunctionController` 是空类 | `AgentFramework.d.ets:102,52,77` |
| 有没有「流式回调」 | **没有**。整个 d.ets 无 token/chunk/stream 相关声明 | 同上（全文 316 行） |

**开发前置**（官方原文）：① 在小艺开放平台开发 Agent；② 关联应用；③ 终端登录华为账号且联网。`agentId` 在智能体配置页网址中获取，1~64 字符。
来源：同上 hmaf-function "开发前准备"。

> **官方文档自相矛盾处（重要）**：《Agent Framework Kit 简介》称 "在应用中智能体可以作为客户端或服务端与其它应用中的智能体进行交互。例如，当一个应用内的智能体需要调用小艺智能体完成某项任务时，可以通过 A2A 协议发起请求"（<https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/hmaf-introduction>）；但同期《通过AgentAbilityExtension实现智能体间A2A协议通信》只描述「构建 **Agent 服务端**」，API 只有 `createA2AServer`（26.0.0 新增）。
**以 API 为准**：客户端角色在 26.0.0 SDK 中**不存在**（全 SDK grep `createA2AClient|AgentClient|connectAgent|discoverAgent` → 0 命中，仅 webview 的 `UserAgentClientHints` 同名误报）。该简介句应视为文档超前/笔误。

---

## 3. `@hms.ai.insightIntent`（Q3）：方向是「系统调你」

官方《意图框架概述》把运行机制写死为两种，**发起者**是关键：

| 运行方式 | 发起者 | 定义 |
|---|---|---|
| 意图共享 | 应用/元服务 | 应用主动向 HarmonyOS 共享意图（供本地搜索、习惯学习） |
| **意图调用** | **HarmonyOS** | 系统主动调用应用/元服务的功能，应用执行并**返回执行结果** |

来源：<https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/insight-intent-overview>（"运行机制""意图的运行逻辑"）

应用侧能做的只有「被调 + 回传」：

- `InsightIntentExecutor.onExecuteInUIAbilityForegroundMode/…BackgroundMode/…UIExtensionAbility`，返回值 `insightIntent.ExecuteResult | Promise<ExecuteResult>`（`InsightIntentExecutor.d.ts:76,99,125`）
- 异步场景回传：`insightIntentProvider.sendExecuteResult(instanceId, result)`（:43）、`sendIntentResult(instanceId, result)`（:58）
- 应用侧模块 `@hms.ai.insightIntent` 只有 `shareIntent / deleteIntent / deleteEntity / getSid`（:41,63,81,168），**没有「发起一次问询并等回答」的方法**

**限制**（官方《Intents Kit 简介》"约束与限制"）：

- 设备：Phone、Tablet、PC/2in1
- 地区：仅中国境内（不含港澳台）
- 版本：HarmonyOS 5.0+
- 主体：**仅企业开发者**，个人开发者无法申请/注册意图能力
- 模拟器：不支持

来源：<https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/intents-introduction>

**结论**：insightIntent 是「让应用被小艺唤醒」，不是「让小艺替应用回答」。想用它把模型输出带回自己的聊天界面 —— 方向不成立。

---

## 4. 小艺开放平台：平台上的智能体对外暴露什么（Q4）

### 4.1 平台定位（官方最佳实践原文）

> 「小艺开放平台是小艺结合了**意图框架**与**华为 AI 大模型**能力面向开发者的能力开放平台……允许开发者构建智能体」
> 智能体分三种模式：**LLM 模式 / 工作流模式 / A2A 模式**；「A2A 模式是一种**三方智能体接入**小艺开放平台的高效编排方式……将成熟的第三方智能体**对接至**小艺开放平台，实现分发与调用」

来源：<https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-agent>

### 4.2 两条接入通道，第三方都是「服务端」

| 通道 | 谁发起 | 第三方角色 | 一手依据 |
|---|---|---|---|
| **端侧 A2A**（框架 API 24+；`createA2AServer` 自 26.0.0） | **小艺**（"智能助手作为 Agent **客户端**捕获用户意图"） | 应用 = Agent 服务端（`AgentExtensionAbility` + `createA2AServer`） | <https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/agent-overview>；`@hms.ai.A2A.d.ts:460` |
| **云 A2A** | 小艺（云侧） | 第三方云服务 = 服务端（**推断**：官方最佳实践称 A2A 模式是「三方智能体**接入**小艺开放平台」，但云 A2A 规范正文本次未能读取） | <https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-agent>；规范页见 §7.3 |
| **MCP 上架** | **小艺 / 小艺对话 / 插件市场** | 应用 = MCP Server：填 **MCP URL + Header/Query 鉴权**，平台自动拉取工具清单 → 审核 → 发布 | <https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/intents-kit-listing-mcp-protocol> |
| **意图 / Skill**（ArkAF） | 系统智能体 | 应用 = 能力提供方 | <https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkaf-overview> |

ArkAF 概述把这件事说得最直白：「提供意图框架、Skill 框架和端侧 A2A 框架三种能力开放机制，帮助开发者**将应用能力外化给系统智能体调用**」；能力执行阶段是「**系统智能体**通过 ArkAF 框架调用应用能力执行任务并返回结果，系统智能体将结果转化为自然语言反馈用户」。

### 4.3 「第三方应用直接调用平台智能体」的 endpoint

- **未找到一手来源。** 平台侧所有可读文档（接入方案、MCP 上架、最佳实践、ArkAF 概述）都只描述「小艺调第三方」，没有任何 `access_token / API Key → POST 智能体 → 收文本` 的接口文档、域名或鉴权说明。
- 鉴权在 A2A 里是**服务端侧**实现的：`Server.onAuth(data: string): string`（`@hms.ai.A2A.d.ts:513`）、`AgentExtensionAbility.onAuth(proxy, handshakeData)`（:85）、`AgentHostProxy.sendData()`（:40）——即「小艺来握手，应用校验并回包」，不是「应用拿 token 去调小艺」。
- **流式**：`agent_config.json` 的 `capabilities.streaming` 表示「**你的** Agent 是否支持 SSE 流式响应」给客户端（小艺）用（<https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/agent-extension-configuration>）。也就是说：流式能力是「你→小艺」方向，不是「小艺→你」。
- 平台智能体上架后是被**用户**在小艺里消费的（小艺对话/搜索/建议/智能体市场），不是被别的应用编程消费。

> 本次取证限制（如实记录）：`doc/service/*` 域下的小艺开放平台文档由 Angular SPA 渲染，web_extract 返回 422/空壳；用真实浏览器打开该域页面会导致渲染进程卡死（`Runtime.evaluate` 连续超时）；`r.jina.ai` 在本网络不可达。**因此云 A2A 规范正文未能逐字核对**，结论仅基于可读页面 + SDK。若需要「平台是否开放 HTTP 调用」的最终裁决，建议以工单形式向华为确认（这是唯一能补上的一手证据）。

---

## 5. 官方 sample / codelab（Q5）

| 类型 | 有没有 | 链接 |
|---|---|---|
| 「应用内拉起小艺智能体」示例 | **有**，但只是文档内嵌完整代码（`FunctionComponent` + `isAgentSupport` + `on/off`） | <https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/hmaf-function> "开发实例" |
| 「拉起后拿到回答」示例 | **无（未找到一手来源）** | — |
| 「端侧 A2A 服务端」示例 | **有**（`MyAgentExtensionAbility` 全量代码，含 `createA2AServer` / `updateStatus` / `addArtifact`） | <https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/hmaf-a2a-dev-guide> |
| 官方最佳实践（智能体搭建 + 上架） | **有**，讲平台侧怎么建/编排/上架，不含应用侧取回 | <https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-agent> |
| 非官方 demo（可作参考，非一手） | 有：`HarmonyOSAppDemo/AI/AgentFrameworkKit`（鸿蒙生态服务（深圳）有限公司组织仓）。我读了它的 `Index.ets`：只有三个 agentId + `FunctionComponent` + 两个 hilog 回调，**无任何取回逻辑** | <https://gitcode.com/harmony_ecosystem_services/HarmonyOSAppDemo/tree/main/AI/AgentFrameworkKit> |

**结论**：官方示例的边界与 SDK 完全一致 —— 只演示「拉起」，不演示（也无法演示）「取回」。

---

## 6. 对本项目的落地判断

1. **v1 的端 A2A 方向是对的，但别指望它借模型**：`AgentExtAbility` 是小艺的「工具提供方」，小艺把用户话语变成对你 Agent 的 A2A 请求；它不反向提供 LLM。
2. **聊天要模型 → 维持自建云侧 LLM（`LlmClient`）**。这是手机端唯一可行路线，与 2026-09-06 的调研结论一致，不需要推翻。
3. **想加「小艺入口」→ `FunctionComponent` + `queryText`**：成本最低（一个组件 + 一个 agentId），但只是入口，回答留在系统半屏对话框，聊天记录里拿不到。
4. **端侧省钱路线不可行**：`localChatModel` 限定 PC/2in1 + 企业开发者，本项目（手机 + 个人/学生主体）不满足。
5. **若产品硬要求「小艺的回答进我们的气泡」**：当前无官方 API。可考虑的替代是把「小艺」降级为**并列入口**（用户在小艺里问，我们不展示），或改用自家模型保证体验闭环。

---

## 7. 来源清单

### 7.1 本机 SDK（路径均相对 `C:/Program Files/Huawei/DevEco Studio/sdk/default/`）

| 文件 | 关键行 |
|---|---|
| `hms/ets/api/@hms.ai.AgentFramework.d.ets` | 40 `isAgentSupport`；52/65 `agentDialogOpened`；77/90 `agentDialogClosed`；102 `FunctionController`（空）；169 `queryText`；268 `FunctionComponent`；288 `onError` |
| `hms/ets/api/@hms.ai.A2A.d.ts` | 460 `createA2AServer`；477 `Server`；503 `onMessage`；513 `onAuth`；524 `updateStatus`；534 `addArtifact`；543 `RequestContext` |
| `hms/ets/kits/@kit.AgentFrameworkKit.d.ts` | 11-13 符号再导出 |
| `hms/ets/build-tools/ets-loader/kit_configs/@kit.AgentFrameworkKit.json` | 19 个符号全集（无客户端符号） |
| `hms/ets/api/@hms.data.localChatModel.d.ts` | 38 `isStream`；105 `isFinished`；118 `init`；142 `chat` |
| `hms/ets/api/@hms.data.rag.d.ts` | 188 `abstract class ChatLLM`；208 `abstract streamChat`；458 `streamRun`；497 `createRagSession` |
| `hms/ets/api/@hms.ai.insightIntent.d.ts` | 41/63 `shareIntent`；81 `deleteIntent`；168 `getSid` |
| `openharmony/ets/api/@ohos.data.intelligence.d.ts` | 39 `getTextEmbeddingModel`；300 `getSupportedCloudModel` |
| `openharmony/ets/api/@ohos.app.ability.InsightIntentExecutor.d.ts` | 76/99/125 `onExecute*` → `ExecuteResult` |
| `openharmony/ets/api/@ohos.app.ability.insightIntentProvider.d.ts` | 43 `sendExecuteResult`；58 `sendIntentResult` |
| `openharmony/ets/api/@ohos.app.agent.AgentExtensionAbility.d.ts` | 63 `onConnect`；74 `onData`；85 `onAuth` |
| `openharmony/ets/api/application/AgentHostProxy.d.ts` | 40 `sendData` |
| `openharmony/ets/api/@ohos.bundle.skillManager.d.ts` | 102/118 `getSkillInfo(s)ForSelf` |

### 7.2 官方文档

| 主题 | URL |
|---|---|
| Agent Framework Kit 简介（含 A2A 客户端表述，与 API 冲突） | <https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/hmaf-introduction> |
| 通过 Function 组件拉起智能体（含完整代码 + 前置条件） | <https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/hmaf-function> |
| FunctionComponent / AgentController API 参考 | <https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/hmaf-function-component> |
| 通过 AgentAbilityExtension 实现 A2A（只讲服务端） | <https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/hmaf-a2a-dev-guide> |
| 端侧 A2A 框架概述（"智能助手作为 Agent 客户端"） | <https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/agent-overview> |
| 方舟智能开发框架概述（"应用能力外化给系统智能体调用"） | <https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkaf-overview> |
| AgentExtensionAbility 配置（AgentCard / `capabilities.streaming`） | <https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/agent-extension-configuration> |
| 端侧问答模型（PC/2in1 + 企业开发者约束） | <https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/dataaugmentation-localchatmodel> |
| Data Augmentation Kit 简介（本地问答 = HiAiMgr 连 LLM） | <https://developer.huawei.com/consumer/en/doc/harmonyos-guides/dataaugmentation-introduction> |
| 意图框架概述（意图共享 vs 意图调用，发起者定义） | <https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/insight-intent-overview> |
| Intents Kit 简介（设备/地区/企业开发者限制） | <https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/intents-introduction> |
| 智能体场景开发案例（三模式：LLM/工作流/A2A） | <https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-agent> |
| MCP 协议上架指导（MCP URL + Header/Query 鉴权 + 审核） | <https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/intents-kit-listing-mcp-protocol> |
| 小艺开放平台入口 | <https://developer.huawei.com/consumer/cn/celia/> |

### 7.3 未能读取正文的一手页面（如实标注）

| 页面 | 状态 |
|---|---|
| 《A2A协议接入方案》 <https://developer.huawei.com/consumer/cn/doc/service/agent2agent-exp-other-0000002660585433> | SPA，正文抓取失败 |
| 《云A2A协议技术规范》 <https://developer.huawei.com/consumer/cn/doc/service/agent2agent-comments-0000002500412353> | SPA，正文抓取失败 |
