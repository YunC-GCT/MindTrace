# MindTrace — AGENTS.md

> **鸿蒙高校创新赛 · 复赛项目 → v1 端A2A 交付** — HarmonyOS 数学学习助手 (拍照 / OCR / 知识结构化 / 端侧 Agent)
> 5 module: 3 HAP (`entry` / `skill` / `cardservice`) + 2 HSP (`common` / `agents`)
> **DevEco Studio 与 hvigor CLI 均为合法开发入口**; CLI 构建 + `hdc` 装机已跑通, AI 可自行验证
> 当前主线: **检索与笔记治理（RAG / 判重 / 建议）** (v1 端A2A 已交付; 测试态不推进上架) · 进度与验收口径见 [`docs/agents/phase-tracker.md`](./docs/agents/phase-tracker.md)
> 项目: **MindTrace** (GitHub 仓库 `YunC-GCT/MindTrace`; 本地目录名因机器而异, 文档一律用相对路径)

---

## 改什么 → 读哪 (必读指针)

| 改 / 触发什么 | 读哪 (按顺序) |
|---|---|
| 第一次接项目 / 写新代码前 | [`CONTEXT.md`](./CONTEXT.md) → [`docs/style/arkts-ai-coding.md`](./docs/style/arkts-ai-coding.md) (60 秒清单) → [`docs/style/arkts-1.1.md`](./docs/style/arkts-1.1.md) (全文) |
| 改业务逻辑 / 改设计 | [`docs/adr/`](./docs/adr/) (先查 why) → [`docs/specs/`](./docs/specs/) (查 how) |
| 改 .ets 合规 / 风格 | [`docs/style/arkts-ai-coding.md`](./docs/style/arkts-ai-coding.md) (先看) → [`docs/style/arkts-1.1.md`](./docs/style/arkts-1.1.md) (40+ 规则) |
| 写测试 / 加测试 | [`docs/specs/`](./docs/specs/) §"Test plan (TDD)" + `scripts/arkts-lint/tests/` 模板 |
| 改 .ets 文件头 / 模块结构 | [`docs/agents/file-header-template.md`](./docs/agents/file-header-template.md) |
| 改 git workflow / commit / branch | [`docs/agents/git-conventions.md`](./docs/agents/git-conventions.md) + 团队手册 [`docs/agents/git-flow-lightweight-2026-09-04.md`](./docs/agents/git-flow-lightweight-2026-09-04.md) (分支模型 / PR / 发版) |
| 改 lint 规则 / lint 输出 | [`scripts/arkts-lint/`](./scripts/arkts-lint/) + [`docs/agents/api-version.md`](./docs/agents/api-version.md) §"Lint job" |
| 改 API 版本兼容 | [`docs/agents/api-version.md`](./docs/agents/api-version.md) |
| 改安全 / secrets / 签名 | [`docs/agents/security.md`](./docs/agents/security.md) |
| 准备 PR / smoke test | [`docs/agents/smoke-test.md`](./docs/agents/smoke-test.md) |
| 复赛演示脚本 / 赛前检查 | [`docs/agents/demo-script-2026-09-06.md`](./docs/agents/demo-script-2026-09-06.md) |
| 排查 build / 编码陷阱 | [`docs/agents/file-header-template.md`](./docs/agents/file-header-template.md) §"创建新文件" |
| 做 Agent workflow / CaptureGraph / ToolLoop / Conversation / skill 重构 | [`docs/specs/018-agent-workflow-architecture.md`](./docs/specs/018-agent-workflow-architecture.md) → [`docs/adr/0008-capturegraph-self-built-runtime.md`](./docs/adr/0008-capturegraph-self-built-runtime.md) → [`docs/agents/d2-capturegraph-teaching-2026-09-05.md`](./docs/agents/d2-capturegraph-teaching-2026-09-05.md) |
| 接 / 改小艺端A2A | [`docs/agents/phase-tracker.md`](./docs/agents/phase-tracker.md) (P0 验收口径) → `entry/src/main/ets/services/A2AController.ets` (策略/编排) → `entry/src/main/ets/services/IngestGateway.ets` (inline/queue) → `entry/src/main/ets/agentextability/AgentExtAbility.ets` (协议/快照) → `entry/src/main/resources/base/profile/agent_config.json` |
| 改 A2A 错误文案 / 分类 | `entry/src/main/ets/services/A2AErrorTaxonomy.ets` → [`docs/specs/042-a2a-error-taxonomy.md`](./docs/specs/042-a2a-error-taxonomy.md) |
| 改数据保留 / 清理策略 | `entry/src/main/ets/services/DataRetentionService.ets` + `A2AContextCleanup.ets` → [`docs/specs/043-data-retention.md`](./docs/specs/043-data-retention.md) |
| 查当前做到哪一阶段 / 怎么验收 | [`docs/agents/phase-tracker.md`](./docs/agents/phase-tracker.md) (唯一进度口径, P0–P6 + DoD) |
| 真机验证 A2A 链路 | `python scripts/a2a-smoke/a2a_smoke.py --text "整理数学题"` (自动起小艺 → 进智能体 → 发送 → 比对回复) |
| 推进 agent 能力级工作 (工具层 / 调用协议 / 拆分) | [`docs/agents/patterns/capability-to-implementation.md`](./docs/agents/patterns/capability-to-implementation.md) (skill 链路) + [`docs/architecture/agent-tool-chain-2026-09-06.md`](./docs/architecture/agent-tool-chain-2026-09-06.md) (派发链总览) |
| 接手后端架构迁移 | [`docs/specs/018-agent-workflow-architecture.md`](./docs/specs/018-agent-workflow-architecture.md) (当前权威状态) → [`docs/legacy/mindtrace/backend-migration-handoff.md`](./docs/legacy/mindtrace/backend-migration-handoff.md) (历史推进背景) |
| 改 entry UI 设计/动效/token | 先读 [`docs/research/frontend-component-audit-2026-09-06.md`](./docs/research/frontend-component-audit-2026-09-06.md) (分层裁决 + C1-C6 候选) → 设计/动效细节 [`docs/research/frontend-ui-design-inventory-2026-09-06.md`](./docs/research/frontend-ui-design-inventory-2026-09-06.md) (96 件三维档案: 令牌/布局/动效) |
| 写 / 改 / 归档 doc | [`docs/index.md`](./docs/index.md) (文档导航) + [`docs/agents/document-control.md`](./docs/agents/document-control.md) (状态/追溯规则) + [`docs/agents/domain.md`](./docs/agents/domain.md) (workflow) + [`docs/agents/issue-tracker.md`](./docs/agents/issue-tracker.md) (issue 模板) |
| 记录执行 / 验收证据 | [`docs/specs/execution/index.md`](./docs/specs/execution/index.md) (bundle 文件词汇与状态口径) |
| 查历史 session 交接 | [`docs/legacy/mindtrace/`](./docs/legacy/mindtrace/) (冻结, 非当前指引) |
| 写 issue / 改 spec | [`docs/agents/issue-tracker.md`](./docs/agents/issue-tracker.md) + [`docs/agents/triage-labels.md`](./docs/agents/triage-labels.md) |
| 排查 audit finding | [`docs/legacy/mindtrace/audit-full-2026-09-01.md`](./docs/legacy/mindtrace/audit-full-2026-09-01.md) |
| 整体目录结构 | `docs/legacy/mindtrace/audit-full-2026-09-01.md` §3 |
| 写新文件 / 改文件名 | [`docs/style/naming-conventions.md`](./docs/style/naming-conventions.md) (权威源) + `node scripts/naming-lint/index.mjs` (验证) |
| 生成 HTML render / 配对 .md+.html 视觉稿 / 清理 docs/legacy/ | [`docs/style/html-in-docs.md`](./docs/style/html-in-docs.md) (决策树) + `.gitignore` + `.naminglintrc.json` skip.files |

---

## 命名规范 (7 条硬约束, 不可逾越)

> **权威源**: [`docs/style/naming-conventions.md`](./docs/style/naming-conventions.md)。本节是硬规则摘要, 详情查源。

1. **顶级 doc**: UPPERCASE 单词 (`AGENTS.md` / `CONTEXT.md` / `README.md`)
2. **目录 / doc / 配置**: `kebab-case` (kebab-case.md, langgraph-rules/) — **禁**驼峰、**禁**下划线、**禁**空格
3. **日期后缀**: `YYYY-MM-DD` (非 `YYYYMMDD` / `_2026_09_15`)
4. **React 组件 (.tsx)**: `PascalCase` 目录 + `PascalCase` 文件名 (e.g. `Button.tsx`, `SearchField.tsx`)
5. **Python 节点 (.py)**: `snake_case.py` + `PascalCase` class (e.g. `retrieve_node.py` 的 `class RetrieveNode`)
6. **测试文件**: `*.test.{ts,tsx,mjs,py}` 与被测文件同目录, 或 `__tests__/` / `tests/` 目录
7. **重命名**: 必须 `git mv` (保 git 历史); **禁** `mv old new` 后再 `git add`

**禁止模式** (完整列表见权威源 §7): 空格、驼峰 / 下划线 (doc 用)、`YYYYMMDD`、缩写、`.html` 入 git、`mv` 不带 `git`。

**验证**: `node scripts/naming-lint/index.mjs` (CI 自动守门)

---

## 必守红线 (8 条, 不可逾越)

1. **不 push** — 未经 user 明确说 "push", 绝不 `git push`。"提交" = local commit
2. **build 可由 AI 跑** — `Build Hap(s)/APP(s)` 可由 AI 通过 hvigor CLI 或 DevEco GUI 执行; AI 做本地 commit + 验证测试 + 跑 build, 不需要 user 跑
3. **不 overwrite** — user 手动编辑过的 plan / file, **不整段覆盖**; 先 read 最新版, 优先 append
4. **相对路径** — 文档禁止盘符绝对路径: 仓库内引用一律相对路径, 工具位置用环境变量表达; 本地目录名因人而异, 以实际工作目录为准
5. **commit 规范** — conventional commits + 模块前缀 (`docs(frontend):` / `fix(agents):`); 详见 [`docs/agents/git-conventions.md`](./docs/agents/git-conventions.md)
6. **不进 `main`** — 所有改动 commit 到 `feature/*` / `bugfix/*` 分支, 通过 PR 合入 `develop`,user 手动 review + merge。详见 [`docs/agents/git-conventions.md`](./docs/agents/git-conventions.md) §"分支工作流"
7. **多 session 并行必须隔离** — ≥2 个 session 同时开发时, 每个 session 用 `git worktree add` 独立工作区(或严格串行: 一个 session 的 commit+push 完成前另一个不做任何 git 写操作); **禁止**在共用 clone 里互相切分支或把他人未完成改动带进自己的 PR; 各分支照常 PR 合入 `develop` 同步。详见团队手册 §11
8. **code review 不阻塞** — `/code-review` 走完 Standards / Spec 两轴后直接继续（含本地 commit），不再等待 user 确认；**push、合并 PR、把改动带进 `main` 仍需 user 明确确认**（见红线 1 / 6）。review 发现的问题要么当轮修掉，要么写进执行包 `tasks.md` 的未勾选项并说明原因，不许口头「已知悉」了事。
9. **端A2A 配置三件事** — 改 `agent_config.json` 后必须：① 平台重新导入 AgentCard ② 重新发真机测试 ③ 重启小艺。缺一条小艺仍读旧卡，表现为 `extension ability not exist` 或发了不回。
10. **两种 AgentID 不是一回事** — 小艺开放平台**生成**的 `AgentID`（形如 `agent` + 32 位十六进制）用于应用内 `FunctionComponent` 拉起智能体；`agent_config.json` 里的 `agentId`（如 `mindtrace-note-agent`）只是端A2A 的应用内标识。填错时 `isAgentSupport()` 恒为 false，入口永远显示「暂不支持」。
10. **不虚报可用** — 端A2A 的改动没跑过 `scripts/a2a-smoke/a2a_smoke.py` 且拿到 `ok: true`，不得写成“已通 / 可用 / 完成”。
11. **受限 Kit 的求值必须延迟** — `@kit.DataAugmentationKit`（`localChatModel`）只在 UI 进程可用。放进 `common` 必须满足两条：`import type` 只取类型，运行时用 `await import()` 在调用点加载（参照 `common/src/main/ets/llm/LocalChatProvider.ets`）。模块顶层静态求值会在 `:agent` 扩展进程触发初始化，导致网络栈失败（`proxy SendRequest failed 201`）、A2A 的 LLM 调用永不返回（2026-10-24 事故）。Kit 准入由 `scripts/process-boundary` 的登记表按**进程可达性**判定（未登记即失败），不看模块名；新增 Kit 先登记再使用。

---

## AI 编码执行契约 (写代码 / 改代码必守)

> 这一节是给 **AI agent 的运行时约束**，不是建议。与“必守红线”叠加生效。

1. **先读后写**：改 `.ets` 前读 [`docs/style/arkts-ai-coding.md`](./docs/style/arkts-ai-coding.md)；不确定的规则查 [`docs/style/arkts-1.1.md`](./docs/style/arkts-1.1.md) 或机器可读清单 [`docs/style/arkts-rules.json`](./docs/style/arkts-rules.json)。不要凭记忆猜 ArkTS 语法。
2. **改完必跑 gate**：`node scripts/agent-gate/index.mjs`。它检查改动的 `.ets`（BOM / 文件头 / 模块边界）、`arkts-lint`、`naming-lint`、`link-check`、`doc-trace`、`process-boundary`，**并跑全量单测**（改动集含 `.ets/.mjs/.ts/.json` 时；`--all` 必跑）。
3. **交付必须带 gate 结果**：回复 / PR / commit 里写 `RESULT: PASS` 或失败项；没有 gate 输出的“已完成”视为未完成。
4. **不许绕过**：不得用 `--no-verify`、注释掉 lint 规则、删除/跳过测试、改 `build-profile` 或 CI 来让 gate 变绿。gate 失败先修第一条 error，再重跑。
5. **边界不放宽**：`agents/` 不 import `entry/`；`pages/` / `overlays/` 不直接 import `CaptureGraph` / `CommandExecutor` / `NoteDao`（走 service）；不新建第 6 个 module；不改 `mcp/` 语义（ADR-0010）。
6. **设计变更先落文档**：改架构 / 协议 / 数据模型前，先看 ADR 与 spec；新的不可逆决策写 ADR，不把决定藏在代码里。
7. **只改该改的**：不顺手重构无关文件，不整段覆盖 user 的手工编辑；历史文档（`docs/legacy/`）只读。
8. **报告事实**：命令失败就贴失败输出；不要用“应该”“大概”代替验证结果。
9. **协议以 SDK 为准**：端A2A 报文格式查 `@ohos.app.agent.AgentExtensionAbility.d.ts` 与 `application/AgentCard.d.ts`，不凭记忆或旧文档写字段名（`kind` 在 A2A v1.0 已删除，`parts` 只有 `mediaType` + `text`）。
10. **交付附烟雾结果**：动了 A2A 链路，回复里贴 `a2a_smoke.py` 的 `ok` 与 `reply_text`，以及 `RESULT: PASS`。

---

## 比赛定位 & 演示流程

### 项目亮点 (展示给评委)

| 亮点 | 位置 | 说明 |
|---|---|---|
| **AI 智能分类 + 知识结构化** | `agents/src/main/ets/agents/` | 5 类题型识别 + KnowledgeUnit 拆解, 端到端 LLM pipeline; KnowledgeModel 重构为轻量编排 agent (spec 015: 拆出 PromptBuilder / TruthCheckService 协作服务) |
| **LlmClient 统一调用层** | `common/src/main/ets/llm/LlmClient.ets` | 唯一公共入口 `call(request)` (spec [`005`](./docs/specs/005-llm-client-consolidation.md)): JSON 与真 SSE 流式 (requestInStream) 双适配路径 |
| **知识星系可视化** | `entry/src/main/ets/pages/KnowledgeGalaxy*` | 用户学情可视化 |
| **ArkTS 严格 lint 引擎** | `scripts/arkts-lint/` | 自研 AST 引擎, 34 规则 · `npm --prefix scripts/arkts-lint test` **768 项全绿**（已取消 curated 白名单，跑全量 glob，约 40 s）· `agent-gate` 与 CI 同源 · **CI 已接入** |
| **审计 + ADR + Spec 完整设计层** | `docs/adr/` + `docs/specs/` + `docs/legacy/mindtrace/` | 19 篇 ADR + 26 篇设计 spec + 8 个执行包 + 1 份残包合并记录, 设计透明度高 |

### 当前阶段 (v1 端A2A)

| 阶段 | 状态 | 说明 |
|---|---|---|
| **P0 协议接入** | ✅ | 小艺可调起 `AgentExtAbility` 并渲染回复；验收命令 `python scripts/a2a-smoke/a2a_smoke.py --text "整理数学题"` 返回 `ok: true` |
| **P1 入口 / P2 选图 / P3 编排 / P3b 文搜图** | ✅ | 应用内 `+ → 批量`；A2A 已就地入库（`AgentIngestService → CommandExecutor → KnowledgeUnitWriteService`）；逐项证据见 phase-tracker |
| **P4 模型网关** | 🟡 | 云端真机已通（首字 741ms）；端侧 `localChatModel` 仅 PC/2in1 + 企业资质，手机平板不可用 |
| **P4 结果回执 / P5 合规** | ⬜ / ⏸ | 回执条数未做；合规标识随 P6 缓做 |
| **P6 上架** | ⏸ | **项目处于测试态，不推进上架**；只影响「意图注册」与「Agent Framework Kit 拉起智能体」两项验证，不影响应用内链路与 A2A 白名单链路 |

**新功能一律按 P1–P5 推进；测试态下不排上架相关工作。**
---

## 关键架构 (30 秒读懂)

| 层 | 位置 | 责任 |
|---|---|---|
| UI | `entry/pages/`, `entry/overlays/` | 渲染 + 用户输入 |
| View Model | `entry/viewmodels/` | UI state + 用户意图 |
| Business Service | `entry/services/` | 编排, **不持 UI 引用** |
| **AI Agent (亮点)** | `agents/` | `CommandExecutor` / `CommandRouter` (主) + workflows / `TypeClassifier` / `KnowledgeModel` |
| Agent Workflows | `common/workflow/`, `agents/graph/`, `entry/workflows/`, `skill/workflows/` | 共享 StateGraph 内核 + 各领域 State/Node/Edge |
| **端A2A 入口** | `entry/agentextability/` + `entry/services/A2AController.ets` + `entry/services/IngestGateway.ets` | 小艺 JSON-RPC 2.0 接入：`onData` → `A2AController.handle` → `IngestGateway` → 回 `task` 快照；ability 只做协议适配 |
| Data + Infra | `common/` | `LlmClient` / `LlmGuard` / `ContentProtocol` / RDB 单例 |

**关键 seam**: `ConversationWorkflow → AiService.captureText → CommandExecutor.dispatchCommand → NoteCaptureWorkflow → CaptureGraph → KnowledgeModel.structure → TruthCheckNode → NoteDaoAdapter`; LLM 统一走 `LlmClient.call`, 工具统一走 `ToolCatalog/ToolRegistry`, 全部 Markdown 走 `ContentProtocol` (MM-MD-v1)

**LLM 截断处理**: 聊天回复在 `finish_reason === 'length'` 时**不再抛错**——流式在末尾追加 `*(回复因长度限制被截断)*`，非流式返回 partial + 同一标记（`LlmResponseParser` / `LlmClient`）。`ReplyService` 仍显式传 `CHAT_REPLY_MAX_TOKENS = 12000`。**注意**：note generation 的 JSON 路径（`GenerationJsonCaller`）遇到同一标记会抛 `LLM_TRUNCATED`，消息形如 `... response truncated by max_tokens`；这不是聊天回复的 StreamEvent 解析问题，修法是提高生成预算 / 压缩 prompt，而不是改流式解析。

**5 module 拓扑**: 3 HAP (`entry` `type:entry` / `skill` / `cardservice` `type:feature`) + 2 HSP (`common` / `agents` `type:shared`); 跨 module import 必须完整路径

### 模块归属判据 (2026-11-03)

放哪儿不看「像不像业务」，只看两个问题：

1. **`:agent` 进程要执行它吗？** 要 → `common`（纯契约 / 模型 / 工具）或 `agents`（编排与业务规则）。两者都会在扩展进程加载。
2. **它碰的是规则还是能力？** 规则（纯计算、判定、映射）可以跨模块；能力（RDB 句柄、Kit、UI 渲染）只能留在能执行它的模块。

| 内容 | 归属 |
|---|---|
| 领域模型 / DTO（双进程共用词汇） | `common/models` |
| 纯算法 / 纯函数（无 IO） | `common/utils` 或 `agents` |
| 端口契约 | `common/ports` |
| 编排（workflow / graph / executor / router） | `agents` |
| RDB 实现（DAO）、事务仓储 | `entry/database`，agents 只能经端口使用 |
| 设备 Kit 封装（OCR / 3D 渲染 / CoreFile / DataAugmentation） | `entry` |
| 组合根、工厂、适配器 | `entry` |
| UI 状态、页面、ability、A2A 协议 | `entry` |
| 运行时调度（`WriteJobScheduler`） | `entry`（UI 进程单执行者） |

**`common` 的准入比 `agents` 更严**：只放「≥2 个模块或 ≥2 个进程真实使用，且不含业务阈值 / 用户文案 / 配色渲染」的东西；数据访问实现（RDB 适配器、具体工具）留在 common 内部但**不进 barrel**，消费方按文件深路径引用。单模块使用的业务规则一律回它所属的模块。

**`entry` 不是业务层，是壳 + 组合根**：页面、ability、装配、设备能力。业务规则没理由留在 `entry`；留在那里的唯一合法理由是它必须碰 entry 的 DAO 或 entry-only Kit，而那种情况应该先问「能不能用 `common/ports` 反转」。

**共享原子件**: `entry/src/main/ets/shared/atoms/` 与 `shared/molecules/` (spec 012)

---

## 常用命令 (Windows / DevEco Studio)

**hvigor CLI 与 DevEco GUI 均可使用** (Windows 中文路径下 hvigor CLI 已验证可用, AI 可以主动调用)。

| 任务 | 命令 |
|---|---|
| Open 项目 | DevEco `File → Open → <本地仓库根>` (目录名以各人克隆为准) |
| Build / Run / Sync | DevEco GUI (`Build → Build Hap(s)/APP(s)`, `Run → Run 'entry'`) |
| 启动 OCR 服务（Docker） | `MT_PADDLEX_CACHE=C:/Users/<you>/.paddlex docker compose up -d ocr` (端口 8000; 详见 tools/ocr_service/README.md) |
| 启动 OCR 服务（原生，已弃用） | 运行 `tools/ocr_service/start.bat` (端口 8000; 仅应急) |
| 启动 Embedding 服务（Docker） | 先启动 Docker Desktop，再 `MT_HF_CACHE=C:/Users/<you>/.cache/huggingface docker compose up -d embedding` (端口 8001; 详见 tools/embedding_service/README.md) |
| 跑 arkts-lint 测试 | `npm --prefix scripts/arkts-lint test` (数量以输出为准, 全绿即可) |
| 跑 v0.3 lint 扫描 | `node scripts/arkts-lint/index.mjs --quiet` |
| **交付前跑总 gate** | `node scripts/agent-gate/index.mjs`（改动集）/ `--all`（全仓）/ `--json`（机器读） |
| **一键构建 HSP→断言→HAP (改了 `common` 必须走这条)** | `node scripts/build-hsp-hap.mjs` |
| CLI 构建 HSP (独立构建第 1 步; 改了 `common` 必跑) | `node "<DevEco>/tools/hvigor/bin/hvigorw.js" --mode module -p product=default -p module=common@default assembleHsp --no-daemon --no-incremental` |
| HSP 新鲜度自检 (独立构建第 2 步; 退出码 0 = 新鲜) | `node scripts/hsp-freshness/index.mjs` |
| **装机时安装 HSP (只装 HAP 会留下旧 HSP)** | `hdc install -r common/build/default/outputs/default/common-default-signed.hsp`，再装 `entry-default-signed.hap`；否则设备仍跑旧共享包，运行期 `SyntaxError` |
| CLI 构建 HAP (独立构建第 3 步) | `node "<DevEco>/tools/hvigor/bin/hvigorw.js" --mode module -p product=default -p module=entry@default assembleHap --no-daemon` |
| 装机 | `hdc install -r entry/build/default/outputs/default/entry-default-signed.hap` |
| 端A2A 真机冒烟 | `python scripts/a2a-smoke/a2a_smoke.py --text "整理数学题"` (`ok` / `reply_text` / `hilog`) |
| 一键真机验证（锁屏预检 + hilog 流式捕获） | `node scripts/device-runner.mjs <install\|status\|capture\|smoke\|e2e <mode> [--cold] [--wait 秒]>`；日志落 `.device-logs/` |
| 创建新 module | `cp common/oh-package.json5 <new>/oh-package.json5` (必须含 `main` 字段) |
| 验 .ets 无 BOM | PowerShell: `[System.IO.File]::ReadAllBytes(path)[0..2]` (应为 `0x69 0x6D 0x70`) |

**独立构建顺序**: HSP → 新鲜度自检 → HAP；改了 `common` 不重建 HSP，运行期会因 HSP 产物旧于源码报 `SyntaxError`。

---

## Agent skills 索引

| Skill | 说明 | 详细 |
|---|---|---|
| **CONTEXT.md** | 项目专属词汇 (4 种 "agent" 消歧; D2 起含 CaptureGraph 等) | [`CONTEXT.md`](./CONTEXT.md) |
| **ADR** | 架构决策记录 (19 篇) | [`docs/adr/`](./docs/adr/) |
| **Ticket specs** | 依 ADR 写的设计 spec (22 个) + 执行记录 | [`docs/specs/`](./docs/specs/) · [`docs/specs/execution/`](./docs/specs/execution/) |
| **Issue tracker** | GitHub Issues on `YunC-GCT/MindTrace`, via `gh` CLI | [`docs/agents/issue-tracker.md`](./docs/agents/issue-tracker.md) |
| **Triage labels** | 5 标签: `needs-triage` / `needs-info` / `ready-for-agent` / `ready-for-human` / `wontfix` | [`docs/agents/triage-labels.md`](./docs/agents/triage-labels.md) |
| **端A2A 接入 / 排障** | 小艺调起 `AgentExtensionAbility` 的完整流程与坑 (服务名称=abilityName、proto-JSON、单条 task 快照) | Hermes skill `harmonyos-xiaoyi-a2a` + [`scripts/a2a-smoke/`](./scripts/a2a-smoke/) |
| **TDD / domain-modeling** | 按需调 skill, 不强制 | (内置 skill) |
