# MindTrace — AGENTS.md

> **鸿蒙高校创新赛 · 复赛项目** — HarmonyOS 数学学习助手 (拍照 / OCR / AI 分类 / 知识结构化 / 复习 全链)
> 5 module: `entry` (HAP) + `common` / `agents` / `skill` / `cardservice` (4 HSP)
> **DevEco Studio 与 hvigor CLI 均为合法开发入口** (Windows 中文路径允许使用 hvigor CLI, 但需注意路径与字符编码)
> 主分支: `main` + `develop` · 最新版本: v1.0 (2026-09-05 release) · 最后审计: 2026-09-01
> 项目: **MindTrace** (GitHub 仓库 `YunC-GCT/MindTrace`; MindTrace 是项目昵称; 本地目录名因机器而异, 文档一律用相对路径)

---

## 改什么 → 读哪 (必读指针)

| 改 / 触发什么 | 读哪 (按顺序) |
|---|---|
| 第一次接项目 / 写新代码前 | [`CONTEXT.md`](./CONTEXT.md) → [`docs/style/arkts-1.1.md`](./docs/style/arkts-1.1.md) |
| 改业务逻辑 / 改设计 | [`docs/adr/`](./docs/adr/) (先查 why) → [`docs/specs/`](./docs/specs/) (查 how) |
| 改 .ets 合规 / 风格 | [`docs/style/arkts-1.1.md`](./docs/style/arkts-1.1.md) (40+ 规则) |
| 写测试 / 加测试 | [`docs/specs/`](./docs/specs/) §"Test plan (TDD)" + `scripts/arkts-lint/tests/` 模板 |
| 改 .ets 文件头 / 模块结构 | [`docs/agents/file-header-template.md`](./docs/agents/file-header-template.md) |
| 改 git workflow / commit / branch | [`docs/agents/git-conventions.md`](./docs/agents/git-conventions.md) + 团队手册 [`docs/agents/git-flow-lightweight-2026-09-04.md`](./docs/agents/git-flow-lightweight-2026-09-04.md) (分支模型 / PR / 发版) |
| 改 lint 规则 / lint 输出 | [`scripts/arkts-lint/`](./scripts/arkts-lint/) + [`docs/agents/api-version.md`](./docs/agents/api-version.md) §"Lint job" |
| 改 API 版本兼容 | [`docs/agents/api-version.md`](./docs/agents/api-version.md) |
| 改安全 / secrets / 签名 | [`docs/agents/security.md`](./docs/agents/security.md) |
| 准备 PR / smoke test | [`docs/agents/smoke-test.md`](./docs/agents/smoke-test.md) |
| 排查 build / 编码陷阱 | [`docs/agents/file-header-template.md`](./docs/agents/file-header-template.md) §"创建新文件" |
| 做后端 CaptureGraph / ArkTS 重构 | [`docs/agents/d2-capturegraph-teaching-2026-09-05.md`](./docs/agents/d2-capturegraph-teaching-2026-09-05.md) (踩坑与经验) |
| 写 / 改 / 归档 doc | [`docs/agents/issue-tracker.md`](./docs/agents/issue-tracker.md) (issue 模板) + `docs/agents/domain.md` (workflow) |
| 写 issue / 改 spec | [`docs/agents/issue-tracker.md`](./docs/agents/issue-tracker.md) + [`docs/agents/triage-labels.md`](./docs/agents/triage-labels.md) |
| 排查 audit finding | [`docs/legacy/mindtrace/architecture/audit-full-2026-09-01.md`](./docs/legacy/mindtrace/architecture/audit-full-2026-09-01.md) |
| 整体目录结构 | `docs/legacy/mindtrace/architecture/audit-full-2026-09-01.md` §3 |
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

## 必守红线 (7 条, 不可逾越)

1. **不 push** — 未经 user 明确说 "push", 绝不 `git push`。"提交" = local commit
2. **build 可由 AI 跑** — `Build Hap(s)/APP(s)` 可由 AI 通过 hvigor CLI 或 DevEco GUI 执行; AI 做本地 commit + 验证测试 + 跑 build, 不需要 user 跑
3. **不 overwrite** — user 手动编辑过的 plan / file, **不整段覆盖**; 先 read 最新版, 优先 append
4. **相对路径** — 文档禁止盘符绝对路径: 仓库内引用一律相对路径, 工具位置用环境变量表达; 本地目录名因人而异, 以实际工作目录为准
5. **commit 规范** — conventional commits + 模块前缀 (`docs(frontend):` / `fix(agents):`); 详见 [`docs/agents/git-conventions.md`](./docs/agents/git-conventions.md)
6. **不进 `main`** — 所有改动 commit 到 `feature/*` / `bugfix/*` 分支, 通过 PR 合入 `develop`,user 手动 review + merge。详见 [`docs/agents/git-conventions.md`](./docs/agents/git-conventions.md) §"分支工作流"
7. **worktree 互斥** — 多 session 共享同一 worktree 时, 一个 session 改时另一个别动; 多 worktree 用 `develop` 分支同步

---

## 比赛定位 & 演示流程

### 项目亮点 (展示给评委)

| 亮点 | 位置 | 说明 |
|---|---|---|
| **AI 智能分类 + 知识结构化** | `agents/src/main/ets/agents/` | 5 类题型识别 + KnowledgeUnit 拆解, 端到端 LLM pipeline |
| **LlmClient 流式响应 (W4 新)** | `common/src/main/ets/llm/LlmClient.ets` | 3 调用路径待合一, spec [`005`](./docs/specs/005-llm-client-consolidation.md) |
| **知识星系可视化** | `entry/src/main/ets/pages/KnowledgeGalaxy*` | 用户学情可视化 |
| **ArkTS 严格 lint 引擎** | `scripts/arkts-lint/` | 自研 AST 引擎, 34 规则 + 89 单元测试, **CI 已接入** |
| **审计 + ADR + Spec 完整设计层** | `docs/legacy/mindtrace/architecture/` (历史审计) + `docs/adr/` + `docs/specs/` | 9 ADR + 9 ticket spec, 设计透明度高 |

### 演示路径 (5 分钟 walk-through)

1. 启动 OCR 服务 (`python -m uvicorn ocr.app:app --port 8000`)
2. DevEco Studio `Run → Run 'entry'` (真机/模拟器)
3. 主流程: 拍照 → OCR → AI 分类 → 知识结构化 → 持久化 → 复习浮窗对话 (SSE 流式)
4. 5 Tab 流畅 / 知识星系无 "示例:*" 假学科 (ticket #16 已修)
5. 源码: `agents/` (AI 业务) + `scripts/arkts-lint/` (工程亮点) + `docs/legacy/mindtrace/architecture/audit-full-2026-09-01.md` (21 个 finding 的架构审计)

### 状态 (per audit 2026-09-01 · D2-D4 进度 2026-09-06)

✅ 已修: **#15** ArkTS 铁律 (规约错误) · **#9** LlmConfig 静默覆盖 (TDD) · **#16** fixture data 泄漏 (TDD)
✅ 已落地: **D2 全链** (2026-09-05, spec [`011`](./docs/specs/011-capturegraph-arkts-refactor.md) + [ADR-0008](./docs/adr/0008-capturegraph-self-built-runtime.md)) — Dispatcher 单入口 + CaptureGraph (capture→classify→structure→truth_check→persist 条件边) + 5 节点, 旧 API 已删 · **D3 部分** (spec [`012`](./docs/specs/012-frontend-component-model.md)) — shared/components → atoms/molecules/organisms · **D4 P0 契约** (spec [`013`](./docs/specs/013-kit-adoption-boundary.md) + [ADR-0009](./docs/adr/0009-kit-facade-injection-boundary.md)) — `common/kit/` 三 facade
🟡 待修: **#1** doc expiry · **#3** KnowledgeModel 实质拆分 (façade 阶段) · **#5** LlmClient 三路径合一 · **#7** AgentChatService 拆分 · **#10** mcp/ → tools/ rename (D4 Kit 实际接入后续评估, 2026-09-06)

详细: [`docs/legacy/mindtrace/architecture/audit-full-2026-09-01.md`](./docs/legacy/mindtrace/architecture/audit-full-2026-09-01.md) §7 + [`docs/specs/`](./docs/specs/)

---

## 关键架构 (30 秒读懂)

| 层 | 位置 | 责任 |
|---|---|---|
| UI | `entry/pages/`, `entry/overlays/` | 渲染 + 用户输入 |
| View Model | `entry/viewmodels/` | UI state + 用户意图 |
| Business Service | `entry/services/` | 编排, **不持 UI 引用** |
| **AI Agent (亮点)** | `agents/` | `Dispatcher` (主) + `TypeClassifier` / `KnowledgeModel` (子) |
| Data + Infra | `common/` | `LlmClient` / `LlmGuard` / `ContentProtocol` / RDB 单例 |

**关键 seam**: `AiService.capture → Dispatcher.dispatch → KnowledgeModel.structure → LlmClient.call → LlmGuard`; 全部 Markdown 走 `ContentProtocol` (MM-MD-v1)

**5 module 拓扑**: 1 HAP (`entry`, `type:entry`) + 4 HSP (`common` / `agents` / `skill` / `cardservice`, `type:feature`); 跨 module import 必须完整路径

**已废弃 (不要新建)**: ~~`components/`~~ ~~`atoms/`~~ ~~`archive/`~~ ~~`MindTrace-MVP/`~~ ~~`common/src/main/ets/database/`~~ (顶层) ~~`docs/W3_SUMMARY.md`~~

---

## 常用命令 (Windows / DevEco Studio)

**hvigor CLI 与 DevEco GUI 均可使用** (Windows 中文路径下 hvigor CLI 已验证可用, AI 可以主动调用)。

| 任务 | 命令 |
|---|---|
| Open 项目 | DevEco `File → Open → <本地仓库根>` (目录名以各人克隆为准) |
| Build / Run / Sync | DevEco GUI (`Build → Build Hap(s)/APP(s)`, `Run → Run 'entry'`) |
| 启动 OCR 服务 | `python -m uvicorn ocr.app:app --port 8000` |
| 跑 arkts-lint 测试 | `npm --prefix scripts/arkts-lint test` (89 测试) |
| 跑 v0.3 lint 扫描 | `node scripts/arkts-lint/index.mjs --quiet` |
| 创建新 module | `cp common/oh-package.json5 <new>/oh-package.json5` (必须含 `main` 字段) |
| 验 .ets 无 BOM | PowerShell: `[System.IO.File]::ReadAllBytes(path)[0..2]` (应为 `0x69 0x6D 0x70`) |

---

## Agent skills 索引

| Skill | 说明 | 详细 |
|---|---|---|
| **CONTEXT.md** | 项目专属词汇 (4 种 "agent" 消歧; D2 起含 CaptureGraph 等) | [`CONTEXT.md`](./CONTEXT.md) |
| **ADR** | 架构决策记录 (9 个) | [`docs/adr/`](./docs/adr/) |
| **Ticket specs** | 依 ADR 写的实施 spec (9 个) | [`docs/specs/`](./docs/specs/) |
| **Issue tracker** | GitHub Issues on `YunC-GCT/MindTrace`, via `gh` CLI | [`docs/agents/issue-tracker.md`](./docs/agents/issue-tracker.md) |
| **Triage labels** | 5 标签: `needs-triage` / `needs-info` / `ready-for-agent` / `ready-for-human` / `wontfix` | [`docs/agents/triage-labels.md`](./docs/agents/triage-labels.md) |
| **TDD / domain-modeling** | 按需调 skill, 不强制 | (内置 skill) |