# MindTrace 项目定位 — 摘要 + 详细双节

> **Date:** 2026-09-04
> **Project:** MindTrace (`<本地仓库根>`,大小写敏感,非 `MindTrace` 仓库名)
> **Audience:** 评委 pitch(读 §1)+ 团队对齐(读 §2–§9)
> **Scope:** 全代码库扫描 + 本地文档三角验证;远程 `YunC-GCT/MindTrace` 当前环境 404,见 §8
> **基线 HEAD:** `5963493` on `YunCeH`(与 `main` 同步);审计基线 `29df511` (2026-09-01)

---

## §0 一句话定位

MindTrace 是**鸿蒙高校创新赛复赛项目**:一个跑在 HarmonyOS 上的数学学习助手,核心闭环是 **拍照 → OCR → AI 分类 → 知识结构化 → 持久化 → 复习浮窗对话(SSE 流式)**,并配自研的 **AST ArkTS 1.1 strict lint 引擎** 与 **7 ADR + 6 spec + 21-finding 审计** 的工程治理层。当前 W4 阶段,业务跑通,债务清单已盘清,正进入"债务消化"窗口。

---

## §1 一页纸摘要(评委用)

| 维度 | 值 |
|---|---|
| **项目名 / 包名** | MindTrace / `entry`(HAP) + `common` / `agents` / `skill` / `cardservice`(4 HSP) |
| **比赛** | 鸿蒙高校创新赛 · 复赛 |
| **平台** | HarmonyOS(`runtimeOS: HarmonyOS` / `targetSdkVersion: 6.1.1(24)` / `compatibleSdkVersion: 6.1.1(24)`) |
| **核心能力** | 数学拍照 OCR → LLM 解析 → KaTeX 渲染回 ArkUI WebView;5 类题型(概念/定理/公式/证明题/计算题)自动分类;KnowledgeUnit 结构化 + 知识星系图谱可视化;AI 助手浮窗 + 复习浮窗 SSE 流式对话 |
| **业务亮点** | (a) `Dispatcher` 主调度 + `TypeClassifier`/`KnowledgeModel` 子 agent 端到端 LLM pipeline;(b) W4 多 WebView 分块渲染(突破 ArkUI 1800vp 高度上限,公式块无上限 + `LazyForEach` 按需创建);(c) `MM-MD-v1` 内容协议统一 AI/OCR/历史三源 + `LatexRiskNormalizer` 风险归一化 |
| **工程亮点** | (a) 自研 `scripts/arkts-lint/` AST 引擎 — **34 规则 / 63/63 测试通过 / CI 已接入**,取代 v1 正则(消除 ~80% 误报);(b) **7 ADR + 6 ticket spec + 162 文件 23,301 LOC 全量架构审计**(总评级 🟡 可工作但分层混乱);(c) GitHub Actions CI + `permissions: contents: read` hardening;PR 模板 + 5 标签 triage 工作流 |
| **测试基线** | Hypium ArkTS 测试 12 个(ADR-0007 基线)+ arkts-lint Node 测试 63 个 = **75 个测试** |
| **当前状态** | W4 增量清晰(渲染层 + 缓存优化);已修 #15 ArkTS 铁律 / #9 LlmConfig 静默覆盖(TDD) / #16 fixture data 泄漏(TDD);待修 #1 doc expiry / #3 KnowledgeModel 870 LOC god class / #4 Dispatcher 双入口 / #5 LLMClient 三路径 / #7 AgentChatService 802 LOC / #10 mcp→tools rename |
| **风险信号** | 远程仓库 `YunC-GCT/MindTrace` 在当前环境全部 404(本地 origin 指向它,大概率私有 + 无凭证);`AGENTS.md` 中"最后审计 2026-09-01 / HEAD 29df511" 与现实 HEAD `5963493` 不一致(审计 §4.16 已点);6 spec 全部 "spec ready, not implemented",0 个落地 |
| **仓库结构骨架** | 5 module 依赖方向单向无环:`entry → {common, agents}`;`{skill, cardservice} → {common, agents}`;`agents → common`;`common` 叶子 |

**三句 elevator pitch**:
1. **做什么**:HarmonyOS 数学学习助手,拍照拍题 → OCR + LLM 拆解为 KnowledgeUnit → 5 类题型自动分类 → 知识星系图谱可视化 → 复习浮窗 AI 助教 SSE 流式对话。
2. **做得怎么样**:W4 渲染层突破 ArkUI 1800vp 高度上限(公式块无上限,文本块虚拟化);5 套 Hypium 单测全过;自研 AST lint 引擎替代正则(消除 80% 误报,补齐 9 条新规则)。
3. **接下来**:把 6 份已写好的 spec(其中 #4 Dispatcher 单入口最小,#10 mcp→tools rename ~3 行)按推荐顺序消化,让架构匹配 ADR 意图。

---

## §2 项目身份(技术画像)

**来源**: `AGENTS.md`, `build-profile.json5`, `entry/oh-package.json5`, `common/oh-package.json5`, `agents/oh-package.json5`, `skill/oh-package.json5`, `cardservice/oh-package.json5`, 本地 `git status/log/remote -v`。

| 字段 | 值 | 引用 |
|---|---|---|
| 项目名 | **MindTrace**(README / AppScope / docs 一致) | `README.md` L1, `AppScope/app.json5` |
| 仓库本地路径 | `<本地仓库根>` | `AGENTS.md` L7 |
| 远程仓库 | `git@github.com:YunC-GCT/MindTrace.git`(当前环境 404) | `git remote -v` |
| 主分支 | `main`;AI 工作分支 `YunCeH` | `AGENTS.md` L5, `docs/agents/git-conventions.md` |
| 当前 HEAD | `5963493 fix(ci): add 'permissions: contents: read' to both workflows`(on `YunCeH`,与 `main` 同步) | `git log -1` |
| 工作树状态 | clean,无未提交改动 | `git status` |
| Tag / Release | 无(`git tag` 空,`git describe --tags` fatal) | `git tag`, `git describe` |
| 比赛 | 鸿蒙高校创新赛 · 复赛 | `AGENTS.md` L1 |
| 当前版本 | **W4**(自 2026-07-24 起) | `AGENTS.md` L5, `README.md` L9 |
| 最后审计 | 2026-09-01(HEAD 基线 `29df511`,审计期落后当前 HEAD 19 个 commit) | `AGENTS.md` L6, `audit-full-2026-09-01.md` L4 |
| SDK | `modelVersion=6.1.1`, `targetSdkVersion=6.1.1(24)`, `compatibleSdkVersion=6.1.1(24)`, `runtimeOS=HarmonyOS` | `build-profile.json5` L8-10 |
| Strict mode | `caseSensitiveCheck: true`, `useNormalizedOHMUrl: true` | `build-profile.json5` L12-15 |
| 顶层目录数 | 18 项,含 5 module + `AppScope/` + `docs/` + `scripts/` + `tools/` + 构建缓存(`build/` `hvigor/` `oh_modules/`) | `AGENTS.md` L14-25 |

**关键备注**:
- **HEAD 不一致**:`AGENTS.md` / `git-conventions.md` 引用的基线 `29df511` 与现 HEAD `5963493` 间隔 19 个 commit(都是 docs/lint/CI 收尾工作),审计 §4.16 标记为 🔴 P0(过期元数据)。本次定位报告以现 HEAD 为准。
- **远程不可达**:本环境 `gh` CLI 未安装 / `curl` 全 404,详细分析见 §8。
- **未发布 tag**:项目处于"git 工作流成熟但未走 release 流程"状态,与复赛时间窗口吻合。

---

## §3 模块拓扑 + 依赖图

**来源**: 5 个 `oh-package.json5`, `audit-full-2026-09-01.md` §1.2 + §3。

| Module | 类型 | `main` | LOC | 直接依赖 |
|---|---|---|---|---|
| `entry` | HAP (`type:entry`) | `""`(空) | 17,719 / 123 文件 | `common`, `agents`(ADR-0001 允许直接跨层) |
| `common` | HSP (`type:shared`) | `./src/main/ets/Index.ets` | 3,580 / 22 文件 | —(叶子) |
| `agents` | HSP (`type:shared`) | `./src/main/ets/Index.ets` | 1,930 / 9 文件 | `common` |
| `skill` | HSP (`type:shared`) | — | 14 / 2 文件 | `common`, `agents` |
| `cardservice` | HSP (`type:shared`) | — | 58 / 6 文件 | `common`, `agents` |
| **合计** | | | **23,301 / 162 文件** | |

> 注:`module.json5` 中 `common/agents/skill/cardservice` 的 `type` 字段是 `"shared"`,而非字面 `"hsp"`;"4 HSP" 是行业统称,审计报告沿用。

**依赖图(单向无环)**:

```
entry  ──► common
entry  ──► agents          (ADR-0001 允许)
skill  ──► common, agents
cardservice ──► common, agents
agents ──► common          (无反向)
common ──► (叶子)
```

**模块职责对照表**(审计 §2 + CONTEXT.md):

| Module | 职责 | 关键导出 |
|---|---|---|
| `entry` | UI 渲染 + 业务编排 + 拍照/相册 + DB 读写 | 5 Tab 页(`Home` `Notes` `AiSettings` `Review` `Profile`)+ 浮窗(`AgentFloatWindow` `CameraOverlay` `NoteDetailOverlay`)+ viewmodels(7)+ services(6)+ DAO(4) |
| `common` | 共享类型 + LLM/Render/OCR config + DB 助手 + Mock 数据 | `LlmClient` / `LlmGuard` / `LlmConfig` / `ContentProtocol`(MM-MD-v1)/ `LatexRiskNormalizer` / `MathTextParser` / `DatabaseHelper` / `ColorTokens` |
| `agents` | AI 业务 — 主调度 + 子 agent + OCR 工具 + 领域模型 | `Dispatcher`(159 LOC, 3 公开方法待合一)/ `TypeClassifier`(333)/ `KnowledgeModel`(870 🔴)/ `OcrTool`(394 🔴)/ `KnowledgeCategory` / `KnowledgeUnitExt` / `NoteDaoInterface` / `TruthCheckResult` |
| `skill` | 技能卡片(Feature Ability 入口) | 2 文件,14 LOC |
| `cardservice` | 卡片服务(FormExtensionAbility) | 6 文件,58 LOC |

**架构判断**:
- ✅ 跨模块依赖方向干净,无反向依赖,符合 HarmonyOS HAP/HSP 规约
- ✅ `agents` 不 import `entry` / `skill` / `cardservice`,AI 业务可独立测试
- 🟡 `entry/services/` 直接 `from 'agents'` 是 ADR-0001 批准的临时豁免,无接口层(`IAiService` 待加)

---

## §4 业务亮点

**来源**: `README.md`, `agents/src/main/ets/agents/`, `common/src/main/ets/llm/`, `entry/src/main/ets/pages/`, `audit-full-2026-09-01.md` §2-§4。

### 4.1 AI 业务核心(亮点 1:端到端 LLM pipeline)

| 文件 | LOC | 角色 |
|---|---|---|
| `agents/core/Dispatcher.ets` | 159 | 主调度中枢,3 公开方法(`analyze` / `dispatch` / `routeDispatch`,后两者待合一只剩 `dispatch`,见 ADR-0003 + spec #4) |
| `agents/agents/TypeClassifier.ets` | 333 | 5 类题型识别(概念/定理/公式/证明题/计算题),`CONTEXT.md` NoteType 定义 |
| `agents/agents/KnowledgeModel.ets` | **870** | 🔴 God class,做 ≥7 件事(structuring + AI call + JSON validate + truth check + latex fix + prompt build + fallback),待按 ADR-0006 拆 `PromptBuilder` + `TruthCheckService` + `StructureService` |
| `agents/mcp/tools/OcrTool.ets` | 394 | OCR 工具(实际是 HTTP 客户端,目录名 `mcp/` 误导,待按 ADR-0005 重命名为 `tools/`) |

**关键 seam**(CONTEXT.md `Dispatcher` 定义):
```
AiService.capture → Dispatcher.dispatch → KnowledgeModel.structure → LlmClient.call → LlmGuard
                                                          ↓
                                              ContentProtocol (MM-MD-v1)
```
所有 Markdown 内容走 `ContentProtocol`(MM-MD-v1),统一 AI / OCR / 历史三源 `summary / markdown / raw` 三段结构。

### 4.2 渲染协议层(亮点 2:跨三源协议 + LaTeX 风险归一化)

**来源**: `common/src/main/ets/llm/`, `common/src/main/ets/render/`, README L29-33。

| 组件 | 角色 |
|---|---|
| `LlmGuard` + `LlmOutputRules` | LLM 输出多通道守卫(类型/字段/风险/HTML 转义),失败返回结构化 `LlmGuardReport` |
| `LatexRiskNormalizer` | LaTeX 风险归一化 — 把裸 `\\frac` / 缺失定界符 / 误用 `*` 转义等编译失败模式换成安全等价形式 |
| `ContentProtocol`(580 LOC) | `MM-MD-v1` 协议归一化 AI/OCR/历史三源;摘要按公式边界安全截断(不切 `$...$` 内部) |
| `ContentExcerptBuilder` | 摘要构造,适配公式边界 |
| `MathTextParser` | 行内 `$...$` / `$$...$$` / `\(...\)` / `\[...\]` 四种定界符混排 |

### 4.3 渲染组件层(亮点 3:W4 多 WebView 分块突破 1800vp 上限)

**来源**: `README.md` L9-27, `entry/src/main/ets/shared/components/`, `entry/src/main/ets/pages/`。

**核心问题**: ArkUI Web 组件在此设备上有 **1800vp 高度上限**,超过后 WebView 完全空白(非截断);此前 `clampHeight` 强行限制 + 内部滚动导致 List + WebView 双重滚动。

**W4 解决方案**:
- `FormulaSplitRenderer`(245 行):按 `$$` 拆分 markdown 为 `FormulaBlock[]`,合并相邻文本块(减少 ~40% WebView),公式块 `forceDisplay=true` 无高度上限,文本块 ≤1800vp
- `FormulaBlockDataSource` 实现 `IDataSource` + `LazyForEach`:仅可见 block 持有 WebView 实例,滚出视口自动销毁
- `splitLongTextBlocks()`:超 1500 字符按 `\n\n` 段落边界二次拆分,防极端超长纯文本 >1800vp 截断
- block 硬上限 30,防 OOM
- `render.html` 新增 `renderFormula` / `renderFormulaForCache` bridge:公式块跳过 `marked.parse` + `renderMathInElement` 全 DOM 扫描,直接 `katex.renderToString(innerTex, {displayMode:true})` — **快 ~30-50%**

**5 类专属 renderer**(NoteDetail): `Computation` / `Concept` / `Fallback` / `Formula` / `Proof` / `Theorem`,统一走 `DetailSection + DetailStepList + DetailMetaFooter`。

### 4.4 缓存与预加载(W3.5 优化)

**来源**: `README.md` L46-50。

- `UiDataCacheService`:主页 + 学科页 + 详情页三段式数据缓存,带 `UiCacheDebug` 调试面板
- `MarkdownParseCache`:block / inline 双层缓存,带总字符预算和超大条目绕过
- 笔记列表查询改用元数据,不再批量读 `content` / `embedding` / 关系字段
- `DetailRenderModel` + `DetailRenderCache`:元数据与节点树分离,LRU 限制 8 条 / 512KB
- `DetailRenderQueue`:二阶段 `List + LazyForEach` 虚拟化,首次仅挂 3 节点,"继续阅读"每次追加 3 节点

### 4.5 5 Tab 主页(无 fixture data 泄漏)

**来源**: `entry/src/main/ets/pages/`, ticket #16 已修。

5 Tab: `Home` / `Notes` / `AiSettings` / `Review` / `Profile`。`ReviewGraphView`(1880 LOC,🔴 最大文件)+ `KnowledgeGalaxyViewModel`(735 LOC,🟡)实现知识星系图谱可视化,ticket #16 修复后已无 `ENABLE_GALAXY_PREVIEW_UNITS=true` 的 fixture data 泄漏到生产。

---

## §5 工程亮点

**来源**: `scripts/arkts-lint/README.md`, `scripts/arkts-lint/` 目录, `.github/workflows/`, `audit-full-2026-09-01.md`。

### 5.1 ArkTS 1.1 strict lint 引擎(自研 AST,亮点 1)

| 指标 | v1 (regex) | arkts-lint (AST) | 变化 |
|---|---|---|---|
| 规则数 | 25 | **34** | +9 |
| 实际可执行规则 | 23(2 禁用) | **34** | +11 |
| 单元测试 | 0 | **63/63 pass** | 新增 |
| 真实 errors | 0 | **0** | CI ✅ |
| Warnings | 285(≈80% 误报) | **253**(高质量) | -11% 总数,但 90 个是真问题 |
| Parse errors | 0(regex 不需要) | **91**(新信息!) | 揭示 v1 看不见的 12% 文件 |
| 状态 | 灰度保留 | **Day 3 完成 2026-09-01** | |

**目录结构**(`scripts/arkts-lint/`):
```
parser/        # @typescript-eslint/parser + ArkUI preprocessor
ast-utils/     # walk.mjs + has-decorator.mjs
rules/
  official/    # 23 个 ArkTS 1.1 官方规则
  project/     # 2 个项目偏好规则 (no-get-accessor / struct-no-regular-methods)
fixtures/{pass,fail}/   # 测试 fixture
tests/         # 6 测试 + run-rule.mjs
README.md      # 状态条 + 维护手册
```

**关键技术**: AST 上下文(`parent`, `parentMap`)让 arkts-lint 正确区分 method body vs 独立 expression,解决 v1 三大误报源(`no-func-expressions` / `no-nested-funcs` / `no-destruct-params`)。对应 Phase 4 ticket #15,已修。

### 5.2 审计 + ADR + Spec 完整设计层(亮点 2)

**审计基线**:
- `docs/legacy/mindtrace/architecture/audit-full-2026-09-01.md`:全代码库架构审计主报告,**162 文件 / 23,301 LOC**
- 总评级 🟡 "可工作但分层混乱"
- 21 个 finding,分类:
  - 🔴 P0(4 条):LLM 三套调用路径并行(§4.1)/ `KnowledgeModel` 870 LOC god class(§4.2)/ `AgentChatService` 802 LOC god class(§4.3)/ Production fixture data 泄漏(§4.20)
  - 🔴 其他: `AGENTS.md` 路径错误/过期(§4.16)、"禁 C 风格 for" 规约理解错(§4.17)
  - 🟡 P1(11 条): `LlmConfig` 静默覆盖(§4.4)/ `Dispatcher` 双入口(§4.5)/ `OcrTool` C-style for(§4.6)/ `ContentProtocol` 580 LOC(§4.7)/ `mcp/` 空壳(§4.8)/ `ReviewGraphView` 1880 LOC(§4.9)/ `KnowledgeGalaxyViewModel` 789 LOC + P0 BUG(§4.10)/ UTF-8 手写编码(§4.11)/ ArkTS 1.1 规则表覆盖率 ~10%(§4.18)/ `compatibleSdkVersion < 10` 不强制(§4.19)/ `extractJsonObject` 正则在嵌套 JSON 上截断(§4.21)
  - 🟢 P2: agent 术语重载(§4.12)/ 文件头模板覆盖不均(§4.13)/ 缺 `CONTEXT.md` + `docs/adr/`(§4.14,已部分解决)/ 模块命名误导(§4.15)
- `docs/legacy/mindtrace/architecture/deep-dive-2026-09-01.md`:7 个最大文件的 deep-dive(§F1 ReviewGraphView、§F2 KnowledgeGalaxyViewModel、§F3 extractJsonObject 等)

**ADR 层**(`docs/adr/`,7 篇 + index):
| ADR | 决定 |
|---|---|
| 0001 | 允许 `entry/services/` 直接 import `agents/`,不强制引入 `IAiService` 接口(5+ service 触发时再加) |
| 0002 | 保留代码命名 `Agent*`;仅迁移用户可见文案("AI 助手"),不做全量 rename |
| 0003 | `Dispatcher` 折叠为 1 个 `dispatch(req, opts?)`,删 `routeDispatch`,`analyze` 降为内部步骤 |
| 0004 | `LlmClient` 三方法合一为 `call(opts)`,`LlmGuard` 改为可选 wrapper,删 `callSseTokens` |
| 0005 | `agents/mcp/tools/` → `tools/`;项目未运行 MCP server,目录名是假宣传 |
| 0006 | `KnowledgeModel`(870 LOC)拆为 `StructureService` + `TruthCheckService` + `PromptBuilder` |
| 0007 | 测试基线定为 12 个 Hypium 单元测试(对应 ticket #13) |

**Spec 层**(`docs/specs/`,6 份 + index): 全部 `spec ready, not implemented`(除 #9 标 `spec for review (Phase 3)`)。**0 个 spec 落地**。

### 5.3 CI / 工作流(亮点 3)

**来源**: `.github/workflows/`,最近 commit `5963493`, `2fb5e92`。

- `.github/workflows/` 含 CI 守门,最近加固:`permissions: contents: read`(最小权限原则,符合 `docs/agents/security.md`)
- `scripts/naming-lint/` 命名规范守门(CI 自动跑)
- `scripts/link-check/` 死链扫描
- `scripts/audit-arkts-strict.mjs` v1 lint 引擎(灰度保留,与 arkts-lint 并行)
- `docs/agents/ci-failure-workflow.md` CI 失败排查手册
- PR 模板 + 5 标签 triage 工作流(`needs-triage` / `needs-info` / `ready-for-agent` / `ready-for-human` / `wontfix`)

### 5.4 命名与目录规范(亮点 4)

**来源**: `docs/style/naming-conventions.md`, `.naminglintrc.json`。

7 条硬约束: UPPERCASE 顶级 doc / kebab-case 目录与配置 / `YYYY-MM-DD` 日期后缀 / PascalCase React 组件 / snake_case Python + PascalCase class / 测试文件 `*.test.{ts,tsx,mjs,py}` / 重命名必须 `git mv`。`node scripts/naming-lint/index.mjs` CI 守门。

---

## §6 文档层全景

**来源**: `AGENTS.md` "改什么 → 读哪" 表, `docs/` 完整目录。

| 子目录 | 文件数 | 角色 | 引用入口 |
|---|---|---|---|
| `docs/adr/` | 7 + index | 架构决策记录(why) | `docs/adr/index.md` |
| `docs/specs/` | 6 + index | 实施 spec(how)— 6 个 ticket 对应 | `docs/specs/index.md` |
| `docs/agents/` | 12 + `patterns/` | agent 工作流治理 | `docs/agents/agent-glossary.md`(通用 agent 术语) / `docs/agents/domain.md`(域文档消费规则) |
| `docs/legacy/mindtrace/architecture/` | 7 | 审计基线 + deep-dive + lint baseline | `docs/legacy/mindtrace/architecture/audit-full-2026-09-01.md` |
| `docs/legacy/mindtrace/plans/{w3,w4}/` | 多 | 阶段计划(W3 渲染协议 / W4 多 WebView 分块) | `README.md` 中提到的 plan 文件 |
| `docs/legacy/mindtrace/research/` | 多 | 调研支撑(多 WebView 性能 / 公式渲染策略) | `README.md` 中提到的 research 文件 |
| `docs/research/` | 4(2 md + 2 html) | 一手调研产物(agent framework / langgraph migration / 本报告) | `docs/research/` |
| `docs/style/` | 2 | 编码规范权威源(arkts-1.1.md / naming-conventions.md) | `docs/style/` |
| `docs/template/` | 多 + index | ADR / spec / research / agent-workflow 模板 | `docs/template/index.md` |
| `docs/` 顶层 | `index.md` / `onboarding.md` | 项目入口 | `docs/index.md` |

**关键判断**:
- ✅ 设计层透明度极高:从 ADR(why) → spec(how) → audit(what's wrong)→ template(标准模板)→ research(调研底料),五层齐全
- ✅ 文档有 owner 和引用规范,`AGENTS.md` 的"改什么 → 读哪"表是清晰的导航
- 🟡 `CONTEXT.md` 与 `docs/agents/agent-glossary.md` 已分层(2026-09-02 迁移 note),术语治理到位

---

## §7 状态盘点(债务 vs 已修)

**来源**: `AGENTS.md` "状态"段, `docs/specs/index.md`, `audit-full-2026-09-01.md` §4/§6/§7。

### 7.1 ✅ 已修

| Ticket | 内容 | 方式 |
|---|---|---|
| **#15** | ArkTS 铁律(规约错误) — "禁 C 风格 for" 实为 "禁 for..in" | arkts-lint AST 引擎补齐规则(§4.17) |
| **#9** | `LlmConfig.normalizeModel/Endpoint` 静默覆盖 → 抛错 | TDD(spec #9 已写,待 review) |
| **#16** | Production fixture data 泄漏(`ENABLE_GALAXY_PREVIEW_UNITS=true`) | TDD(arkts-lint 测试 + 源码改) |

### 7.2 🟡 待修(6 份 spec 已就位,等开工)

**来源**: `docs/specs/index.md` "Implementation order (recommended)"。

| 优先级 | Ticket | Spec | 概要 | 工作量 |
|---|---|---|---|---|
| 1 | **#4** | `004-dispatcher-single-entry.md` | `Dispatcher` 缩到单公开方法 + 迁移 `AiService` 调用方 | S(最小爆炸半径) |
| 2 | **#5** | `005-llm-client-consolidation.md` | `LlmClient` 合一调用路径(3 → 1) | S(~5 行 refactor) |
| 3 | **#3** | `003-knowledge-model-decomposition.md` | `KnowledgeModel` 拆 3 服务 + 对应 Hypium 测试 | L(870 LOC,3 atomic PR) |
| 4 | **#7** | `007-agent-chat-service-decomposition.md` | `AgentChatService`(802 LOC)拆 `IntentClassifier` + `ReplyService` + `ChatStatusMachine` | L(802 LOC,3 atomic PR) |
| 5 | **#10** | `010-mcp-to-tools-rename.md` | `mcp/tools/` → `tools/` 的 `git mv` + import 修正 | XS(~3 行) |
| 6 | **#9** | `009-llm-config-throw-on-silent-override.md` | `LlmConfig` 静默覆盖改抛错 | XS(~10 行) |

### 7.3 🟢 其他已识别但未列入 spec 的债务

| Ticket | 内容 | 来源 |
|---|---|---|
| **#1** | doc expiry(AGENTS.md / git-conventions.md 过期) — 元工作,无 spec | audit §4.16 |
| **#11** | `OcrTool.strToUtf8` 改用 `util.TextEncoder` | audit §4.11,XS |
| **#12** | `ReviewGraphView` 1880 LOC 拆分 | audit §4.9,L |
| **#14** | smoke test 矩阵覆盖 W4 SSE 流式 | docs/agents/smoke-test.md |
| **#17** | `extractJsonObject` 非贪婪正则 bug | audit §4.21,S |
| §4.18 | ArkTS 1.1 strict 规则表覆盖率 ~10%(仅警告) | audit |
| §4.19 | `compatibleSdkVersion < 10` → strict 规则仅警告不报错 | audit |

### 7.4 架构演进后应达到的状态(per spec/index.md)

> After all 6, the architecture should match ADR intent:
> - Dispatcher has 1 public method
> - LLMClient has 1 public method (call + adapters)
> - KnowledgeModel doesn't exist; replaced by 3 services
> - AgentChatService is a thin facade
> - mcp/ directory doesn't exist

---

## §8 远程视角(本地三角验证)

**来源**: `curl --ssl-no-revoke` 直连 GitHub API 与 HTML(本环境 404),本地 `git remote -v`, `README.md`, 最近 30 commit 主题分布, `docs/onboarding.md`(若有), `docs/index.md`(若有)。

### 8.1 远程可达性结论

| 探测 | 结果 |
|---|---|
| `gh` CLI | 未安装 |
| `curl https://api.github.com/repos/YunC-GCT/MindTrace` | **HTTP 404** |
| `curl https://github.com/YunC-GCT/MindTrace` | **HTTP 404** |
| 用户 `YunC-GCT` 公开仓库列表 | 只有 `YunC-GCT/SIT`(Python),无 `Math-Mind` |
| 拼写变体穷举 | `YunC-GCT/MathMind` / `Yun-C-GCT/Math-Mind` / `YunC-GCT/Math_Mind` 全部 404 |

**最可能原因**:
1. 仓库私有 + 当前环境无凭证(GitHub API 对私有无认证直接 404)
2. 仓库被删除/重命名(用户名下零 `Math-Mind` 命中,排除重命名到同 owner)
3. 凭证缺失(本地 `git remote -v` 显示 `git@github.com:YunC-GCT/MindTrace.git`,与本地 origin 一致)

**后续可补**: 在能访问 `YunC-GCT/MindTrace` 的环境里重跑 `gh repo view --json ...`,把 JSON 贴回可补全远程视角。

### 8.2 本地三角验证的"远程视角"信号

**信源 1: README 自陈**(`README.md` L1-5)
- 项目名: MindTrace
- 工程链接: [YunC-GCT/MindTrace](https://github.com/YunC-GCT/MindTrace)
- 作者: YunC-GCT `<2549237929@qq.com>`,当前主笔: Z
- 最近更新: 2026-09-01
- 头注自述: "全代码库架构审计 + arkts-lint v0.3 (AST) + GitHub Actions CI 已落地"

**信源 2: commit 主题分布**(本地 `git log --oneline -30`)
- **当前阶段**: 文档工程 + lint/CI 工具链收尾
- **比例**: docs 治理类 16 条 / lint 工具 6 条 / CI workflow 6 条 / link-fix 2 条 / 无功能 commit
- **结论**: 项目处于"架构审计收尾 → 工具化收尾"阶段,功能层 W3.5 已验证通过

**信源 3: docs/ 索引**
- `docs/onboarding.md` + `docs/index.md` 形成清晰的"面向 AI agent 的文档骨架"
- `docs/adr/` 与 `docs/specs/` 编号不连续(specs 缺 001/002/006/008,ADR 缺 0008+),反映 spec 在更名/合并/淘汰
- `docs/legacy/mindtrace/architecture/` 在 2026-09-01 一次性产出 audit / deep-dive / lint baseline 整套归档(命名带日期)

**信源 4: README 中的"无"信号**
- 无 demo URL
- 无截图
- 无 badges
- 无 deployment 节
- 无社交预览图

**判断**: 项目的对外可见身份高度依赖 README 引言 + `docs/` 完整 ADR/spec/agent 文档骨架,**定位非常清晰:面向 HarmonyOS 的数学学习助手,重点在渲染协议层 + LLM 安全归一化 + AI agent 协作工程实践**。缺的是"对评委友好的视觉物料"(截图 / demo / 部署指南)。

---

## §9 后续动作清单

### 9.1 给评委(5 分钟 pitch)

| 优先级 | 动作 |
|---|---|
| 高 | **补 demo URL / 截图 / 视频**:目前 README 没有视觉物料,这是评委快速理解项目的最大缺口 |
| 高 | **一句话项目定位**:"HarmonyOS 数学学习助手,拍照拍题 → AI 拆解 → 知识结构化 → 复习对话" |
| 中 | **亮点三选一聚焦**:(a) W4 多 WebView 分块突破 ArkUI 1800vp 上限 + 公式渲染快 30-50%;(b) MM-MD-v1 内容协议统一三源 + LaTeX 风险归一化;(c) 自研 AST lint 引擎 + 7 ADR + 6 spec 完整工程治理 |
| 中 | **风险信号透明**:不掩盖"5 spec 待实施 / 远程仓库访问受限 / 文档过期"问题,反而是设计透明度的体现 |

### 9.2 给团队(对齐用)

| 优先级 | 动作 |
|---|---|
| 高 | **消化 6 份 spec**:按推荐顺序 #4 → #5 → #3 → #7 → #10 → #9 实施 |
| 高 | **修 AGENTS.md 过期**:最后审计日期 + HEAD SHA + tag/release 状态(ticket #1,元工作) |
| 中 | **远程仓库可达性**:owner 在自己终端跑 `gh repo view` + `gh release list`,确认公开/私有状态 |
| 中 | **新增 ADR-0008**:把"AST lint 引擎作为项目一等公民"写入 ADR 决策(目前只在 README/状态条,未走 ADR 流程) |
| 低 | **覆盖率扩 40%**:ArkTS 1.1 规则表覆盖率从 10% 扩到 30%(audit §4.18) |

### 9.3 后续 to-spec 入口(本次定位到为止,不在本次范围)

如果决定要把 §7.2 的 6 份 spec 转化为可执行的 ticket,推荐路径:
1. 走 `/to-spec` 把每个 spec 折叠成 issue tracker ticket
2. 走 `/to-tickets` 拆成 tracer-bullet,声明 blocking edges
3. 走 `/implement` per ticket,每个 ticket 跑 `/code-review`(Standards + Spec 双轴)

---

## §10 数据源路径索引

> 本报告引用的所有一手信源,便于回查。

**项目入口**:
- `<本地仓库根>\AGENTS.md`
- `<本地仓库根>\README.md`
- `<本地仓库根>\CONTEXT.md`
- `<本地仓库根>\build-profile.json5`

**5 module 清单**:
- `entry/oh-package.json5` `common/oh-package.json5` `agents/oh-package.json5` `skill/oh-package.json5` `cardservice/oh-package.json5`

**业务核心**:
- `agents/src/main/ets/core/Dispatcher.ets`
- `agents/src/main/ets/agents/TypeClassifier.ets`
- `agents/src/main/ets/agents/KnowledgeModel.ets`
- `agents/src/main/ets/mcp/tools/OcrTool.ets`
- `common/src/main/ets/llm/LlmClient.ets` `LlmGuard.ets` `LlmConfig.ets` `LlmOutputRules.ets` `LlmTypes.ets`
- `common/src/main/ets/render/ContentProtocol.ets` `ContentExcerptBuilder.ets`
- `common/src/main/ets/utils/LatexRiskNormalizer.ets`

**渲染层**:
- `entry/src/main/ets/shared/components/MathTextRenderer.ets`
- `entry/src/main/ets/shared/components/FormulaSplitRenderer.ets`
- `entry/src/main/ets/pages/Home/` `pages/Notes/` `pages/AiSettings/` `pages/Review/` `pages/Profile/`

**工程层**:
- `scripts/arkts-lint/README.md` `index.mjs` `parser/` `ast-utils/` `rules/official/` `rules/project/` `fixtures/` `tests/`
- `.github/workflows/`
- `scripts/naming-lint/` `scripts/link-check/` `scripts/audit-arkts-strict.mjs`

**文档层**:
- `docs/adr/index.md` + 7 ADR
- `docs/specs/index.md` + 6 spec
- `docs/agents/`(12 文件 + `patterns/`)
- `docs/legacy/mindtrace/architecture/audit-full-2026-09-01.md` `deep-dive-2026-09-01.md` `lint-baseline-2026-09-01.json` `lint-baseline-ast-2026-09-01.json`
- `docs/style/arkts-1.1.md` `naming-conventions.md`
- `docs/template/` + `docs/index.md` + `docs/onboarding.md`
- `docs/research/agent-framework-comparison-2026-09-02.md`
- `docs/research/langgraph-migration-2026-09-02.md`
- `docs/research/project-positioning-2026-09-04.md`(本报告)

**git 引用**:
- HEAD: `5963493 fix(ci): add 'permissions: contents: read' to both workflows`
- 审计基线: `29df511` on `main` (2026-09-01)
- 最近 30 commit 主题集中在 docs/lint/CI 收尾

---

## §11 元数据 + 维护

| 字段 | 值 |
|---|---|
| 报告作者 | 主 agent + research 后台 agent |
| 报告日期 | 2026-09-04 |
| 报告类型 | 项目定位(摘要 + 详细双节) |
| 评审基准 | AGENTS.md "改什么 → 读哪" 表 + docs/style/naming-conventions.md |
| 命名合规 | 遵循 `YYYY-MM-DD` 日期后缀 + kebab-case |
| 后续维护 | 与 W5 / W6 等新版本叠加时,新开 `docs/research/YYYY-MM-DD-project-positioning-vN.md`,旧版转 `docs/legacy/` |
| 与审计关系 | 不替代 `audit-full-2026-09-01.md`,定位报告偏团队/评委,审计报告偏技术债务 |
| 与 ADR 关系 | 不替代 `docs/adr/`,定位报告描述现状,ADR 解释 why |
