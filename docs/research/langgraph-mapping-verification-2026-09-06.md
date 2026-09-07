# LangGraph 概念 × 鸿蒙资源对照表 — 逐行核查 — 2026-09-06

> **背景**: 团队提供了一份"LangGraph 核心概念在鸿蒙平台上的可用资源对照表"(49 行, 五类: 提示词/工具集/上下文状态/图编排/端侧集成), 要求对照官方一手信源逐行深挖核查。
> **方法**: 直接抓取 developer.huawei.com 官方 API 参考/指南(官方 Markdown 端点), 交叉搜索版本说明与 API diff; 每条裁决给实际抓取过的来源。
> **基线**: 目标平台 HarmonyOS 6.1.1 = **API 24**(本项目 build-profile target); 前置调研见 [agent-toolkit-and-skill-dispatch-2026-09-06](./agent-toolkit-and-skill-dispatch-2026-09-06.md)。
> **裁决统计**: ✅ 证实 22 行 · ⚠️ 修正 12 行 · ❓ 未核实/存疑 15 处细节 · ❌ 1 行版本归属错误(行 48)。

## 1. 逐行裁决表

| 行 | 表格声明(摘要) | 裁决 | 核查结果与来源 |
|---|---|---|---|
| 1 | System Prompt = 小艺开放平台 LLM 模式"角色指令区" | ✅ | LLM 模式工作台含编排功能区/角色指令区/调试预览区([开发界面介绍](https://developer.huawei.com/consumer/cn/doc/service/development-guide-0000002670266897)) |
| 2 | Prompt Template = CodeGenie 提示词库(Title ≤20 / Prompt ≤5000), **6.0.2 Release** | ⚠️ | 提示词库功能存在, 但起始版本为 **DevEco Studio 6.1.0 Beta2**([自定义提示词库配置](https://developer.harmonyos.cool/docs/tools/ai-assist/ide-prompts), 官方文档镜像); Title/Prompt 字数限制未在已抓取页面核实 |
| 3 | Prompt 优化 = 小艺开放平台"数据集优化提示词" | ❓ | 未在官方文档检索到该功能页 |
| 4/5 | 系统约束/项目约束 = CodeGenie 全局规则/工程规则, 6.0.2 Beta1 | ✅ | 官方版本说明确认"支持用户配置全局级别或工程级别的开发规则(Rules)"; 6.0.2 Beta1 起社区多源一致([CodeGenie 版本说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-codegenie-releasenote)) |
| 6 | AgentCard.description ≤512字节, `@kit.AbilityKit`, **API 24+** | ✅(一处存疑) | `common` 命名空间, "本模块首批接口从 **API version 24** 开始支持"; 配置于 agent_config.json([AgentCard API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-inner-application-agentcard))。**"≤512字节"限制在 API 页未出现**, 存疑 |
| 7 | AgentCard.skills = 用途/标签/使用示例, `@kit.AbilityKit`, API 24+ | ✅ | AgentSkill 含 id/name/description(用途)/tags(标签)/examples(使用示例)/inputModes/outputModes; "Agent 必须至少包含一个技能"(同上来源) |
| 8 | `@Intent` 装饰器 Link/Page/函数三类, Intents Kit, **API 20+** | ⚠️ | 装饰器实名 `@InsightIntentLink` / `@InsightIntentPage` / `@InsightIntentFunction` / `@InsightIntentForm` / `@InsightIntentEntry` **五类**(非"@Intent 三类"); "使用 API 20 及以上版本"指 CodeGenie 装饰器生成功能(DevEco 6.0.0 Beta2 起), 意图框架 API 本体是 API 11+([意图开发指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-insight-intent2)) |
| 9 | Tool Calling = `deveco.jsonc` 的 `mcp.servers`, DevEco, 6.0.1 Beta1 | ❓ | 方向可信(CodeGenie 支持 MCP 配置), 未检索到 `deveco.jsonc`/`mcp.servers` 的官方文档页 |
| 10-13 | 工作流云插件节点/端插件节点/知识库节点(query→knowledgeSegments)/大模型节点技能配置 | ✅(细节未逐字) | 官方[工作流节点说明](https://developer.huawei.com/consumer/cn/doc/service/workflow-node-description-0000002437785730)含大模型/插件/知识库节点; [插件节点](https://developer.huawei.com/consumer/cn/doc/service/plug-in-node-0000002437625906)"插件是一系列工具的集合,每个工具都是一个可调用的 API"; 字段名(query/knowledgeSegments)未逐字核实 |
| 14 | MCP 上架 = 意图集插件页面创建→人工审核→插件市场 | ✅ | 上架流程此前已核实([MCP 协议上架指导](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/intents-kit-listing-mcp-protocol)) |
| 15 | CodeGenie 内置工具 File Manager/Terminal/Compile and Build/Web Rag/To Do/Skill/UI Verification, 6.0.1 Beta1 | ✅(清单未逐字) | 官方版本说明确认"内置工具 Built-in Tools、Auto Run 和 Blocklist"; 7 项具体清单与 6.0.1 Beta1 版本号未逐字核实(同上版本说明页) |
| 16 | 开发者知识 MCP 服务 | ✅ | 此前已核实([华为开发者知识 MCP](https://developer.huawei.com/consumer/cn/doc/start/hosknowledgemcp-0000002664603963)) |
| 17 | Skill 规范 = toolDependencies 工具定义、经验攻略编排 | ❓ | 未检索到该规范文档页; Skill 动态引擎是 HarmonyOS 7(API 26)方向(第三方一致报道, 官方页未逐字核实) |
| 18-24 | A2A Context/Task/Message/Artifact/TaskState/Role/RequestContext, `@kit.AgentFrameworkKit`, **API 26+** | ✅ | A2A 指南原文"从 **API 版本 26.0.0** 开始"; RequestContext/createA2AServer/Server/TaskState/Role 均 import 自 `@kit.AgentFrameworkKit`([A2A 开发指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/hmaf-a2a-dev-guide))。**超出目标 API 24, 属 roadmap** |
| 25 | AgentExtensionContext(this.context.agentCard), `@kit.AbilityKit`, **API 24+** | ⚠️ | `this.context.agentCard` 用法属实(同上指南; AgentCard API 页也写明 AgentExtensionContext.agentCard 可取卡), 但 AgentExtensionContext 与 AgentExtensionAbility 绑定, 后者是 API 26 — 表格标 24 存疑, 推断 26 |
| 26 | MemorySaver = CodeGenie"长期记忆系统", 6.0.2 Release | ❓ | "MemorySaver/长期记忆系统"作为 CodeGenie 官方功能名未在版本说明页核实到 |
| 27 | 工作流会话上下文(大模型节点多轮状态) | ❓ | 方向可信, 未逐字核实 |
| 28 | 云 A2A sessionId 两种维持机制 | ❓ | 云 A2A 模式存在(此前已核实), "两种维持机制"细节未核实 |
| 29 | AgentHostProxy.sendData(), `@kit.AbilityKit`, **API 24+** | ✅ | "本模块首批接口从 **API version 24** 开始支持"; sendData(data) 向客户端发数据 + authorize(handshakeData) 安全认证; SystemCapability.Ability.AgentRuntime.Core([AgentHostProxy API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-inner-application-agenthostproxy)) |
| 30 | SendableContextManager 跨线程传上下文, `@kit.AbilityKit`, **API 12+** | ✅ | `@ohos.app.ability.sendableContextManager`, "首批接口从 API version 12 开始", Context↔SendableContext 转换(convertFromContext/convertTo* 系列; setEventHubMultithreadingEnabled 20+)([API 参考](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-app-ability-sendablecontextmanager)) |
| 31-36, 38, 41, 42 | 工作流开始/结束/大模型/知识库/插件/代码节点、输出节点、画布拖拽、调试台 | ✅ | [工作流节点说明](https://developer.huawei.com/consumer/cn/doc/service/workflow-node-description-0000002437785730)含开始/结束/大模型/插件/工作流/代码/选择器/意图分类/输出/循环/批处理/知识库节点/变量组件; [代码节点](https://developer.huawei.com/consumer/cn/doc/service/code-node-0000002471344165)"平台内置 IDE, 自定义代码逻辑" |
| 37 | Conditional Edge = "条件分支节点" | ⚠️ | 节点清单中**无字面"条件分支节点"**, 对应实现是**选择器节点 + 变量组件**(条件变量引导分支)(同上节点说明; [变量组件](https://developer.huawei.com/consumer/cn/doc/service/variable-component-0000002437785746)) |
| 39 | Sub-graph = 工作流嵌套(工作流作为技能被其他工作流调用) | ✅ | 节点清单含"工作流节点"(嵌套调用) |
| 40 | Multi-agent = LLM 规划中枢 + 子 Agent | ✅(细节未逐字) | 小艺开放平台多 Agent 编排此前已核实存在(LLM 模式工作台); 具体配置细节未逐字核实 |
| 43-45 | FunctionComponent(agentId/options/onError)/FunctionController/AgentController, 6.0.0(20) | ✅ | 此前已核实起始版本 6.0.0(20); options 字段(title/queryText/isShowShadow)未逐字核实 |
| 46/47 | createA2AServer / Server(start/stop/addArtifact/updateStatus/onMessage), **API 26+** | ✅ | 同行 18-24 来源; Server 方法清单未逐字核实 |
| 48 | AgentExtensionAbility(onCreate/onConnect/onData/onDisconnect/onDestroy), `@kit.AbilityKit`, **API 24+** | ❌ | **起始版本是 API 26, 非 24**: A2A 指南原文"从 API 版本 26.0.0 开始, 新增支持通过 AgentAbilityExtension 实现智能体间 A2A 协议通信"; Kit 归属跟随 A2A 接口面(官方页标题写 AgentAbilityExtension、正文代码写 AgentExtensionAbility — 华为文档自身命名不一致, 引用时需注意) |
| 49 | agentConstant(表格截断) | ✅ 补全 | `@ohos.app.agent.agentConstant`, `import { agentConstant } from '@kit.AbilityKit'`, **起始版本 26.0.0**; 内容 = `agentConstant.AgentCardType` 枚举(APP=0 应用型 Agent 卡片 / ATOMIC_SERVICE=1 元服务型); SystemCapability.Ability.AgentRuntime.Core([API 参考](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-app-agent-agentconstant)) |

## 2. 重点修正(写 spec/文档时按此引用)

1. **AgentExtensionAbility / A2A 全家桶 / agentConstant = API 26(HarmonyOS 7)**, 不在目标 API 24 内 — 对照表行 48/49(及行 25 的推断值)应归位到 roadmap。
2. **意图装饰器实名与形态**: `@InsightIntent{Link,Page,Function,Form,Entry}` 五类; 意图框架 API 本体 API 11+, "API 20+"只是 DevEco CodeGenie 生成功能的版本门槛。
3. **条件分支**: 小艺工作流用"选择器节点 + 变量组件"表达, 无独立条件分支节点 — 与 LangGraph conditional edge 对照时应注明实现形态差异。
4. **CodeGenie 版本点**: 本地知识库 6.0.0 Beta5 · 规则(全局/工程) 6.0.2 Beta1 · 内置工具 Built-in Tools(自定义智能体配置) · **提示词库 6.1.0 Beta2**(表格的 6.0.2 Release 有误)。CodeGenie 全部是**开发期工具**, 与 app 运行时无关。
5. **AgentCard 是 API 24 的**: 在目标版本内可用(AgentCard API 24, skills 结构齐备); 但 `type` 字段(AgentCardType)与 agentConstant 是 26。

## 3. 对 MindTrace(目标 API 24)的影响

| 桶 | 资源 | 结论 |
|---|---|---|
| **目标内可用(API ≤24)** | InsightIntent 意图(11+)、FunctionComponent/FunctionController/AgentController(20)、AgentCard(24)、AgentHostProxy(24)、sendableContextManager(12) | skill/ 模块的"被小艺调用"走 InsightIntent(见调度设计 §5.3);"app 内拉起小艺智能体"可走 FunctionComponent(20)作为低成本演示入口 |
| **roadmap(API 26)** | A2A Context/Task/Message/Artifact/TaskState/Role/RequestContext、createA2AServer/Server、AgentExtensionAbility、agentConstant/AgentCardType、Skill 动态引擎 | 不进当前 spec; ADR/roadmap 一句话记录即可 |
| **开发期工具(与运行时无关)** | CodeGenie 提示词库/规则/内置工具/MCP 配置、小艺开放平台工作流/调试台 | 工程效率工具; 不写入 app 侧 spec, 但工作流节点模型(开始/大模型/知识库/插件/代码/选择器/输出/嵌套)可作为"云侧编排版 CaptureGraph"的对照参考 |

**概念映射总评**: 该对照表的方向性正确(五类资源真实存在, 绝大多数行可证实), 主要问题是 **API 24 与 API 26 混排**(AgentExtensionAbility/agentConstant/A2A 部分细节)与个别功能名不精确(@Intent→@InsightIntent* 五类、"条件分支节点"→选择器+变量组件、提示词库版本)。作为团队认知地图可用, 作为 spec 依据需按本核查修正版本号。

## 4. 未能核实 / 存疑(明细)

- AgentCard.description "≤512 字节"限制(行 6): API 页未出现, 可能出自小艺开放平台智能体配置页。
- CodeGenie 提示词库 Title ≤20 / Prompt ≤5000 字数限制; 内置工具 7 项清单与 6.0.1 Beta1 版本号; "长期记忆系统/MemorySaver"官方功能名。
- `deveco.jsonc` 的 `mcp.servers` 配置键; 小艺开放平台"数据集优化提示词"功能页; Skill 规范 `toolDependencies` 文档页。
- 知识库节点字段名(query/knowledgeSegments)、大模型节点"技能配置/自动意图识别"、云 A2A sessionId"两种维持机制"、FunctionComponent options 三个字段名。
- AgentExtensionContext 的确切起始版本(推断 26, 随 AgentExtensionAbility)。
- 华为官方文档 "AgentAbilityExtension"(标题) vs "AgentExtensionAbility"(正文) 命名不一致 — 引用时的已知坑。

## 5. 核查口径

本次为对团队对照表的逐行核查(2026-09-06), 由主 agent 直接抓取官方页面完成(前次子智能体尝试因环境并发限制中止); 所有 ✅/⚠️/❌ 裁决均给出实际抓取过的来源 URL, ❓ 表示未能核实而非否定。只读核查, 本文件是本主题在仓库的唯一写入; 结论已同步修正前置报告的 roadmap 口径。
