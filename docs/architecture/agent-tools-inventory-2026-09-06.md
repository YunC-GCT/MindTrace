# Agent 可用工具清单 (agent-tools inventory) — 2026-09-06

> **体检性质**: 全仓只读清点, 不修改任何业务代码。本文件是本次体检唯一的仓库写入。
> **扫描时点**: `develop@fcd1f11` (与 origin/develop 同步)。驱动技能: improve-codebase-architecture; 口径对齐 [CONTEXT.md](../../CONTEXT.md) (「MCP 工具 (mcp/)」「Kit Facade (contract)」「NoteDaoAdapter」「sub-agent」) 与 [ADR-0010](../adr/0010-mcp-tools-semantics.md)、[ADR-0009](../adr/0009-kit-facade-injection-boundary.md)。
> **可视化报告**: HTML 版生成于本机临时目录 (不入 git, 见 [html-in-docs 决策树](../style/html-in-docs.md))。

## 1. 分类口径

**agent 工具** = LLM 或 pipeline 在运行时可选择/封装调用的能力 (MCP 语义工具、未来 `tools/` CRUD 工具、外部服务端点)。仅被代码硬编码调用的基建类 (Client / Resolver / Adapter / Service / Utils) 单列判读, 不计入工具; [scripts/](../../scripts/README.md) 是开发/CI 工具链, 服务开发 agent 而非 MindTrace app 内 agent, 单列一节。

## 2. 工具总表

| # | 名称 | 路径 | 分类 | 调用方 | 方法面 (公开) | 状态 |
|---|------|------|------|--------|----------------|------|
| 1 | OcrTool | `agents/src/main/ets/mcp/tools/OcrTool.ets` | MCP 语义工具 (ADR-0010 口径; 无 MCP wire 协议) | TypeClassifier (×2)、AiSettingsViewModel (×1) | `recognizeBytes` / `recognizeBytesWithEndpoint` / `recognize` / `recognizeImage` | 现役 |
| 2 | LlmClient | `common/src/main/ets/llm/LlmClient.ets` | LLM 能力层 (非工具: 无工具选择机制) | TypeClassifier、KnowledgeModel、AgentChatService、AgentMemoryService、StudyPlanViewModel、AiSettingsViewModel | `call(request)` (JSON / 真 SSE 双路径) | 现役 |
| 3 | LlmGuard | `common/src/main/ets/llm/LlmGuard.ets` | LLM 输出校验/重试 (LlmCaller 接缝) | TypeClassifier、KnowledgeModel、AgentMemoryService | `callJsonWithRetry` / `validateJsonText` / `extractJsonObject` | 现役 |
| 4 | NoteDao | `entry/src/main/ets/database/NoteDao.ets` | CRUD 能力面 (未工具化) | NoteDaoAdapter、NoteEditService、AiService、NotesViewModel、KnowledgeGalaxyViewModel、ProfileViewModel、HomeViewModel、UiDataCacheService (读) | 7 方法 (insert/update/deleteById/queryById/queryAll/queryAllMetadata/queryByReviewStatus) | 现役 |
| 5 | ChatMessageDao | `entry/src/main/ets/database/ChatMessageDao.ets` | CRUD 能力面 | AgentMemoryService | 4 方法 (insert/queryRecent/queryAll/deleteBySession) | 现役 |
| 6 | AgentMemoryDao | `entry/src/main/ets/database/AgentMemoryDao.ets` | CRUD 能力面 | AgentMemoryService | 6 方法 (insert/queryPendingNotes/queryLatestSummary/queryLatestProfile/markPendingUsed/deleteBySession) | 现役 |
| 7 | StudyPlanDao | `entry/src/main/ets/database/StudyPlanDao.ets` | CRUD 能力面 | StudyPlanViewModel (用户 CRUD + AI generatePlan 直写) | 6 方法 (insert/queryAll/updateDone/updateTitle/updateCreatedAt/deleteById) | 现役 |
| 8 | ReminderFacade | `common/src/main/ets/kit/ReminderFacade.ets` | Kit 接缝契约 (ADR-0009) | 无 (仅 common/Index.ets re-export) | `scheduleReviewReminder` / `cancelByUnit` | 契约已立, 0 实现 0 消费 |
| 9 | BackgroundTaskFacade | `common/src/main/ets/kit/BackgroundTaskFacade.ets` | Kit 接缝契约 | 无 | `requestOneShot` / `hasPending` | 契约已立, 0 实现 0 消费 |
| 10 | FormCardFacade | `common/src/main/ets/kit/FormCardFacade.ets` | Kit 接缝契约 | 无 (cardservice FormAbility 现用 mock) | `pushSnapshot` | 契约已立, 0 实现 0 消费 |
| 11 | `agents/src/main/ets/tools/` | (不存在) | CRUD 工具预留位 (ADR-0010) | — | — | 预留, 目录未创建 |
| 12 | skill/ 模块 | `skill/src/main/ets/Index.ets` + `SkillAbility.ets` | 小艺 (Xiaoyi) skill 接入预留位 | 无 | `SKILL_VERSION` 常量; SkillAbility.onCreate 仅 TODO | 预留保留 (未实装; 2026-09-06 裁决不冻结不移除) |
| 13 | OCR python 服务 | `tools/ocr_service/formula_api.py` | 外部 HTTP 服务 (OcrTool 的远端一半; 无 MCP 协议) | OcrTool (multipart POST) | 3 端点 (见 §3.7) | 现役 (start.bat 内联组 app) |
| 14 | scripts/ 工具链 | `scripts/` | 开发/CI 工具 — **不算 agent 工具** | CI / 开发者 | arkts-lint (34 规则 / 89 测试)、naming-lint、link-check、audit-arkts-strict v1、lint 包装脚本 | 单列说明 |

## 3. 逐项详注 (源码引用)

### 3.1 MCP 语义工具: OcrTool

- 类声明: `agents/src/main/ets/mcp/tools/OcrTool.ets:52`; 模块导出: `agents/src/main/ets/Index.ets:29`
- 方法面: `recognizeBytes` (:60)、`recognizeBytesWithEndpoint` (:64)、`recognize` (:98)、`recognizeImage` (:111); 私有约 15 个 (端点解析 / multipart / UTF-8 / MIME)
- 能力形状: 混合 OCR — 端侧 CoreVisionKit `textRecognition` (:177-207) + 本地 HTTP 服务回退与公式识别 (默认端点 `http://127.0.0.1:8000/api/v1/formula/recognize`, :57; 实际端点经 [OcrConfig](../../common/src/main/ets/ocr/OcrConfig.ets) 单例)
- 调用方复核: **不止 TypeClassifier** — `agents/src/main/ets/agents/TypeClassifier.ets:140,146` (image/file payload 分支) + `entry/src/main/ets/viewmodels/AiSettingsViewModel.ets:172` (设置页 OCR 连通性测试, 走 `recognizeBytesWithEndpoint` + 内置测试图)
- 管线位置: OcrNode (`agents/src/main/ets/graph/nodes/OcrNode.ets`) → TypeClassifier.recognizeText → OcrTool; CaptureGraph 的 `capture` 步
- "MCP" 语义: 按 ADR-0010, `mcp/` 是**工具定位与封装语义**分类, 不代表运行着 MCP server; 该文件与 python 服务均无 JSON-RPC/MCP 协议实现 (grep `mcp|jsonrpc|FastMCP` 零命中) — 与 ADR-0010 "是否/何时以 MCP 协议对外暴露由维护队员决定" 的开放注记一致

### 3.2 LLM 能力层 (function-calling 复核结论: 不支持)

- [LlmClient](../../common/src/main/ets/llm/LlmClient.ets): 唯一公共入口 `call(request)` (:57, spec [005](../specs/005-llm-client-consolidation.md)); JSON 路径 `callJsonInternal` (:74) + 真 SSE 路径 `callStreamInternal` (:200, `requestInStream` + dataReceive/dataEnd + 首字节 8s 降级 + 总超时)
- **`LlmRequestBody` 无 tools/function_call/tool_choice 字段** (复核确认, [LlmTypes.ets:20-29](../../common/src/main/ets/llm/LlmTypes.ets)); `LlmCallRequest` (:130-143) 同样没有; 响应侧 `extractContent` (:142) 只读 `message.content` / `reasoning_content`, **不解析 `tool_calls`**。结论: LLM 层当前无法表达工具调用, 所有工具使用都是代码硬编码
- [LlmGuard](../../common/src/main/ets/llm/LlmGuard.ets): `callJsonWithRetry` (:37, 校验失败把 issues 拼回消息重试, 默认 2 次)、`validateJsonText` (:68)、`extractJsonObject` (:72); 依赖 `LlmCaller` 接口 (:5) — 生产侧 LlmClient、测试侧 mock (`common/src/test/LlmGuard.test.ets`), 是一个有双 adapter 的真实 seam
- 配套: [LlmConfig](../../common/src/main/ets/llm/LlmConfig.ets) (单例, preferences 持久化 endpoint/model/key/temperature/maxTokens/timeout)、LlmOutputRules (JSON_ONLY_RULES / LATEX_GENERATION_RULES / buildGuardRetryMessage)
- 调用方: agents 侧 TypeClassifier / KnowledgeModel; entry 侧 AgentChatService / AgentMemoryService / StudyPlanViewModel / AiSettingsViewModel

### 3.3 CRUD 能力面: 4 个 DAO (23 个公开方法)

| DAO | 方法 (行号) | 写入触发方 |
|---|---|---|
| [NoteDao](../../entry/src/main/ets/database/NoteDao.ets) | insert :29 · update :44 · deleteById :61 · queryById :77 · queryAll :100 · queryAllMetadata :123 · queryByReviewStatus :146 | 用户编辑 (NoteEditService.upsert :14)、AI 笔记生成 (路径①)、UI 读 (NotesViewModel / KnowledgeGalaxyViewModel / ProfileViewModel / HomeViewModel / UiDataCacheService) |
| [ChatMessageDao](../../entry/src/main/ets/database/ChatMessageDao.ets) | insert :11 · queryRecent :24 · queryAll :51 · deleteBySession :74 | AgentMemoryService.insert (:49), 由 AgentChatService 消息流触发 |
| [AgentMemoryDao](../../entry/src/main/ets/database/AgentMemoryDao.ets) | insert :11 · queryPendingNotes :24 · queryLatestSummary :49 · queryLatestProfile :73 · markPendingUsed :98 · deleteBySession :119 | AgentMemoryService.insert (:69), LLM 生成的画像/摘要落库 |
| [StudyPlanDao](../../entry/src/main/ets/database/StudyPlanDao.ets) | insert :19 · queryAll :41 · updateDone :65 · updateTitle :85 · updateCreatedAt :105 · deleteById :125 | StudyPlanViewModel (用户 CRUD + AI generatePlan 直写 :232) |

**AI 触发写库路径 — 复核结果为 3 条, 不是 1 条**:

1. **路径① (有 truth_check 把关)**: [AgentChatService.generateNoteFromConversation](../../entry/src/main/ets/services/AgentChatService.ets) :206 → `classifyTextIntent` (:413, 意图门禁) → `summarizeConversation` (:253, LlmClient) → [AiService.captureText](../../entry/src/main/ets/services/AiService.ets) :117 → Dispatcher/CaptureGraph (persist=true) → [NoteDaoAdapter](../../entry/src/main/ets/adapters/NoteDaoAdapter.ets) → NoteDao.insert — 已知路径, 确认存在
2. **路径② (LlmGuard 弱校验, 无 truth_check)**: AgentChatService 的 `safeUpdateLearnerProfileIfNeeded` / `safeSummarizeIfNeeded` / `safeSaveAssistantMessage` → [AgentMemoryService](../../entry/src/main/ets/services/AgentMemoryService.ets) → LlmGuard `callJsonWithRetry` (:156) 校验后 → AgentMemoryDao.insert (:69) + ChatMessageDao.insert (:49) — LLM 生成的画像 / 摘要 / 回复落库
3. **路径③ (无校验 + ViewModel 越层直写)**: [StudyPlanViewModel.generatePlan](../../entry/src/main/ets/viewmodels/StudyPlanViewModel.ets) → LlmClient (:28) 生成计划项 → `this.dao.insert(item)` (:232) — ViewModel 持 RdbStore 直写 DAO, 跳过 Service 层, 无 LlmGuard 校验

另: `AiService.capture` (AiService.ets:52, 头注释声明的"拍照整链入库入口") 在 entry 内**无调用方** — 实际图片流是 CameraOverlay.onConfirm → AgentFloatWindow → [AgentChatService.captureReply](../../entry/src/main/ets/services/AgentChatService.ets) :45 → `analyzeImage` (:71, persist=false 只分析) → 对话回复; 图片直接转 KnowledgeUnit 入库的入口当前未接线 (入库只能经对话中显式"生成笔记"意图的文本路径①)。

### 3.4 Kit 接缝契约 (3 个, 契约已立 / 实现延后)

- [ReminderFacade](../../common/src/main/ets/kit/ReminderFacade.ets) :21 — `scheduleReviewReminder` / `cancelByUnit`; [BackgroundTaskFacade](../../common/src/main/ets/kit/BackgroundTaskFacade.ets) :10 — `requestOneShot` / `hasPending`; [FormCardFacade](../../common/src/main/ets/kit/FormCardFacade.ets) :18 — `pushSnapshot`
- 全仓 grep `implements *Facade` 零命中; 除 common/Index.ets re-export 外无 import — **0 实现 0 消费**, 与 ADR-0009 "契约先行、实现注入延后" 一致; 卡片侧现状是 [FormAbility](../../cardservice/src/main/ets/formability/FormAbility.ets) :7-14 返回 mock 数据
- 现状评级: 假设性 seam (一个 adapter 都没有); ADR-0009 允许, 但拖延越久签名漂移风险越大

### 3.5 预留位: `agents/src/main/ets/tools/`

- 确认**不存在** (`ls` 验证) — 与 ADR-0010 "`tools/` 留给增删查改类工具, 未落地不创建" 一致
- 注意与仓库根 `tools/` 目录区分: 根级 `tools/` 现存且只有 `tools/ocr_service/` (python 服务), 见 §3.7 与 F7 术语发现项

### 3.6 skill/ 模块 (小艺 skill 接入预留位 — 裁决保留)

- [Index.ets](../../skill/src/main/ets/Index.ets) 仅 `export const SKILL_VERSION = 'v0.0.1'`; [SkillAbility.ets](../../skill/src/main/ets/skillability/SkillAbility.ets) onCreate 仅注释 "placeholder" + `TODO(W1 块 3): 根据 want.action 路由到对应 Agent` (头注释自述目标: 7 Intent actions 路由 + 调 common / agents 共享后端)
- 无任何其它模块 import skill/ — 现状零调用方
- **2026-09-06 裁决 (用户确认)**: 该模块是**小艺 (Xiaoyi) skill 开发预留位**, 开发尚未开始但必须保留 — F4 的"冻结/移除"建议撤销; 后继审计不得再把它当死代码建议删除 (裁决理由建议以 ADR 固化, 见 §6 F4 行)

### 3.7 OCR python 服务 (`tools/ocr_service/`)

- HTTP 端点 ([formula_api.py](../../tools/ocr_service/formula_api.py)): `POST /api/v1/formula/recognize` (:108) · `GET /api/v1/formula/health` (:134) · `POST /api/v1/ocr/recognize` (:144); 路由前缀 `/api/v1` 由 start.bat 内联组装 (`tools/ocr_service/start.bat:91`: `FastAPI()` + 两个 `include_router` + `uvicorn.run(0.0.0.0:8000)`)
- 函数面: FormulaTool (`recognize` :73 / `recognize_from_bytes` :108 / `recognize_with_metadata` :127, formula_tool.py)、OcrTextTool (`recognize` :25 / `recognize_to_plain_text` :36, ocr_text_tool.py)
- **无 MCP 协议实现** (无 jsonrpc / mcp SDK 依赖) — 纯 FastAPI REST
- 文档漂移: AGENTS.md 常用命令 `python -m uvicorn ocr.app:app --port 8000` 已失效 (仓库根无 `ocr/` 目录, formula_api.py 亦无 `app` 对象), 实际启动方式是 `tools/ocr_service/start.bat`

### 3.8 其它命名像工具的类 (逐个判读)

| 类 | 路径 | 判读 | 理由 |
|---|---|---|---|
| TypeClassifier | `agents/src/main/ets/agents/TypeClassifier.ets` | 不是工具, 是**工具消费方** (sub-agent) | 内部 new OcrTool + LlmGuard; 它自己被 pipeline 硬编码调用, LLM 无从选择它 |
| KnowledgeModel | `agents/src/main/ets/agents/KnowledgeModel.ets` | 同上 (sub-agent) | 结构化 sub-agent, LlmGuard 消费方 |
| PromptBuilder / StructureService / TruthCheckService | `agents/src/main/ets/agents/` | 不是工具 — KnowledgeModel 之上的 façade (D2 Ticket #3) | pipeline 内部组件, 头注释自述 "façade" |
| Dispatcher / CaptureGraph | `agents/src/main/ets/core/` `graph/` | 不是工具 — 编排层 | Dispatch 是 Order 的入口契约 (CONTEXT.md), 非可选项 |
| NoteDaoAdapter | `entry/src/main/ets/adapters/NoteDaoAdapter.ets:6` | 不是工具 — 接缝适配器 | implements agents 的 NoteDaoInterface (仅 `insert`, 见 agents/models/NoteDaoInterface.ets), 2-adapter 真实 seam (prod + test) |
| AiService | `entry/src/main/ets/services/AiService.ets` | 不是工具 — **AI 能力的 UI 入口** | capture / analyzeImage / captureText 三入口; UI→pipeline 的桥 |
| AgentChatService | `entry/src/main/ets/services/AgentChatService.ets` | 不是工具 — 对话编排服务 | 消费 LLM 层 + AgentMemoryService + AiService |
| AgentMemoryService | `entry/src/main/ets/services/AgentMemoryService.ets` | 不是工具 — 记忆服务 (但自身是 AI 写库路径②) | LlmGuard + 2 DAO |
| ImageUriResolver | `entry/src/main/ets/services/ImageUriResolver.ets` | 不是工具 — capture 前置基建 | file:// URI → 沙箱路径 |
| UiDataCacheService | `entry/src/main/ets/services/UiDataCacheService.ets` | 不是工具 — 读侧快照缓存 | 版本化快照, 无写库 |
| NoteEditService | `entry/src/main/ets/services/NoteEditService.ets` | 不是工具 — 用户编辑落库 | 静态 upsert (insert/update 二选一) |
| OverlayService | `entry/src/main/ets/services/OverlayService.ets` | 不是工具 — 浮层调度 | UI 服务 |
| DatabaseHelper | `common/src/main/ets/DatabaseHelper.ets` | 不是工具 — RDB 单例基建 | 建表 + getStore/init |
| LlmClient / LlmGuard / LlmConfig | `common/src/main/ets/llm/` | 不是工具 — LLM 能力层 (统计口径见 §3.2) | 无工具选择机制, 全部硬编码调用 |
| ContentExcerptBuilder / ContentProtocol | `common/src/main/ets/render/` | 不是工具 — MM-MD-v1 渲染基建 | 人 (UI) 用, 非 agent 可选 |
| LatexRiskNormalizer / FileUriUtils / uuid / confidenceSort / timeWindow / logger | `common/src/main/ets/utils/` | 不是工具 — 纯函数基建 | 共享工具函数 (utils), 无运行时选择面 |
| OcrConfig | `common/src/main/ets/ocr/OcrConfig.ets` | 不是工具 — OcrTool 的配套配置单例 | endpoint/mode preferences |
| FormAbility | `cardservice/src/main/ets/formability/FormAbility.ets` | 不是工具 — 卡片数据源 (mock) | FormCardFacade 的未来消费点 |

### 3.9 scripts/ — 开发工具链 (单列, 不算 agent 工具)

[scripts/](../../scripts/README.md) 全部是 CI/开发工具: arkts-lint (AST 引擎, 34 规则 / 89 单测, CI 守门)、naming-lint、link-check、audit-arkts-strict.mjs (v1 regex)、lint-arkts-*.bat/sh 包装。它们服务于**开发 agent (AI 编码助手) 与人**, 不进入 MindTrace app 运行时, 因此不计入本清单的工具面。若未来做"开发 agent 工具清点", 本节是起点。

## 4. 与起点线索的复核差异

| 起点线索 | 复核结果 |
|---|---|
| OcrTool 是全仓唯一 *Tool 类 | ✅ 成立 (entry/common/agents/skill/cardservice 范围内) |
| TypeClassifier 是 OcrTool 唯一调用方 | ❌ 修正: 还有 AiSettingsViewModel.ets:172 (设置页连通性测试) |
| DAO 共 4 个 | ✅ 成立 (Note / ChatMessage / AgentMemory / StudyPlan, 共 23 个公开方法) |
| LlmRequestBody 无 tools 字段 | ✅ 成立 (请求与响应两侧均不支持, 见 §3.2) |
| skill/Index.ets 只导出 SKILL_VERSION | ✅ 成立 (SkillAbility 亦为 TODO 占位) |
| 自研 OCR 服务经 OcrTool 以 HTTP 调 127.0.0.1:8000 | ✅ 成立, 但服务实际代码在 `tools/ocr_service/` (非根级 `ocr/`), 启动经 start.bat 内联组装 |
| AI 触发写库唯一路径 = generateNoteFromConversation | ❌ 修正: 共 3 条 (§3.3), 其中 2 条绕过 CaptureGraph 的 truth_check |

## 5. 缺口清单

1. **LLM 无 function-calling** (F1): 请求侧无 tools/tool_choice, 响应侧不解析 tool_calls — agent 无法让 LLM 选择工具; ADR-0010 预留的 `tools/` CRUD 层因此没有调用协议支撑, 直接开工只会复制 TypeClassifier 的硬编码模式
2. **CRUD 未工具化** (F1/F2): 23 个 DAO 方法全部由 Service/ViewModel 直接调用, 无 `tools/` 包装; AI 写库只能走 3 条硬编码路径, 无统一 schema 校验
3. **Kit 契约未接线** (F3): 3 个 facade 0 实现 0 消费, pipeline 无法安排提醒 / 后台任务 / 卡片回灌; 卡片仍在用 mock
4. **AI 写库路径不一致** (F2): 3 条路径三种校验强度 (truth_check / LlmGuard / 无), 且 StudyPlanViewModel 越层直写 DAO
5. **图片直接入库入口未接线**: `AiService.capture` 无调用方, 拍照流只到 analyzeImage (persist=false); 图片→KnowledgeUnit 直存需经对话显式意图 (产品决策还是缺口, 需队员确认)
6. **skill/ 未实装** (F4, 已裁决保留): 小艺 skill 接入预留位 — 缺的是实装计划与时间窗, 不是删除建议
7. **文档漂移** (F6): AGENTS.md OCR 启动命令失效
8. **"tools/" 一词两义** (F7): 仓库根 tools/ (python 服务) vs agents/src/main/ets/tools/ (CRUD 工具预留位), CONTEXT.md 未收录
9. **OcrTool 实例化散布** (F5): 3 处 `new OcrTool()`, 端点隐式依赖 OcrConfig 全局单例, 图节点测试需全局状态

## 6. 发现项 (按严重度) 与下一步建议

| 级别 | 发现项 | 建议下一步 |
|---|---|---|
| P1 | F1 LLM 层无 function-calling, tools/ 层无调用协议支撑 | **先立 spec 不写实现**: LlmTypes 增 tools/tool_choice + LlmResponse 增 tool_calls 解析 (OpenAI 兼容) + LlmGuard 上层工具执行循环 (ToolRegistry: name/description/JSON schema/execute); 这是 ADR-0010 预留位的前置条件。建议用 to-spec 流程立项 |
| P1 | F2 AI 写库 3 条路径、3 种校验强度, StudyPlanViewModel 越层直写 | 小步先修: StudyPlan 生成抽到 Service 层并复用 LlmGuard validator; AgentMemory 契约文档化; 长期并入 F1 的 tools/ CRUD schema 校验 |
| P2 | F3 Kit facade 0 实现 0 消费 (假设性 seam 腐烂风险) | 挑最小闭环接线: ReminderFacade (Home 已有 ReminderBanner), entry composition root 实现 + 注入; 按 ADR-0009 形状走 |
| P3 | F4 skill/ 预留位 (2026-09-06 裁决) | **保留** — 小艺 skill 开发预留, 不冻结不移除; 评估复赛前能否落 1-2 个最小 Intent 演示, 否则作为路线图叙事; 建议落 ADR 固化裁决理由 |
| P2 | F5 OcrTool 散布实例化 + OcrConfig 隐式全局依赖 | composition root 构造并注入 TypeClassifier/CaptureGraph (与 DispatchOptions.dao 同形状); 为 F1 ToolRegistry 铺路 |
| P3 | F6 AGENTS.md OCR 启动命令漂移 | 文档修正 (一行): 指向 tools/ocr_service/start.bat |
| P3 | F7 "tools/" 一词两义 | 用 domain-modeling 在 CONTEXT.md 增补词条 (区分根级 tools/ 与 agents 预留位) |
| P3 | F8 scripts/ 定位 | 已在本清单 §3.9 单列澄清; 无需代码动作 |
| P3 | `AiService.capture` 无调用方 | 找队员确认是产品决策 (意图门禁) 还是漏接线; 若是决策, 在 AiService 头注释标注现状 |

### 6.1 复赛阶段定位修订 (2026-09-06 增补)

项目已抵达鸿蒙高校创新赛**复赛阶段**, 工作模式从"架构能力建设"切换为"演示强化 + 平台特性得分 + 设计叙事"。据此对 §6 发现项做**日历优先级**修订 — 架构判断不变, 变的是先后:

| 复赛冲刺序 | 事项 | 说明 |
|---|---|---|
| 1 | 演示链路稳定性 | 真机 OCR 端点配置 (OcrConfig 已支持)、API key 流程、失败 fallback 演示脚本; 复赛前只修 demo-blocking 问题 |
| 2 | F3 ↑ ReminderFacade 真实接线 | 唯一能在演示中展示的 Kit 深度集成点 (NotificationKit ReminderAgent); ADR-0009 所说的 "later window" 就是现在 |
| 3 | F1 spec-only | 工具调用协议 spec (不写实现) — 强化 "AI agent 工具化路线图" 的设计透明度叙事 |
| 4 | F4 保留 + 评估最小演示 | 小艺 skill 预留位不动; 若平台接入窗口允许, 复赛前落 1-2 个最小 Intent 演示, 否则作为路线图叙事 |
| 赛后 | F2 / F5 / F6-F8 | 动已工作代码的回归风险 > 复赛收益; F5 并入 F1 的 ToolRegistry; 文档项 (F6/F7) 顺手修 |

**定位声明 (复赛叙事)**: MindTrace = 鸿蒙端侧的"拍照 → OCR → AI 分类 → 知识结构化 → 复习"全链数学学习助手; 复赛三大支柱 = ① AI 全链自研 (Dispatcher + CaptureGraph, F1 spec 补上 agent 工具化路线图) ② 平台特性集成 (ReminderFacade 真实接线 + 小艺 skill 路线图) ③ 严格 ArkTS 工程化 (arkts-lint CI + ADR/spec 体系, 本清单即证)。

**复赛版 Top recommendation** 与 §6 架构建议不冲突: F1 spec 仍是第一架构动作, 但日历上排在演示稳定性与 F3 接线之后。

**Top recommendation**: 先做 F1 的 spec (工具调用协议), 理由: 它是 ADR-0010 预留位与 F2 长期解的共同前置, 且零实现成本即可让"CRUD 工具层"从口号变成可评审的设计。次优先: F2 的 StudyPlan 越层直写 (改动小、独立可落)。

## 7. 本次体检的写入边界

- 只读扫描: agents/ common/ entry/ skill/ cardservice/ tools(ocr_service)/ scripts/ 五模块 + 服务 + 工具链; 未修改任何业务代码与既有文档 (AGENTS.md / CONTEXT.md 的修正仅记录为发现项 F6/F7)
- 本文件为唯一仓库写入, 位于 `docs/architecture/` (新建目录); HTML 报告不入 git ([html-in-docs 决策树](../style/html-in-docs.md))
- 分支: `feature/agent-tools-inventory-2026-09-06` → 目标合入 `develop` (PR 由人工发起, 遵守红线: 不自动 push)
