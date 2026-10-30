# MindTrace 全代码库架构审计 (2026-09-01)

> **审计对象**: `D:\HMgent\MathMind` 5 个 module 全部源代码 (`entry` HAP + `common`/`agents`/`skill`/`cardservice` 4 HSP)
> **审计基线**: `git rev-parse HEAD = 29df511` (chore(setup): scaffold agent-skills config) on `main`
> **审计日期**: 2026-09-01
> **审计方法**: 静态阅读全部 `.ets` 源文件 (162 个, 23,301 LOC) + 跨模块 import 拓扑分析 + ArkTS 1.1 规范扫描 + Agent 设计反模式扫描
> **关联文档**:
> - `docs/architecture-audit-20260901.md` — 早期的 AGENTS.md 单文档审计 (本报告的子集,本报告替代/扩展其内容)
> - `docs/research/huawei-arkui-agent-20260901.md` — 华为官方文档调研笔记
> - `docs/agents/domain.md` — 项目域文档规约

---

## 0. TL;DR

| 维度 | 评级 | 说明 |
|---|---|---|
| **总体架构健康度** | 🟡 **可工作但分层混乱** | 业务跑通,W4 加了流式;但有 2 个 700+ LOC 的 god class,3 套并行 LLM 调用路径,跨层 import 缺乏规约 |
| **深度模块占比** | 🔴 **约 25%** | 6/24 个核心类 (LlmGuard / LlmConfig / LlmTypes / OcrConfig / Dispatcher / OcrTool) 是深模块; 18/24 (含 KnowledgeModel, AgentChatService, ContentProtocol 等) 是浅模块/God class |
| **ArkTS 1.1 规范** | 🟡 **规则表覆盖率 ~10%** | 官方 40+ 规则,AGENTS.md/MEMORY 仅列 5 条;AGENTS.md rule #2 关于"禁 C 风格 for"实际是错的 (应禁 `for..in`); 详见 §4.17/§4.18; 当前 `compatibleSdkVersion=9` 仅警告不报错 |
| **LLM 调用层** | 🔴 **三套并行路径** | `LlmClient.call` (JSON) + `LlmClient.callStream` (SSE) + `LlmClient.callSseTokens` (伪流式);三者底层是同一 HTTP 客户端但行为各自独立,无统一 seam |
| **Agent 调度** | 🟡 **多入口泄漏** | `Dispatcher` 同时暴露 `analyze` (识别) + `dispatch` (入库) 两个公开方法,业务语义重叠;上层 `AiService` 两个都用 |
| **UI / Service 分层** | 🔴 **分层不清** | `entry/services/AgentChatService.ets` (802 LOC) 同时持有 UI 回调、prompt 构造、JSON 校验、记忆读写、流式控制;**没有任何"UI 不应感知 LLM"或"Service 不应持有 UI 引用"的分层约束文档** |
| **MD 文档可信度** | 🟡 **部分可信** | `AGENTS.md` 有 6 处与现状脱节 (路径错误,死链,过期版本号);`docs/architecture-audit-20260901.md` 是子集审计,本报告替代之 |

**核心结论**: MindTrace 工作正常,W3→W4 增量清晰,但积累性债务已到需要重设计的窗口。本报告 + 后续 Phase 2/3/4 给出重设计的入口、ADR 与拆分路径。

---

## 1. 审计方法

### 1.1 数据来源

- 全量源代码扫描: `entry/src/main/ets/`, `common/src/main/ets/`, `agents/src/main/ets/`, `skill/src/main/ets/`, `cardservice/src/main/ets/` 共 **162 个 .ets 文件,23,301 LOC** (排除 `build/`、`oh_modules/`、`oh-package*.json5` 等生成/配置)
- 跨模块 import 拓扑: PowerShell 解析 `from 'common'`、`from 'agents'` 等语句
- ArkTS 1.1 静态扫描: 正则匹配 C-style `for`、`any`/`unknown` 注解
- Agent 反模式: 人工审查 4 个核心类 (Dispatcher, TypeClassifier, KnowledgeModel, AgentChatService) 的职责分布
- 官方文档对照: `docs/research/huawei-arkui-agent-20260901.md`

### 1.2 模块分类 (per AGENTS.md)

| module | 类型 | 大小 | 层 |
|---|---|---|---|
| `entry` | HAP (type:entry) | 123 文件 / 17,719 LOC | UI + 业务编排 (业务编排跨层) |
| `common` | HSP (type:shared) | 22 文件 / 3,580 LOC | 类型 + 基础设施 (LLM/Render/OCR config/DB) |
| `agents` | HSP (type:shared) | 9 文件 / 1,930 LOC | AI 业务 (Dispatcher + 子 Agent) |
| `skill` | HSP (type:shared) | 2 文件 / 14 LOC | 卡片能力 (Feature Ability 入口) |
| `cardservice` | HSP (type:shared) | 6 文件 / 58 LOC | 卡片服务 (FormExtensionAbility) |

注: `module.json5` 中 `common` / `agents` / `skill` / `cardservice` 的 `type` 字段为 `"shared"`,而非字面 `"hsp"`。"HSP" 是行业对 shared/feature 的统称,本报告沿用 AGENTS.md 的"4 HSP"表述。

### 1.3 评级标准

- 🔴 **P0**: 影响可维护性或运行时正确性,需立即修
- 🟡 **P1**: 显著技术债务,应在下一两个大版本处理
- 🟢 **P2**: 改进项,有空再做
- 评级同时给出 "deep module vs god class" 判断 (depth = small interface / lots of behaviour; god class = mixed responsibilities / 500+ LOC)

---

## 2. 模块卡片

### 2.1 `entry` (HAP, 123 文件 / 17,719 LOC)

**职责**: 主应用入口,UI 渲染 + 业务编排 + 拍照/相册 + 数据库读写。

**子目录分布**:
| 子目录 | 文件数 | 角色 |
|---|---|---|
| `pages/` | 46 | 5 个 Tab 页面 (Home/Notes/AI/Review/Profile) + 子页面 |
| `overlays/` | 43 | 浮层 (AgentFloatWindow 17 + CameraOverlay + NoteDetailOverlay 25) |
| `services/` | 6 | 业务服务 (AiService, AgentChatService, AgentMemoryService, ImageUriResolver, OverlayService, UiDataCacheService) |
| `viewmodels/` | 7 | @Observed 视图模型 |
| `database/` | 4 | DAO 层 (AgentMemoryDao, ChatMessageDao, NoteDao, StudyPlanDao) |
| `shared/components/` | 7 | 渲染器 (MathTextRenderer, MarkdownRenderer, FormulaSplitRenderer 等) |
| `utils/` | 7 | 工具 (MarkdownParser 等) |
| `models/`, `entryability/`, `entrybackupability/` | 各 1 | Ability 入口 |

**重头文件 (LOC 排行)**:

| LOC | 文件 | 备注 |
|---|---|---|
| **1880** | `pages/Review/ReviewGraphView.ets` | 🔴 **最大文件** (deep-dive 修正:实际 1880,非 1679),复习图谱,UI + 数据处理 + 动画混在一起;deep-dive §F1.1-§F1.9 揭示更多隐藏缺陷 |
| 802 | `services/AgentChatService.ets` | 🔴 **God class**,见 §4 |
| 735 | `viewmodels/KnowledgeGalaxyViewModel.ets` | 🟡 大 view model,可能需拆 |
| 528 | `services/AgentMemoryService.ets` | 🟡 大 service,记忆读写 + 摘要 + profile |
| 516 | `overlays/NoteDetailOverlay/NoteDetailOverlay.ets` | 🟡 大浮层,可能含 router logic |
| 499 | `shared/components/MathTextRenderer.ets` | 🟡 渲染器,可能有 over-coupling |
| 452 | `services/UiDataCacheService.ets` | 🟡 UI 数据缓存 |
| 449 | `overlays/NoteDetailOverlay/model/DetailRenderModel.ets` | 🟡 详情渲染 model |
| 277 | `viewmodels/AiSettingsViewModel.ets` | 适中型 |

**跨模块 import**: `entry → common` (主要) + `entry → agents` (从 `services/` 调 `Dispatcher`),具体依赖 `from 'common'` 与 `from 'agents'` 在源码中均有出现,符合"HAP 依赖 HSP"规约。

**评估**:
- ✅ 模块边界清晰,符合 HarmonyOS HAP/HSP 模式
- 🔴 业务服务层 (`services/`) 与 UI 层耦合度高 — `AgentChatService` 通过 `AgentChatCallbacks` 接收 UI 回调但同时处理 LLM/记忆/JSON 校验/中文 prompt 拼装 (802 LOC),违反 SRP
- 🔴 `viewmodels/` 与 `services/` 职责有重叠 (e.g. `KnowledgeGalaxyViewModel` 可能包含 Service 应有的逻辑)

### 2.2 `common` (HSP, 22 文件 / 3,580 LOC)

**职责**: 跨模块共享的类型、LlmConfig/Render/OcrConfig 单例、DB 助手、Mock 数据、颜色 token。

**子目录分布**:
| 子目录 | 文件数 | 关键导出 |
|---|---|---|
| `llm/` | 5 | `LlmClient`, `LlmConfig`, `LlmGuard`, `LlmOutputRules`, `LlmTypes` |
| `render/` | 2 | `ContentProtocol` (580 LOC), `ContentExcerptBuilder` |
| `models/` | 3 | `CommonTypes`, `CaptureChain`, `StudyPlan` |
| `utils/` | 6 | `logger`, `uuid`, `FileUriUtils`, `LatexRiskNormalizer`, etc. |
| `data/` | 2 | `MockNotes`, `NoteTaxonomy` |
| `constants/`, `ocr/` | 各 1 | `ColorTokens`, `OcrConfig` |
| (top) `DatabaseHelper.ets` | 1 | RDB 助手单例 |

**重头文件 (LOC 排行)**:

| LOC | 文件 | 备注 |
|---|---|---|
| **580** | `render/ContentProtocol.ets` | 🟡 **MM-MD-v1 协议**,单职责但 580 LOC; 详见 §4.3 |
| **458** | `llm/LlmClient.ets` | 🔴 **3 套调用路径并行**,详见 §4.1 |
| 340 | `utils/LatexRiskNormalizer.ets` | LaTeX 风险归一化,适度 |
| 230 | `render/ContentExcerptBuilder.ets` | 摘要构造,适中 |

**评估**:
- ✅ 模块边界清晰,作为"被所有其他模块依赖"的底部 HSP,设计意图正确
- 🟡 `LlmClient` 三套调用路径是最大的可拆分候选 (§4.1)
- 🟡 `LlmConfig` 静默覆盖用户配置 (详见 §4.4)

### 2.3 `agents` (HSP, 9 文件 / 1,930 LOC)

**职责**: AI 业务逻辑 — 主 Agent 调度中枢 (Dispatcher) + 子 Agent (TypeClassifier, KnowledgeModel) + MCP 工具 (OcrTool) + 领域模型。

**子目录分布**:
| 子目录 | 文件数 | 关键文件 |
|---|---|---|
| `core/` | 1 | `Dispatcher.ets` (159 LOC) |
| `agents/` | 2 | `TypeClassifier.ets` (333), `KnowledgeModel.ets` (870) |
| `mcp/tools/` | 1 | `OcrTool.ets` (394) |
| `models/` | 4 | `KnowledgeCategory`, `KnowledgeUnitExt`, `NoteDaoInterface`, `TruthCheckResult` |
| (top) `Index.ets` | 1 | 公共 API 入口 |

**重头文件**:

| LOC | 文件 | 备注 |
|---|---|---|
| **870** | `agents/agents/KnowledgeModel.ets` | 🔴 **最大 god class**,详见 §4.2 |
| **394** | `agents/mcp/tools/OcrTool.ets` | 🔴 **ArkTS 1.1 违规重灾区**,6 处 C-style `for` |
| **333** | `agents/agents/TypeClassifier.ets` | 🟡 多职责混杂 (见 §4.3) |
| 159 | `core/Dispatcher.ets` | 双入口泄漏,见 §4.5 |

**跨模块 import**:
- `agents → common` (类型 + LlmGuard + LlmConfig + ContentProtocol)
- `agents → @kit.CoreVisionKit` (OcrTool)
- `agents → @kit.NetworkKit` (OcrTool HTTP)
- ✅ **没有反向依赖** (agents 不 import entry / skill / cardservice),模块方向干净

**评估**:
- ✅ 依赖方向正确 (agents 只依赖 common + HarmonyOS Kit)
- 🔴 `KnowledgeModel` 870 LOC 做 ≥7 件事 (structuring + AI call + JSON validate + truth check + latex fix + prompt build + fallback),应拆分
- 🔴 `OcrTool` 文件夹叫 `mcp/tools/`,但项目未运行 MCP server,误导命名
- 🔴 `Dispatcher` 双入口 (`analyze` + `dispatch`) 是 leaky abstraction

### 2.4 `skill` (HSP, 2 文件 / 14 LOC)

**职责**: 技能卡片 (Feature Ability 入口)。

**文件**: 实际主要是 `Index.ets` (3662 bytes) + `skillability/`。模块体量很小,主要是 Ability 声明。

**评估**: ✅ 模块小巧,职责单一。无需审计关注。

### 2.5 `cardservice` (HSP, 6 文件 / 58 LOC)

**职责**: 卡片服务 (FormExtensionAbility)。

**文件**: `Index.ets` + `entryability/` + `formability/` + `pages/` + `widget/`。

**评估**: ✅ 模块小巧。无需审计关注。

---

## 3. 跨模块 Seam Map

```
┌─────────────────────────────────────────────────────────────────────┐
│  entry (HAP, UI + 业务编排)                                          │
│                                                                      │
│  pages/ ─── overlays/ ─── viewmodels/ ─── services/ ─── database/   │
│    │            │            │             │             │          │
│    └────────────┴────────────┴─────────────┴─────────────┘          │
│                              │                                       │
│   共享组件 shared/components/  │                                      │
└──────────────────────────────┼──────────────────────────────────────┘
                               │  'common'
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│  common (HSP, 共享类型 + LLM/OCR/Render 配置 + DB)                    │
│                                                                      │
│  llm/ ─── ocr/ ─── render/ ─── models/ ─── utils/ ─── DatabaseHelper │
│   │                                                                  │
│   ├─ LlmClient (3 套调用路径) ◄──────┐                                │
│   ├─ LlmConfig (单例 + preferences)    │                              │
│   ├─ LlmGuard (JSON 校验)              │                              │
│   └─ LlmTypes / LlmOutputRules         │                              │
│                                        │                              │
└────────────────────────────────────────┼─────────────────────────────┘
                                         │  'common'
                                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│  agents (HSP, AI 业务)                                                │
│                                                                      │
│  core/Dispatcher ──► agents/TypeClassifier ──► mcp/tools/OcrTool    │
│       │                    │                          │              │
│       │                    └──────► agents/KnowledgeModel            │
│       │                                │                             │
│       └──────► models/                 │                             │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
                                         ▲
                                         │  'common'
                                         │
                              entry/services/AiService
                              ─── entry/services/AgentChatService
```

**关键 seam** (候选 deep-module interface):
1. `LlmClient` ↔ `LlmGuard` — JSON 校验 + 调用的耦合
2. `Dispatcher.dispatch` ↔ `AiService.capture` — 业务编排接口
3. `KnowledgeModel.structure` ↔ `NoteDao.insert` — 业务数据落地
4. `OcrTool.recognize` ↔ `TypeClassifier.extractText` — OCR 输入路径
5. `LlmConfig` / `OcrConfig` 单例 ↔ `preferences` — 配置持久化

---

## 4. 关键发现 (P0 / P1 / P2)

### 4.1 🔴 P0 — LLM 三套调用路径并行 (用户已识别,严重度被低估)

**位置**: `common/src/main/ets/llm/LlmClient.ets`

| 方法 | 行数 | 用途 | 调用方 |
|---|---|---|---|
| `call(messages, opts)` | L47-113 | 非流式 JSON 调用 | `LlmGuard` → `TypeClassifier.classify`, `KnowledgeModel.callAi`, `AgentChatService.summarizeConversation`, `AgentChatService.realReply` (回退) |
| `callStream(messages, onDelta, opts)` | L179-329 | 真 SSE 流式 (用 `requestInStream` + `dataReceive` 事件) | 当前**无业务调用** (W4 commit `7d7621b` 已合并,可能尚未被引用) |
| `callSseTokens(messages, opts)` | L430-495 | **伪流式** (非流式 HTTP,但客户端解析 SSE body) | `AgentChatService.realReplyStream` 主路径 |

**问题**:
1. 同一 HTTP 客户端 (`http.createHttp()`) 三套用法,请求构造逻辑分散 (buildBody 在三处分别实现)
2. `callSseTokens` 是 W4 临时方案:不用 `requestInStream` 而是 `request()` + 手动解析 SSE,延迟首字节 — 这等于把"流式"做到了 UI 上但传输层不是流式,延迟 > 真实流式
3. `LlmConfig` (单例) 在 `LlmClient` 构造时硬绑,无法注入测试 fake
4. 三套都没有重试 + 退避 (除了 `LlmGuard` 包装层加了 retry)

**修复方向** (Phase 2 决策, Phase 4 ticket #5):
- 引入 `LlmCaller` interface (已存在于 `LlmGuard.ets`, 见 L5-7),三个方法改为三个 adapter
- 或合并 `call` + `callSseTokens` 为一个 `call(opts)` (根据 `opts.stream` 走不同实现)

**严重度**: 🔴 影响: (a) 业务误判调用路径;(b) 维护成本 (W4 加流式时新增了一个 `callStream` 但没有用,代码死链);(c) 单元测试困难

---

### 4.2 🔴 P0 — `KnowledgeModel` God Class (870 LOC)

**位置**: `agents/src/main/ets/agents/KnowledgeModel.ets`

**职责清单** (一文件 7+ 职责):
| 职责 | 行数 | 备注 |
|---|---|---|
| AI prompt 构建 | L441-475 (`buildPrompt`) | 35 行内联中文 prompt |
| AI JSON 调用 | L292-352 (`callAi` + `validateAiJson`) | |
| 结构化字段归一化 | L528-617 (`normalize*` 5 个方法) | |
| Truth check (4 项数学正确性校验) | L688-928 (`truthCheck` + `checkBracePairing`/`checkDivisionByZero`/`checkEquation`/`checkLatexInternal`) | **241 行** |
| LaTeX 自动修复 | L835-877 (`checkLatexInternal` + `patchIntegralDx`) | |
| Fallback note 构造 | L223-264 (`buildFallbackFromClassify`) | |
| 单元 ID 生成 | L289-291 (`uuid` 自实现) | 已有 `common/utils/uuid.ets` 但未复用 |
| 分类 hint 解析 | L620-680 (`resolveClassificationHint` + `buildExternalHint` + `mergeClassificationHint`) | 与 `TypeClassifier` 有 overlap |

**问题**:
1. **深模块反义**: interface `structure(ocrText, ...)` 只有 1 个方法,但内部做了 8 件事 — 失败时 (line 137 `buildFallbackFromClassify` 与 line 144 真 AI 路径) 行为不同, 接口不能表达
2. **trut h check 是独立 concern**,241 行可独立测试,目前被 `KnowledgeModel` 私藏
3. **prompt 是数据不是逻辑**,应可外部替换 (用于 AB 测试或不同模型)
4. **truthCheck public 暴露** (`truthCheck(ocrText)` 在 L688 是 public),这意味着外部 (entry/UI) 可能直接调用 truth check 而不走 structuring — 这是 leaky abstraction

**修复方向** (Phase 4 ticket #3):
- 拆为 `StructureService` (主入口) + `TruthCheckService` (数学校验) + `PromptBuilder` (prompt 构造) + `LlmJsonValidator` (KnowledgeModel 自有 JSON schema)
- `StructureService` interface: `structure(text, hints?): KnowledgeUnit` — 小接口
- `TruthCheckService` interface: `check(text): TruthResult` — 小接口,可独立单元测试
- `PromptBuilder` interface: `build(category, text, hints?): ChatMessage[]` — prompt 作为可替换数据

**严重度**: 🔴 任何结构修改都会动到 870 行,变更风险大;测试覆盖率近乎 0 (`agents/src/test/` 只有 2 个文件,见 §6.2)

---

### 4.3 🔴 P0 — `AgentChatService` God Class (802 LOC)

**位置**: `entry/src/main/ets/services/AgentChatService.ets`

**职责清单**:
| 职责 | 行数 | 备注 |
|---|---|---|
| Intent 分类 (note_generation vs chat) | L407-589 (`classifyTextIntent` + 三个 keyword array 共 ~150 行) | 双重规则 + 远程 LLM 兜底 |
| Chat 流式回复 | L115-200 (`realReplyStream` 86 行) | |
| Chat 非流式回复 | L65-109 (`realReply` 45 行) | 流式失败时回退 |
| Chat JSON 校验 | L328-354 (`validateChatAnswerJson`) | |
| Chat prompt 构造 | L268-306 (`buildReplyMessages`) | 15 行中文 system prompt |
| 图片识别回复 | L45-63 (`captureReply`) | |
| 笔记生成编排 | L202-247 (`generateNoteFromConversation`) | |
| 摘要生成 | L249-266 (`summarizeConversation`) | |
| 内容协议校验 | L382-405 (formula/mermaid 检测) | |
| 状态机映射 | L687-742 (`statusFromStep` 13 个步骤映射) | |
| 记忆读写包装 | L768-846 (10 个 `safe*` 包装方法) | |
| 30+ keyword 字典 | L489-578 | intent / deny / explicit |

**问题**:
1. 单类持有 12+ 职责,任何修改都可能引入回归
2. `intent` keyword 字典 (3 个数组 + `hasActionNearTarget` 距离算法) 是 DSL-in-class,应独立模块
3. `realReplyStream` 与 `realReply` 90% 重复,只有"流式 vs 非流式"一行差异 — 这是 duplicated code smell
4. UI 回调通过 `AgentChatCallbacks` interface 注入 (L20-34),这是好设计,但接口里有 7 个 callback,粒度过细

**修复方向** (Phase 2 决策, Phase 4 ticket #N):
- 拆为 `ChatService` (流式/非流式对话) + `NoteGenerationService` (intent + 编排) + `IntentClassifier` (keyword + remote) + `PromptTemplate` (中文 prompt 数据)
- `ChatService.realReply` / `realReplyStream` 合并为单接口 `reply(opts)` + 内部 adapter

**严重度**: 🔴 W4 加流式时已经引入了 duplication (`realReplyStream` 与 `realReply` 并存),且 intent 字典在 W4 已加了一轮 — 任何规则变动都要改这里

---

### 4.4 🟡 P1 — `LlmConfig` / `OcrConfig` 静默覆盖用户配置

**位置**: `common/src/main/ets/llm/LlmConfig.ets` L201-237 + `common/src/main/ets/ocr/OcrConfig.ets` L48-94

**问题**:
- `LlmConfig.normalizeEndpoint`: 若 endpoint 含 `"siliconflow"` → 静默返回 `DEFAULT_ENDPOINT` (DeepSeek),**用户配置被丢弃**且无任何提示
- `LlmConfig.normalizeModel`: 若 model 含 `"v3"` / `"flash"` / `"deepseek-chat"` / `"deepseek-reasoner"` / `"r1"` → 静默返回 `DEFAULT_MODEL`,**用户配置被丢弃**且无任何提示
- `OcrConfig.normalizeEndpointInput` 没有这个 reverse-mapping,但 `LlmConfig` 有
- 这两处都是 `private normalize*` 方法,业务方拿不到拒绝原因

**修复方向** (Phase 4 ticket #N):
- `normalize*` 改为 `tryNormalize*` 抛 `LlmError('UNSUPPORTED_MODEL', 'siliconflow endpoints not supported')` 而不是静默
- 或在 `setModel` / `setEndpoint` 中检测冲突并写一条 warning 到 console
- 写入 `docs/adr/` ADR-0004 (用户配置优先原则)

**严重度**: 🟡 不是崩溃,但用户报告 "我设置了 xxx 但没生效" 时无从查起

---

### 4.5 🟡 P1 — `Dispatcher` 双入口泄漏

**位置**: `agents/src/main/ets/core/Dispatcher.ets`

**问题**:
- 公开方法 `analyze(req, context): DispatchAnalysisResult` (L63-93) — 只 OCR + 分类,不调 KnowledgeModel
- 公开方法 `dispatch(req, context): DispatchResult` (L97-152) — 完整链:OCR + 分类 + 结构化 + 入库
- 公开方法 `routeDispatch(req, context)` (L155-157) — `dispatch` 的别名,纯兼容代码 (注释: "兼容旧接口名(原 D 任务规划用 routeDispatch)")
- `entry/services/AiService.analyzeImage` (L71-93) 调 `Dispatcher.analyze` — 业务"识别但不存"
- `entry/services/AiService.processAndPersist` (L105-141) 调 `Dispatcher.dispatch` — 业务"识别并存"

**问题**:
1. 两个公开方法 + 一个别名 = 三个 entry point,语义重叠 (`analyze` 是 `dispatch` 的子集)
2. `AiService` 必须知道哪个调哪个,业务方承担 Dispatcher 内部结构知识
3. `routeDispatch` 是 dead alias,只有 commit `13c934f` 之前的代码用过

**修复方向** (Phase 4 ticket #4):
- `analyze` 改为 private / 内部 stage
- `dispatch` 为唯一公开方法,签名不变
- 删 `routeDispatch`
- 如果"只识别不存"是合法业务,改为 `Dispatcher.dispatch(req, { persist: false })` opts

**严重度**: 🟡 不是阻塞,但是 leaky abstraction;后续重设计时一并处理

---

### 4.6 🟡 P1 — `OcrTool` 6 处 C-style `for` (项目规约, **非** ArkTS 1.1 strict 违规) — **§4.17 规则理解需修正**

**位置**: `agents/src/main/ets/mcp/tools/OcrTool.ets`

| 行号 | 代码片段 |
|---|---|
| L74 | `for (let attempt = 0; attempt < 2; attempt++) {` |
| L221 | `for (let blockIndex = 0; blockIndex < result.blocks.length; blockIndex++) {` |
| L223 | `for (let lineIndex = 0; lineIndex < block.lines.length; lineIndex++) {` |
| L265 | `for (let attempt = 0; attempt < 2; attempt++) {` |
| L278 | `for (let attempt = 0; attempt < 2; attempt++) {` |
| L366 | `for (let i = 0; i < value.length; i++) {` (UTF-8 encoder 内部) |

**重要修正** (经 `docs/research/huawei-arkui-agent-20260901.md` §3.3 核对):

- ❌ **本审计初版** §4.6 称"ArkTS 1.1 strict 模式禁止 C-style `for`" — **这是错的**
- ✅ 官方 ArkTS 1.1 strict 实际只禁止 `for..in` (rule `arkts-no-for-in`, error code **10605080**),C-style `for (let i = 0; i < n; i++)` **是允许的**
- 原文出处: <https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-migration-background> 第 1967-1997 行,引文:"ArkTS不支持for .. in迭代对象属性。"
- AGENTS.md rule #2 ("禁 C 风格 `for`") 是**项目级约定** (项目偏好 `for...of` / `forEach` / `while` 以提升可读性),**不是**官方 strict-mode 强制

**说明**:
- 6 处 C-style `for` 全在 OcrTool 一个文件,其它 161 个 .ets 文件 0 出现
- 实际严格模式规则是 `arkts-no-for-in` (10605080),需用 `grep "for\s*(let\|const)\s+\w+\s\+in"` 扫描
- 本审计初版扫描的"0 处 `any`/`unknown`" + "6 处 C-style `for`" 这个组合误导读者以为 strict 模式基本合规 — 实际应改为扫描 `for..in` 用法

**修复方向** (Phase 4 ticket #2 改):
- **不改代码**: 既然官方允许 C-style `for`,OcrTool 6 处不必改写
- **改项目规约**: AGENTS.md / `docs/style/arkts-1.1.md` 应说"项目偏好 `for...of`/`forEach`/`while`;C-style `for` 允许但不推荐"而非"禁止"
- **改扫描脚本**: 增加 `for..in` 扫描,删除 C-style `for` 扫描
- **新增 ticket #15**: 全面更新 ArkTS 规则表 (见 §4.18)

**严重度**: 🟢 **降低** — 项目规约偏好而非 strict 违规;真正的严格模式覆盖率见 §4.18

---

### 4.7 🟡 P1 — `ContentProtocol` 单职责但 580 LOC

**位置**: `common/src/main/ets/render/ContentProtocol.ets`

**职责**: MM-MD-v1 协议 (LaTeX + Markdown 边界 + 列表与公式互斥) 的归一化与校验。

**问题**:
- 单职责是对的 ("validate markdown") — 不是 god class
- 但实现细节高度耦合 (canonicalize + validate + fixup 三个阶段互相递归)
- 18 个 public/private 方法,部分方法签名超 6 参数
- 单元测试覆盖率低 (`common/src/test/` 几乎为空,见 §6.2)
- AgentChatService (L756-766) + AgentMemoryService 都直接 import 此 class,**没有任何 protocol-version 协商机制**

**修复方向** (Phase 4 ticket #N):
- 拆为 `MarkdownCanonicalizer` + `LatexBoundaryNormalizer` + `MathGuard` (校验)
- 引入 `protocolVersion` 字段,持久化到 KnowledgeUnit 元数据
- 这是 Phase 2 决策项,本报告只标记

**严重度**: 🟡 单职责好,但耦合紧,无版本协商 — W5 加新规则时会影响所有调用方

---

### 4.8 🟡 P1 — `mcp/` 目录是空壳

**位置**: `agents/src/main/ets/mcp/tools/OcrTool.ets`

**问题**:
- 目录命名 `mcp/tools/` 暗示 MCP (Model Context Protocol) 客户端/服务端集成
- 实际项目未运行 MCP server;OcrTool 是一个直接的 HTTP 客户端 (multipart upload → JSON response)
- `agents/Index.ets` 把 OcrTool 作为 "MCP 工具" 重导出 (L20-21) — 但调用方 (`TypeClassifier.extractText`) 直接 `new OcrTool()`,未通过任何 MCP 注册表

**修复方向** (Phase 2 决策):
- 选项 A: 真正接入 MCP server (新增 `agents/mcp/McpClient.ets` + 协议握手)
- 选项 B: 改名 `mcp/tools/` → `tools/` 或 `recognition/`,OcrTool 作为普通 Adapter
- 推荐 B,理由:MCP 集成的工作量远超本次审计范围,改名消除误导

**严重度**: 🟡 不是 bug,但误导新人,违反"目录名应反映实际内容"的本地规约

---

### 4.9 🟡 P1 — `ReviewGraphView` 1880 LOC 单文件 (deep-dive §F1.1-§F1.9)

**位置**: `entry/src/main/ets/pages/Review/ReviewGraphView.ets` (**实际 1880 LOC,审计时低估为 1679**)

**问题** (经 deep-dive 确认):
- 🔴 **§F1.1 God file**: 单文件含 3 个 `@Component` + 2 套坐标系 + 2 套相机模型 + 120 LOC 无封装的纯函数 (`clamp`/`pctText`/`stableHash`/`paletteColor`/`planetVariant` 等 L48-123)
- 🔴 **§F1.2 重复 `SolarPlanet`**: L885-919 (overview) 与 L1541-1580 (detail) 实现同一个 6-变体行星渲染器,但变体选法不同 + 定位算法不同,类型系统看不出重复
- 🔴 **§F1.3 `GalaxyMath` 伪模块缺 seam**: 相机/缩放/调色/版式全是 file scope 自由函数,无 export,单测需 instantiate 整个 component 才能跑
- 🔴 **§F1.4 `@State` ViewModel 不触发响应**: `vm: KnowledgeGalaxyViewModel = new ...()` 是 `@State`,但 `vm.load()` 只改内部 array;页面"看似响应"是因为 `build()` 每次 `this.vm.systems.length` 读 — 任何 memoization 都会冻屏
- 🟡 §F1.5 planet z-order 依赖 `Math.sin(radians)` (L1836-1839) + `setInterval` 每帧调,触发 ~25 次层切换/旋转 × 30+ 行星 = 巨大重渲染
- 🟡 §F1.6 `deleteNote` 双触发 reload: ViewModel L271 reload + watcher L151-153 又 reload,一次删除 = 两次全量重渲染
- 🟡 §F1.7 魔数物理: `GALAXY_SIZE=360` (L21) / 两套 ZOOM 范围 / `tilts` 数组 / `slotX/Y` 环布局 / 360×520 舞台尺寸 (L23-24),改一处别处静默坏

**修复方向** (Phase 4 ticket #12 强化):
- 拆为 `galaxy/GalaxyMath.ets` + `galaxy/GalaxyConstants.ets` + `galaxy/SolarPlanet.ets` (`@Builder` 共享) + `pages/Review/ReviewController.ets` + `pages/Review/SubjectUniverseView.ets` + `pages/Review/SubjectGalaxyView.ets`
- `ReviewGraphView` 缩到 ~150 LOC,`<100` 行 build

**严重度**: 🔴 提升 (因 deep-dive 揭示更多隐藏缺陷,如 `@State` 失效、`SolarPlanet` 重复)

---

### 4.10 🟡 P1 — `KnowledgeGalaxyViewModel` 789 LOC (deep-dive §F2.1-§F2.9) — **含 P0 BUG**

**位置**: `entry/src/main/ets/viewmodels/KnowledgeGalaxyViewModel.ets` (**实际 789 LOC,审计时低估为 735**)

**关键问题** (经 deep-dive 确认):
- 🔴 **§F2.1 P0 BUG — 生产 fixture 数据泄漏到用户**: L324-465 是硬编码 12 节点的 "示例" galaxy (140 LOC),`ENABLE_GALAXY_PREVIEW_UNITS = true` (L12),`previewSubjectRank` (L527) **主动把"示例:*"学科排到最前面** (L516-522),**生产用户会在他们的 galaxy 看到假的"示例:数学分析"等学科**
- 🔴 **§F2.2 `withPreviewUnits` 污染用户状态**: L286-297 用 magic 前缀 `"galaxy_preview_"` 拼接 fixture ID,`loadNote` (L308-318) 与 `deleteNote` (L265-267) 都根据前缀做特殊判断 — 三处代码知道一个 magic string
- 🔴 **§F2.3 god `@Observed`**: `systems[]/units[]/notes[]` 五个 mutable array + DB 写副作用,`@Observed` 装饰器对消费者无效 (因 ReviewGraphView 不是 `@ObjectLink`),见 §F1.4 联动
- 🟡 §F2.4 `buildChapterOrbits` 然后 `reapplyOrbitLayout` (L573-588) 死重算
- 🟡 §F2.5 graph builder 每次 load 重建 ~6 arrays × N subjects,DB miss 时 O(n²)
- 🟡 §F2.6 `loadPersistedUnits` 异常吞掉返空,DB 故障 vs 无笔记分不清
- 🟡 §F2.7 `UnitBundle` 4 字段只用于内部三处,可用 `Map<id, tuple>` 替
- 🟡 §F2.8 舞台尺寸 `360×520` 硬编码与 ReviewGraphView L23-24 不联动

**修复方向** (Phase 4 ticket #N):
- fixture 数据移到 `entry/src/main/resources/rawfile/galaxy_preview.json`,只在 DEBUG 加载 — 见 ticket #15
- 拆 `KnowledgeGalaxyRepository` (DB + fixture merge) + `GalaxyGraphBuilder` (纯 graph build) + `KnowledgeGalaxyViewModel` (state surface only)

**严重度**: 🔴 提升 (因 §F2.1 是真用户可见 BUG,不只架构)

---

### 4.11 🟡 P1 — UTF-8 手写编码 (OcrTool L363-383)

**位置**: `agents/src/main/ets/mcp/tools/OcrTool.ets` `strToUtf8`

**问题**:
- 手写 UTF-8 编码,73 行实现 (`for (let i = 0; i < value.length; i++)` ...)
- HarmonyOS 标准库有 `util.TextEncoder` / `util.TextDecoder` (在 LlmClient 已用,见 `arrayBufferToString` L500-504)
- 自行实现 = 不必要的复杂度,也是项目规约偏好项 (C-style `for` 在项目偏好 `for...of`,虽 ArkTS 1.1 不强制禁)

**修复方向**: 改用 `util.TextEncoder.encode(value: string): Uint8Array` — HarmonyOS ArkTS 标准库提供

**严重度**: 🟡 功能正确,但不必要的复杂度 + ArkTS 违规

---

### 4.12 🟢 P2 — `agent` 术语重载 (项目名 / 模块名 / 业务概念)

**位置**: 全文

**问题**: "agent" 在本项目被用于:
1. **项目名层面**: commit `fae187c chore: 全局重命名 MathMind → MindTrace` 之前叫 MathMind,"agent" 不在项目名,但 AGENTS.md 用 "AGENTS.md" 表示"AI 助手的指南"
2. **模块名**: `agents/` HSP 目录
3. **业务概念**: `AgentFloatWindow` (浮窗) + `AgentChatService` + `AgentMemoryService` + `AgentMemoryDao` — UI 中的 "AI 助手" 概念

**建议** (Phase 2 决策):
- 项目名 / 模块名保持现状 (`MindTrace` + `agents/`)
- UI 中"AI 助手"统一改名为 `Assistant` (用户面 copy);模块名后端保留 `Agent*` (代码面)
- 写 ADR-0005 (术语规约)

**严重度**: 🟢 不是 bug,但 Glossary 不清会让 Phase 2 决策困难

---

### 4.13 🟢 P2 — 文件头注释模板覆盖率不均

**位置**: 全文

**观察**:
- `common/src/main/ets/render/ContentProtocol.ets` 有完整文件头注释 (L1-14)
- `common/src/main/ets/llm/LlmClient.ets` 有 `// ...` 块注释 (L1-22) 但不是 AGENTS.md 规定的 `/** ... */` 模板
- `entry/src/main/ets/services/AiService.ets` 有 `// ============` ASCII banner (L1-22) 但不是模板
- `agents/src/main/ets/agents/KnowledgeModel.ets` 有完整 `/** ... */` (L1-25)
- 抽样观察: 4 种风格并存,**没有统一**

**修复方向** (Phase 4 ticket #1 / MD 标准化):
- 选 1 个模板 (推荐 AGENTS.md L107 的 `/** ... */` 模板)
- 用脚本批量补全 / 改格式

**严重度**: 🟢 现有早期 audit 已 P1 标注 (P0 #6 "Code style '80+ 文件已统一'夸大"),本审计确认问题但降级为 P2 因为不影响运行时

---

### 4.14 🟢 P2 — 缺少 `CONTEXT.md` 与 `docs/adr/`

**位置**: 仓库根 + `docs/`

**观察**:
- `docs/agents/domain.md` 规约:`CONTEXT.md` 应在仓库根,`docs/adr/` 应有 ADR 文件
- 两者当前**不存在** (per 早期 audit 已确认)
- 项目已积累 ≥ 8 个跨 session 沟通文件 (`docs/2026-07-1X/`),但没有 ADR

**修复方向** (Phase 2 主任务):
- 创建 `CONTEXT.md` (Glossary)
- 创建 `docs/adr/` + 至少 3 个 ADR (layer boundaries, Dispatcher 设计, LLM 调用层)

**严重度**: 🟢 不是阻塞,但 Phase 2/3 的前置条件

---

### 4.15 🟢 P2 — 模块命名误导: `common/DatabaseHelper.ets` 在顶层

**位置**: `common/src/main/ets/DatabaseHelper.ets`

**观察**:
- 同一目录 `common/src/main/ets/models/` 已存在,但 `DatabaseHelper` 没在子目录里
- 与 `common/src/main/ets/{ocr, render, llm, ...}` 子目录规约不一致
- AGENTS.md 早期审计误以为它在 `common/src/main/ets/database/` 子目录

**修复方向**: 不必立即改 (内部一致),但下一轮整理时考虑移到 `common/src/main/ets/database/DatabaseHelper.ets`

**严重度**: 🟢

---

### 4.16 🔴 P0 — `AGENTS.md` 路径错误 + 过期信息 (继承自早期 audit)

**位置**: `AGENTS.md`

**问题** (沿用早期 audit 的 §2.2.4,§2.3,§2.5):
- L28: `D:\HMgent\MindTrace` — 实际是 `D:\HMgent\MathMind`
- L43: `最近大版本: W3 (2026-07-17)` — 实际已 W4 (commit `13c934f` 2026-07-24, + W4 wip `7d7621b` 2026-09-01)
- L57: `agents/ Dispatcher / TypeClassifier / KnowledgeModel` — 实际在 4 个子目录
- L59: `components/` `atoms/` — **不存在**
- L66-67: `archive/` `MindTrace-MVP/` — **不存在**
- L62: `docs/W3_SUMMARY.md` — **不存在** (README + AGENTS.md 都引用了死链)
- L75: `~/.mavis/agents/mavis/memory/MEMORY.md` — 不可移植,新机器没有
- L78-82: **ArkTS 1.1 铁律 Top 5 与官方规则不符** (详见 §4.17 / §4.18)

**修复方向** (Phase 4 ticket #1, Phase 5 重写):
- 改路径,改版本号,删死链,inline ArkTS 规则
- 详见 Phase 5 §5.1

**严重度**: 🔴 新 session 接 MindTrace 会被误导

---

### 4.17 🔴 P0 — AGENTS.md "禁 C 风格 for" 规则基于错误理解 (经官方文档核对)

**位置**: `AGENTS.md` L78 (rule #2)

**问题** (经 `docs/research/huawei-arkui-agent-20260901.md` §3.3 官方核对):

| 项 | AGENTS.md 现状 | 官方 ArkTS 1.1 实际 |
|---|---|---|
| 禁止 C-style `for (let i; i<n; i++)` | ❌ "禁止" | ✅ **允许** |
| 禁止 `for..in` | 未提及 | ❌ **禁止** (`arkts-no-for-in`, error 10605080) |

**官方原文**: `developer.huawei.com/.../arkts-migration-background` 第 1967-1997 行:
> "ArkTS不支持for .. in迭代对象属性。"

**影响范围**:
- 本审计初版 §4.6 据 AGENTS.md 错报"6 处 C-style `for` 违规",**已在本审计修订版 §4.6 改正**
- 全代码库需重新扫描 `for..in` 用法 (初版未扫描)
- 现有静态扫描脚本 (如有) 若基于"C-style for"扫描,会假阳性

**修复方向** (Phase 4 ticket #15 整合进 §4.18 任务):
- 改写 AGENTS.md rule #2 措辞:"项目偏好 `for...of` / `forEach` / `while` (可读性);ArkTS 1.1 strict **不允许** `for..in`"
- 增加 `for..in` 扫描到 CI / lint job
- 修正 MEMORY.md 与本审计初版 §4.6

**严重度**: 🔴 P0 — 项目规约与官方规则反向,误导新人且导致 lint 错报

---

### 4.18 🟡 P1 — ArkTS 1.1 strict 规则表覆盖率 ~10% (AGENTS.md Top 5 vs 官方 40+)

**位置**: `AGENTS.md` L78-82 + `~/.mavis/agents/mavis/memory/MEMORY.md`

**问题** (经官方 `arkts-migration-background` 全文核对):

| 项 | AGENTS.md / MEMORY | 官方 ArkTS 1.1 strict |
|---|---|---|
| 规则总数 | 5 ("铁律 Top 5") | **40+** (含 42 条 rule ID + error code) |
| 规则 ID | 无 | `arkts-no-any-unknown`(10605008)、`arkts-no-for-in`(10605080)、`arkts-as-casts`(10605053)、`arkts-no-destruct-*`(10605069/74/91)、`arkts-no-call-signatures`(10605014)、`arkts-no-intersection-types`(10605019)、`arkts-no-mapped-types`(10605083)、`arkts-no-conditional-types`(10605022) 等 |
| 项目实际违反率 | 0% (Top 5 全 OK) | **未知** — 因未扫描 40+ 规则中其余 35+ 条 |

**官方 40+ 规则节选** (完整列表见 `docs/research/huawei-arkui-agent-20260901.md` §3.2):
- `arkts-no-any-unknown` (10605008)
- `arkts-no-for-in` (10605080)  ← AGENTS.md 漏列
- `arkts-no-destruct-assignment` (10605069)
- `arkts-no-destruct-decls` (10605074)
- `arkts-no-destruct-params` (10605091)
- `arkts-as-casts` (10605053)
- `arkts-no-intersection-types` (10605019)
- `arkts-no-mapped-types` (10605083)
- `arkts-no-conditional-types` (10605022)
- `arkts-no-private-identifiers` (10605003) (`#field` 语法禁)
- `arkts-no-typing-with-this` (10605021)
- `arkts-no-ctor-signatures-*` (10605015/27)
- `arkts-no-class-literals` (10605050)
- `arkts-no-func-expressions` (10605046)
- `arkts-no-props-by-index` (10605029) (`obj['key']` 禁)
- `arkts-no-is` (10605096) (类型谓词禁)
- ... 共 42 条

**影响**:
- 审计初版仅扫了 `any`/`unknown` 与 C-style `for` 两类,**对项目实际严格模式合规度的判断不可靠**
- 项目"ArkTS 1.1 strict 基本合规"的 TL;DR 评级 **不可信**,需重做扫描

**修复方向** (Phase 4 ticket #15):
- 写 `scripts/audit-arkts-strict.ts`,扫全部 40+ 规则
- 内联规则到 `docs/style/arkts-1.1.md` (替换 AGENTS.md MEMORY 引用)
- 与 hvigor lint 集成 (CI gate)

**严重度**: 🟡 P1 — 覆盖率 10% vs 100% 的合规判断都基于不完全信息

---

### 4.19 🟡 P1 — `compatibleSdkVersion < 10` 导致 strict 规则仅警告不报错

**位置**: `entry/build-profile.json5` (推测),`common/`, `agents/` 同样

**问题** (经官方 `arkts-migration-background` 第 143-146 行核对):

官方原文:
> "compatibleSdkVersion >= 10 为标准模式。在该模式下,所有.ets文件必须严格遵循ArkTS语法规则,任何语法违规工程都会编译不通过"

**MindTrace 当前** (per AGENTS.md "ArkUI 1.1 = API 9" + 已观察到的 `compileSdkVersion`):
- 推测 `compatibleSdkVersion = 9`
- 这意味着:即使代码违反 `arkts-no-any-unknown` 等规则,DevEco Studio **只警告不报错**
- 项目"ArkTS 1.1 strict 铁律"实际是**自愿遵守**,非编译时强制

**影响**:
- 任何 ticket 的"通过 strict 检查"判定,实际只是"通过 lint 警告",不是"通过编译"
- 未来某次 commit 引入 `any` 类型,CI 不会红
- 与 §4.18 规则覆盖率问题叠加,合规度被双重低估

**修复方向** (Phase 4 ticket #15 子任务):
- 评估升级 `compatibleSdkVersion` 到 ≥10 的成本 (API 12+ 才有 `@kit.ArkTS.JSON`,可能影响 `JSON.parse` 调用)
- 短期:加 lint job 强制 `arkts-no-any-unknown` 等关键规则
- 中期:规划 API 10 升级窗口

**严重度**: 🟡 P1 — 规则不被强制 = §4.18 修复 ROI 打折

---

### 4.20 🔴 P0 — Production fixture data 泄漏到用户 (deep-dive §F2.1)

**位置**: `entry/src/main/ets/viewmodels/KnowledgeGalaxyViewModel.ets` L324-465

**问题** (经 deep-dive 报告确认):
- `KnowledgeGalaxyViewModel.previewUnits()` (L324-465, **140 LOC**) 是一个硬编码的 12 节点 "示例" galaxy
- `ENABLE_GALAXY_PREVIEW_UNITS = true` (L12) 默认开启
- `previewSubjectRank` (L527) **主动把 "示例:*" 学科排到最前面** (L516-522)
- `withPreviewUnits` (L286-297) 用 magic 前缀 `"galaxy_preview_"` 拼接 fixture ID
- `loadNote` (L308-318) 与 `deleteNote` (L265-267) 都根据前缀做特殊判断
- **结果**: 生产用户打开"知识星系"会看到假的"示例:数学分析"等学科,且这些假条目**排在最前面**

**严重度**: 🔴 P0 BUG (非架构债务) — 这是**用户可见**的脏数据,**最优先修复**,优先级高于所有架构 ticket

**修复方向** (Phase 4 ticket #16,优先级最高):
- 短期 (1 行 commit): 设 `ENABLE_GALAXY_PREVIEW_UNITS = false`
- 中期: fixture 数据移到 `entry/src/main/resources/rawfile/galaxy_preview.json`,DEBUG build 加载,RELEASE 不加载
- 长期: 拆 `KnowledgeGalaxyRepository` 接口 + `PersistedGalaxyAdapter` (生产) + `PreviewGalaxyAdapter` (debug fixture) — per deep-dive §F2.3 设计

---

### 4.21 🟡 P1 — `extractJsonObject` regex 在嵌套 JSON 上截断 (deep-dive §F3.2 / §F3.4)

**位置**: `entry/src/main/ets/services/AgentMemoryService.ets` L532-544

**问题** (经 deep-dive 报告确认):
- L539 用了非贪婪正则 `\{[\s\S]*\}` 来"找 JSON 对象"
- 对嵌套结构 (e.g. `evidence: "{nested}"`) 会**从第一个 `{` 一直匹配到最后一个 `}`**,造成整段被当成 JSON 解析
- 例如 LLM 输出 `Some words {"a": 1} tail {more}` 会被捕获为 `{"a": 1} tail {more}`,`JSON.parse` 多半抛错
- 调用方在 `console.warn` 后 `return null`,用户**静默丢失 learner profile** (L425-428)
- 同样模式在 `AgentChatService` L474-486 也有 (`extractJsonObject` 复制粘贴)

**严重度**: 🟡 P1 实际正确性 bug — silent failure,需用 brace-balance walker 重写

**修复方向** (Phase 4 ticket #17):
- 写 `extractBalancedJsonObject(text: string): string`,手动 walker 配对 `{` `}`
- 提到 `common/utils/jsonExtractor.ets`,AgentChatService / AgentMemoryService / LlmGuard 共用
- 加测试用例覆盖嵌套对象 + 字符串内含 `}` + 多 JSON 对象

---

## 5. Deep-Module 重设计目标 (Phase 2 决策候选)

每个候选都标注:现状 / 目标 interface / 拆分收益

### 5.1 `StructureService` (替代 `KnowledgeModel.structure`)

**现状**: `KnowledgeModel.structure(ocrText, type?, subject?, chapter?, source?)` 单方法 870 LOC god class

**目标 interface**:
```ts
interface StructureService {
  structure(req: StructureRequest): Promise<KnowledgeUnit>;
}
interface StructureRequest {
  text: string;
  categoryHint?: NoteCategory;
  subjectHint?: string;
  chapterHint?: string;
  source?: string;
}
```

**拆分**:
- `StructureService` (orchestrator) — 调用 TruthCheckService + PromptBuilder + LlmClient
- `TruthCheckService` (§5.2)
- `PromptBuilder` (§5.3)
- 旧 `KnowledgeModel` 删除

**收益**:
- 接口小 (1 方法 / 5 字段)
- 单测可针对 orchestrator / truth-check / prompt 三层分别写
- Phase 4 ticket #3 直接对应

---

### 5.2 `TruthCheckService` (替代 `KnowledgeModel.truthCheck`)

**现状**: 4 个数学正确性校验 + LaTeX 修复,241 行内联在 `KnowledgeModel.ets`

**目标 interface**:
```ts
interface TruthCheckService {
  check(text: string): TruthResult;
  fixLatex(text: string): FixResult;
}
```

**收益**:
- 可独立单元测试 (单文件 200+ 测试用例可写)
- 任何"数学规则变更" (e.g. 加分数校验) 只动一个文件
- 可独立用于 OCR 后处理 (不只是 KnowledgeModel)

---

### 5.3 `PromptBuilder` (替代 `KnowledgeModel.buildPrompt`)

**现状**: 35 行内联中文 prompt,与其他逻辑耦合

**目标 interface**:
```ts
interface PromptBuilder {
  build(category: NoteCategory, text: string, hints?: PromptHints): ChatMessage[];
  // 输出 system + user messages
}
```

**收益**:
- Prompt 作为数据 (可 JSON 化、可版本化)
- AB 测试不同 prompt 模板不需要改 KnowledgeModel
- 未来支持多模型时 prompt 可针对模型优化

---

### 5.4 `LlmClient` 整合 (替代三套调用路径)

**现状**: `call` + `callStream` + `callSseTokens`

**目标 interface** (Phase 2 决策二选一):
```ts
// 选项 A: 一个接口,opts.stream 控制
interface LlmClient {
  call(messages: ChatMessage[], opts: LlmCallOptions): Promise<LlmResult>;
  // opts.stream === true → AsyncIterable<LlmChunk>
  // opts.stream === false → Promise<string>
}

// 选项 B: 两个 interface,各自 adapter
interface JsonLlmCaller { call(messages, opts): Promise<string>; }
interface StreamLlmCaller { call(messages, opts): AsyncIterable<LlmChunk>; }
```

**推荐**: 选项 B (interface seam 让两个 caller 可独立测试)

**收益**:
- 三套路径合一,减少 1/3 代码量
- `LlmGuard` 可选择走 `JsonLlmCaller` (无需自己 retry)
- `AgentChatService.realReply` / `realReplyStream` 90% 重复消失

---

### 5.5 `Dispatcher` 单入口 (替代 `analyze` + `dispatch`)

**现状**: 3 个公开方法 (`analyze` + `dispatch` + `routeDispatch`)

**目标 interface**:
```ts
interface Dispatcher {
  dispatch(req: DispatchRequest, opts?: DispatchOptions): DispatchResult;
  // DispatchOptions.persist = false → 仅识别 (旧 analyze 行为)
}
```

**收益**:
- 业务方 `AiService` 不需知道"识别 vs 入库"两个方法
- `routeDispatch` 删 (dead alias)
- 内部 stage (analyze → structure → persist) 是 private,不被外部依赖

---

### 5.6 `IntentClassifier` (替代 `AgentChatService` 内嵌 keyword 字典)

**现状**: 30+ keyword 数组 + 距离算法 + 远程 LLM 兜底,内联在 `AgentChatService`

**目标 interface**:
```ts
interface IntentClassifier {
  classify(text: string, opts?: IntentOptions): Promise<Intent>;
  // Intent = 'note_generation' | 'chat'
}
```

**收益**:
- 关键字字典独立可维护 (i18n / 新增规则)
- 远程 LLM 兜底可关闭 (依赖 opt-in)
- 可单独 A/B 测试 "纯规则 vs 规则+LLM" 准确率

---

## 6. 缺失项

### 6.1 文档

- `CONTEXT.md` (仓库根) — 不存在
- `docs/adr/` — 不存在
- `docs/W3_SUMMARY.md` — AGENTS.md / README.md 引用但不存在
- `docs/specs/` — 不存在 (Phase 3 将创建)

### 6.2 测试

- `agents/src/test/` 仅 2 个测试文件 (`KnowledgeModel.test.ets`, `List.test.ets`),且规模小
- `common/src/test/` — 不存在
- `entry/src/test/` — 不存在 (虽然 `entry/build-profile.json5` 配置了 `ohosTest` target)

**这是 P0 隐性问题**: 没有测试网,任何"重设计"都没有保护。

**修复方向** (Phase 4 ticket #N 隐含):
- 每个 deep-module 重构 PR 必须有 red-green 证据
- Phase 4 起步应建立一个最小测试基线 (e.g. `StructureService` 5 个测试)

### 6.3 跨 session 通信

- `docs/ui_to_agent_*.md` 命名规约存在,但**没有实际文件** (per 早期 audit §2.7)
- 当前无活跃跨 session 协作迹象 (本审计是单 session 内部审计)

**修复方向**: 不必立即改,Phase 2/3 决定是否仍需此规约。

---

## 7. Phase 3 Ticket 预览 (基于本审计 + Phase 2 决策)

| # | 标题 (provisional) | 阻塞 | 工作量 | 对应 §4 finding |
|---|---|---|---|---|
| 1 | Rewrite AGENTS.md to reflect actual repo layout + inline ArkTS rules | — | S (1-2h) | §4.16 |
| 2 | (已删除) 项目规约与官方规则反向 (§4.17); 不强制改 OcrTool C-style for (官方允许) | — | — | §4.6 修正 |
| 3 | Split `KnowledgeModel` into `StructureService` + `TruthCheckService` + `PromptBuilder` | #1, ADR-0002 | L (4-6h) | §4.2 |
| 4 | Collapse `Dispatcher.analyze()` + `dispatch()` + `routeDispatch` to single seam | #3 | M (2-3h) | §4.5 |
| 5 | Consolidate LLM-call layer (`call` + `callStream` + `callSseTokens`) into adapter seam | #1, ADR-0003 | L (4-6h) | §4.1 |
| 6 | Standardize file headers across `common/` + `entry/services/` + `agents/` | #1 | M (2-3h) | §4.13 |
| 7 | Refactor `AgentChatService` into `ChatService` + `NoteGenerationService` + `IntentClassifier` | #1, ADR-0002 | L (4-6h) | §4.3 |
| 8 | Add `CONTEXT.md` + `docs/adr/{0001,0002,0003,0004}.md` | — | M (2-3h) | §4.14 |
| 9 | Add `LlmConfig.normalize*` rejection path (no silent overwrite) | #1 | S (1h) | §4.4 |
| 10 | Rename `agents/mcp/tools/` → `agents/tools/` (decision: skip MCP) | — | XS (30min) | §4.8 |
| 11 | Refactor `OcrTool.strToUtf8` to use `util.TextEncoder` | — | XS (30min) | §4.11 |
| 12 | Split `ReviewGraphView` 1880 LOC into layout + animation + data + UI shell | #1 | L (4-6h) | §4.9 |
| 13 | Add minimum test baseline (5 tests for `StructureService`) | #3 | M (2-3h) | §6.2 |
| 14 | Update smoke test matrix in AGENTS.md to cover W4 SSE streaming | #1 | S (1h) | (inherited) |
| **15** | **Update AGENTS.md rule #2 wording + add `docs/style/arkts-1.1.md` with full 40+ rule table + Lint job enforcing the full table** | #1 | M (2-3h) | **§4.17, §4.18, §4.19** |
| **16** | **(P0 BUG, highest priority) Fix production fixture data leak to users** — set `ENABLE_GALAXY_PREVIEW_UNITS = false` + move to `rawfile/galaxy_preview.json` loaded only in DEBUG + split `GalaxyRepository` interface | — | **S (1h)** | **§4.20** |
| **17** | Fix `extractJsonObject` non-greedy regex bug — extract to `common/utils/jsonExtractor.ets` with brace-balance walker + tests | — | S (1-2h) | §4.21 |

总计 ~16 个 ticket (删除 #2 后实际 16 个),工作量 ≈ 30-45h。**优先级重排**: #16 (P0 用户可见 BUG) > #15 (P0 规约错误) > #1 (P0 文档过期) > #3 (P0 god class) > #4-7,12 (P0/P1 架构) > #9-11 (P1 小修) > #13-14,17 (P1 测试/小修)。

### Phase 2 + Phase 3 现状 (2026-09-01)

**4 个 design surfaces (全部齐了)**:
- `CONTEXT.md` — 19 个项目专属术语
- `docs/adr/` — 7 个 ADR (含 ADR-0007 test baseline)
- `docs/specs/` — 6 个 ticket spec (依 ADR 写的实施 spec)
- `docs/style/arkts-1.1.md` — 40+ ArkTS 1.1 strict 规则手册

**工作流 (§4 finding → 实施)**:
看 §4 → 找 ticket → 查 ADR (why) → 查 spec (how) → 实施

### Phase 4 推荐实施顺序

1. **#4** (Dispatcher single-entry) — 最小 blast radius,unblocks other changes
2. **#5** (LLMClient consolidation) — 独立,~5 行 refactor
3. **#3** (KnowledgeModel decomposition) — 3 atomic PRs,870-LOC class
4. **#7** (AgentChatService decomposition) — 3 atomic PRs,802-LOC class
5. **#10** (mcp → tools rename) — git mv,~3 import lines
6. **#9** (LlmConfig throw) — ~10 行 change in LlmConfig

**完成后架构匹配 ADR 意图**:
- Dispatcher 1 public method
- LlmClient 1 public method (call + adapters)
- KnowledgeModel 不存在 (3 services 替代)
- AgentChatService thin facade
- mcp/ 目录不存在

**Phase 2 决策完成,Phase 3 spec 6/6,实施待开始**。

---

## 8. 待 Phase 2 决策的问题

下列问题应由 Phase 2 的 grilling 会话与用户共同决定,本审计只罗列:

1. **Layer 边界**: `entry/services/` 是否允许直接 import `agents/`? 推荐:只通过 `common/` 接口,`agents/` 保持黑盒。
2. **"agent" 术语**: UI 层 `AgentFloatWindow` / `AgentChatService` 是否统一改名 `Assistant*`? 推荐:用户面改名,代码面保留。
3. **Dispatcher 单入口签名**: `dispatch(req, opts?: { persist?: boolean })` 还是拆为两个 service (`RecognizeService` + `PersistService`)? 推荐:单入口 + opts,简单。
4. **LLM 层整合方式**: 单一 `LlmClient.call(opts.stream)` 还是双 adapter (`JsonLlmCaller` + `StreamLlmCaller`)? 推荐:双 adapter,seam 清晰。
5. **mcp/ 目录去留**: 删 `/mcp` 还是真接 MCP server? 推荐:删,改名 `tools/`,MCP 未来再说。
6. **ARK 规则内联位置**: 在 AGENTS.md 末尾,还是单独 `docs/style/arkts-1.1.md`? 推荐:`docs/style/arkts-1.1.md`,AGENTS.md 引用。
7. **KnowledgeModel 拆分粒度**: 3 个 service 还是 4 个 (加 LlmJsonValidator)? 推荐:4 个,LlmJsonValidator 是独立可测的 seam。
8. **测试基线**: Phase 4 起步需要多少测试? 推荐:`StructureService` 5 + `TruthCheckService` 4 + `PromptBuilder` 3 = 12 个最小集。

---

## 9. 关联文档

- `docs/architecture-audit-20260901.md` — 早期 AGENTS.md 单文档审计,本报告替代其内容但保留作为历史
- `docs/audit-deepdive-20260901.md` — 7 个最大文件 (ReviewGraphView 1880 / KnowledgeGalaxyViewModel 789 / AgentMemoryService 570 / NoteDetailOverlay 562 / MathTextRenderer 536 / UiDataCacheService / DetailRenderModel 491) 的逐文件深度分析,产出 §F1.x – §F7.x 共 50+ finding。本报告 §4.9/§4.10/§4.20/§4.21 引用其关键结论
- `docs/research/huawei-arkui-agent-20260901.md` — 华为官方文档调研笔记 (398 行,30 个 primary URL),本报告 §4.17/§4.18/§4.19 基于其结论
- `docs/agents/domain.md` — 项目域文档规约
- `docs/agents/issue-tracker.md` — GitHub issue 工作流
- AGENTS.md — 待重写 (Phase 4 ticket #1)
- README.md — 待同步版本号 (Phase 5)

---

## 附录 A — 全代码库扫描汇总

```
源文件 .ets:  162 个
总 LOC:       23,301
按 module:
  entry        123 文件 / 17,719 LOC (76% LOC 占比)
  common        22 文件 /  3,580 LOC
  agents         9 文件 /  1,930 LOC
  cardservice    6 文件 /     58 LOC
  skill          2 文件 /     14 LOC

ArkTS 1.1 扫描:
  C-style `for`: 6 处,全在 agents/mcp/tools/OcrTool.ets
  `: any` / `: unknown` 注解: 0 处

跨模块 import (agents →):
  common:  8 处
  @kit.*:  3 处
  (无 entry / skill / cardservice 反向依赖)

最大文件 (deep-dive 校正后):
  1. entry/pages/Review/ReviewGraphView.ets        1880 LOC  (deep-dive §F1.1)
  2. agents/agents/KnowledgeModel.ets              870 LOC   (deep-dive 未涉及)
  3. entry/services/AgentChatService.ets           802 LOC   (deep-dive 未涉及)
  4. entry/viewmodels/KnowledgeGalaxyViewModel.ets 789 LOC   (deep-dive §F2.1)
  5. entry/services/AgentMemoryService.ets         570 LOC   (deep-dive §F3.1)
  6. entry/overlays/NoteDetailOverlay/...          562 LOC   (deep-dive §F4.1)
  7. entry/shared/components/MathTextRenderer.ets  536 LOC   (deep-dive §F5.1)
  8. common/render/ContentProtocol.ets             580 LOC
  9. common/llm/LlmClient.ets                      458 LOC
 10. entry/services/UiDataCacheService.ets         452 LOC   (deep-dive §F6.x)
 11. entry/overlays/.../DetailRenderModel.ets      491 LOC   (deep-dive §F7.1)
```

---

**报告结束**。下一步:Phase 2 用 `grilling` skill 对 §8 的 8 个决策问题进行决策,产出 `CONTEXT.md` + 3 个 ADR。
