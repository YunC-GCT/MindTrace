# 应用侧调用小艺智能体：官方口径下的可行路径与限制

> 2026-10-24 · 取证口径：本机 DevEco SDK **26.0.0.105 / API 26（HarmonyOS 7.0.0 Release）** 的 `.d.ts`，配合 developer.huawei.com 当前文档。结论先行。

## 0. 结论

| 路径 | 支持度 | 一句话 |
|---|---|---|
| UI 面板 `FunctionComponent` | ✅ 唯一已交付 | 只能拉起，拿不到回答 |
| A2A 客户端（应用调小艺） | ❌ 文档写了，SDK 没给 | 简介称可作 client，指南/API 参考只有 Server |
| 端侧模型开放 | ❌ 未找到官方来源 | SDK 无任何生成式 LLM API |

## 1. Kit 到底提供什么

官方简介原文：「**主要包含 Function 组件和 A2A（Agent to Agent）协议模块**」（[简介](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/hmaf-introduction)）。

- Function：`FunctionComponent`（`@Component` struct，参数仅 `agentId/onError/options/controller`）+ `FunctionController`。文本入口只有 `FunctionOptions.queryText`，**单向下发首句**；`AgentController` 只有 `isAgentSupport()` 与 `agentDialogOpened/Closed` 两个事件（[API 参考](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/hmaf-function-component)；本机 `hms/ets/api/@hms.ai.AgentFramework.d.ets:40-90`）。
- A2A：`createA2AServer / Server / RequestContext / ProxySender`。
- 结论：**没有「发 query / 收 answer / 收 stream chunk」的文本级接口**，只有 UI 控件。

## 2. 能不能做 A2A 客户端

官方文档自相矛盾，这是关键：

- 简介（中英同文）称：「在应用中智能体**可以作为客户端或服务端**……当一个应用内的智能体需要调用小艺智能体完成某项任务时，可以通过 A2A 协议发起请求」。
- 实现指南原文：「本模块提供 A2A 协议的**服务端** API」（[指南](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/hmaf-a2a-dev-guide)）；[API 参考](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/hmaf-a2a-protocol) 同样只有 `createA2AServer`。
- 机器可验证：`hms/ets/kits/@kit.AgentFrameworkKit.d.ts` 仅导出 `createA2AServer/ProxySender/Server/RequestContext`；全 SDK 搜 `A2AClient` 零命中。

→ **client 属文档前瞻，API 26 未交付**（设备侧 HSP 若日后补充，须以新版 SDK 声明为准）。

平台侧同样没有对外 endpoint。端 A2A 文档开篇即「本文档说明了小艺与应用内 Agent 的通信协议规范」，请求方法为 `MessageStream`，回调 method 为 `Execute`/`Cancel`/`PerceptionSuggest`，**全部由小艺发起**（[端 A2A 技术规范](https://developer.huawei.com/consumer/cn/doc/doccenter-celia/agent2agent-device-0000002735764870)、[对话交互](https://developer.huawei.com/consumer/cn/doc/doccenter-celia/agent2agent-chat-0000002735604996)）；云 A2A 仍是平台调用开发者服务器，官方《实现接口定义》写明「华为服务器使用长连接的方式进行调用」，鉴权为 AK/SK 与 OAuth（[接口定义](https://developer.huawei.com/consumer/cn/doc/doccenter-celia/interface-0000001195110098)）。**反向的「开发者凭 Key 调小艺」入口：未找到。**

## 3. 面板回答能否回传宿主

不能。`agentDialogOpened/Closed` 均为 `Callback<void>`，无 payload；`queryText` 只进不出。官方「关联应用」文档只讲一键呼出与「未授权」排障（[关联应用](https://developer.huawei.com/consumer/cn/doc/service/related-applications-0000002437785706)），FAQ 无回传条目。唯一有来有回的形态是反过来：你的 Agent 被小艺调用，答案本就产生在你的进程里。

## 4. 端侧模型开放

**未找到官方来源。** 全 SDK `largeLanguageModel` 零命中；`LLM` 仅出现在 `@hms.data.rag`、`@hms.data.knowledgeProcessor` 的 `abstract class ChatLLM`——注释写明 "Your app needs to inherit from this class"，是协议壳不是模型本体（`hms/ets/api/@hms.data.rag.d.ts:188`）。官方 RAG 指南要求上下文 ≥30k、举例 Qwen2.5-7B/Llama-3.1-8B 且须联网，生成段在端外。CANN Kit 的「LLM 大模型能力开放」是自带权重做量化转换，不是调用小艺模型。

## 5. 卡在哪一步

卡在**没有客户端传输层**。自建聊天 UI + 流式需要：① 取 token 流；② 带 contextId 续多轮；③ 可取消。当前这三件事只有服务端实现（`Server.updateStatus/addArtifact`），客户端侧一个都没有。退路两条：用 FunctionComponent（丢 UI 与流式），或把自己注册成端 A2A Agent（入口与 UI 归小艺）。
