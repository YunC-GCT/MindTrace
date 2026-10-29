# 文档规范 / 设计冲突 / 可追溯性审计（2026-10-18）

> **范围**: `docs/` 全部 186 篇 + 根 `AGENTS.md` / `CONTEXT.md` + `scripts/arkts-lint` / `scripts/doc-trace`。
> **方法**: 链接图遍历、状态字段扫描、spec/ADR 头与索引对读、代码/测试实测（`npm --prefix scripts/arkts-lint test`、`node --test scripts/arkts-lint/tests/*.test.mjs`）。
> **结论**: 链接层已经闭合；状态层和“文档 → 代码 → 测试”的证据层仍有缺口；本轮修掉 9 处明确冲突，并补了 AI coding 入口与追溯检查器。

---

## 1. 结论摘要

| 维度 | 审计前 | 处理 |
|---|---|---|
| 文档可达性 | `docs/index.md` 只把目录索引写成纯文本，链接图实际不可达 185 篇 | 目录索引改为真链接；新增 `scripts/doc-trace` 守门 |
| 目录索引 | 0 缺失、0 orphan（上轮已修） | 保持；新增可达性检查 |
| 状态一致性 | spec 头与 `docs/specs/index.md` 有 4 处不一致 | 修 3 处；1 处（spec 027）留待补 Status |
| 技术冲突 | 9 处明确冲突 / 过期论断 | 全部修正（见 §2） |
| AI coding 入口 | `arkts-1.1.md` 可读但 502 行、无压缩入口；lint 指标 4 处互相矛盾 | 新增 `arkts-ai-coding.md`；统一指标口径 |
| 文档 → 代码证据 | `Code` / `Verified by` 字段无约定 | 新增 `document-control.md` 控制块约定 |

---

## 2. 已修正的设计 / 文档冲突

| # | 冲突 | 证据 | 修正 |
|---|---|---|---|
| 1 | `AGENTS.md` 标题写“必守红线 7 条”，正文列了 8 条 | `AGENTS.md` §必守红线 | 改为 8 条 |
| 2 | `AGENTS.md` 称 `AgentChatService` 76 LOC，实际 70 行 | `wc -l entry/src/main/ets/services/AgentChatService.ets` = 70 | 改为“约 70 LOC” |
| 3 | `AGENTS.md` 把 `atoms/` 整体列为废弃，但 `entry/src/main/ets/shared/atoms/` 是 spec 012 的现行结构 | `ls entry/src/main/ets/shared`；spec 012 状态 | 废弃项限定为顶层 `entry/src/main/ets/components/`、`entry/src/main/ets/atoms/`，并注明 `shared/atoms` / `shared/molecules` 现行 |
| 4 | `AGENTS.md` 的“LLM 截断 gotcha”说聊天浮窗会抛 `LLM response truncated by max_tokens`；实际上聊天回复已改为 partial + 截断标记，只有 note generation 的 `GenerationJsonCaller` 抛 `LLM_TRUNCATED` | `LlmClient.ets:565-567`、`LlmResponseParser.ets:23-82`、`GenerationJsonCaller.ets:133-140` | 重写该段，区分“聊天降级”与“生成 JSON 抛错” |
| 5 | lint 指标四处不一致：AGENTS `707 tests`、README `63/63`、api-version `63 单元测试`、agent-tools `89 单测` | 实测：`npm test` 329/329；`node --test tests/*.test.mjs` 707 / 692 pass / 15 fail | AGENTS、README、api-version 统一为“34 规则；curated 329 全绿；全量 707，15 项既有失败基线”；历史表标注快照 |
| 6 | `arkts-1.1.md` 项目规则第 9 条写“`agents/mcp/tools/` 计划改名 `tools/`”，与 ADR-0010 的“保留 mcp/”直接冲突 | ADR-0010；`CONTEXT.md` MCP 工具词条 | 改为保留 MCP 语义、CRUD 工具放 `tools/`，注明改名已撤销 |
| 7 | spec 021 头部仍写 `proposed`，索引已改为 `implemented in develop` | `docs/specs/021-*.md:3` vs `docs/specs/index.md` | 头部同步为 `implemented in develop; device acceptance pending` |
| 8 | spec 003 头部写 `spec for review`，索引写 `superseded by 015` | spec 003 / specs index | 头部改为 `superseded by spec 015` |
| 9 | spec 017 头部 `implemented`（L1–L6 完成），索引仍写 `draft` | spec 017 / specs index | 索引改为 `implemented` |

> 另外发现但**未改**的一处：ADR-0017 标题写 “device measurement”，正文与索引承认证据来自 DevEco 模拟器、设备目标 NOT_MET。这是“标题措辞 vs 证据等级”的张力，不是事实错误；是否改标题需要 owner 裁决，故只记录在 §5。

---

## 3. 可追溯性

### 3.1 已经成立的链

- `AGENTS.md` → `docs/index.md` → 目录 `index.md` → 文档：结构存在。
- `docs/adr/index.md`：18 条 ADR 全部有编号、决策、状态列。
- `docs/specs/index.md`：22 条 spec 全部有 ticket / ADR / 状态列。
- `docs/research/index.md`：31 条研究 + “Superseded / removed”映射。
- `docs/legacy/mindtrace/index.md`：22 个内容文件 + 删除映射。
- `link-check`：4 个根、全部相对链接 0 broken。
- `naming-lint`：0 violation。

### 3.2 审计前缺的链

| 缺口 | 证据 | 处理 |
|---|---|---|
| 链接图不可达 | 从 `docs/index.md` 做 BFS，只能到 1 篇（索引列表是纯文本，不是链接） | 把目录索引改成真实 Markdown 链接（如 `docs/adr/index.md` 指向 `../adr/index.md`）；现在 `doc-trace` 报告 189 篇全部可达 |
| 状态覆盖率低 | 186 篇中仅 37 篇有显式 Status；`Owner` 为 0 | 新增 `docs/agents/document-control.md`：8 个状态词、控制块、追溯链、检查单 |
| 状态漂移 | spec 021 / 003 / 017 三处头与索引不一致 | 已修；`doc-trace` 先守结构，状态一致性仍需人工/agent 对读 |
| 文档 → 代码无约定 | 只有零散反引号路径，没有“实现锚点”字段 | 控制块新增 `Code` / `Verified by`；新文档和被改文档必须填 |
| 历史文档污染现行结论 | legacy 里仍有旧架构描述 | 已在 `document-control.md` 规定 `frozen` / `superseded` 不得作为当前指引 |

### 3.3 自动守门

新增 `scripts/doc-trace/`：

```bash
node scripts/doc-trace/index.mjs
# OK: doc-trace passed (189 files reachable, indexes complete, numbers unique)
```

检查三件事：

1. `docs/**/*.md` 是否都能从 `docs/index.md` 沿相对链接到达（目录链接解析到 `index.md`）。
2. 每个目录 `index.md` 是否列出同级全部非 index 文件。
3. `docs/specs/NNN-*` 与 `docs/adr/NNNN-*` 编号是否唯一。

已接入 `.github/workflows/document-links.yml`（单测 + 检查各一步），6 个单测全绿。

---

## 4. ArkTS / ArkUI 规范对 AI coding 的可用性

### 4.1 已有资产

| 资产 | 现状 | 对 agent 的价值 |
|---|---|---|
| `docs/style/arkts-1.1.md` | 502 行；40+ 官方规则（含 error code）、ArkUI-1/2/3 项目硬约束、API 版本矩阵、grep 验证命令、多 module 工程规则 | 规则来源完整，agent 可直接引用 rule ID |
| `scripts/arkts-lint/` | 34 条 AST 规则；CI 接入；`--check-rules` 可校验规则定义 | 机器可执行，能给出文件/行号 |
| `docs/agents/file-header-template.md` | 文件头模板 + 编码陷阱 | 降低“新建文件乱写头/带 BOM”的返工 |
| `AGENTS.md` | 有“改 .ets 合规 → arkts-1.1”指针 | 发现入口存在 |

### 4.2 审计前的问题

1. **入口太长**: 502 行 / 21KB，agent 在赶任务时容易只读前 80 行，漏掉 ArkUI-1/2/3 和项目规则。
2. **指标矛盾**: 见 §2 #5；agent 无法判断“跑哪个测试、什么是基线”。
3. **规则与命令脱节**: `arkts-1.1.md` §验证命令仍是 grep 起点（并自承误报多），而真正的 lint 在 `scripts/arkts-lint/`；agent 可能去跑 grep。
4. **没有 DoD**: 没有一页告诉 agent“写完 .ets 要满足哪 8 条才算完成”。

### 4.3 本轮补的入口

新增 [`docs/style/arkts-ai-coding.md`](../style/arkts-ai-coding.md)：

- 20 条最高频编译阻断（rule ID + ❌/✅ 示例）
- ArkUI 硬约束：struct 禁普通方法 / 禁 get / 字段名避让 / 装饰器选择 / `build()` 不做重活 / 长列表 `LazyForEach`
- 工程结构：5 module、完整 import、HSP `main` 字段、BOM、文件头、废弃目录
- 验证命令与判读口径（329 curated vs 707 全量 / 15 既有失败）
- DoD 8 条
- 规则 → `arkts-1.1.md` 小节索引

`AGENTS.md` 的“第一次接项目”和“改 .ets”两行已改为先读该清单，再读全文。

---

## 5. 仍未闭合 / 需要裁决

| 项 | 证据 | 状态 |
|---|---|---|
| spec 027 无 `Status` | `docs/specs/027-*.md` 头部只有日期 | ✅ 已补：`spec merged` + 实现锚点 + 未记录验收 |
| spec 026 状态是“implemented on feature branch” | `026-knowledge-graph-rdb.md` | ✅ 已改：`merged to develop`（分支已是 develop 祖先） |
| `docs/architecture/agent-tools-inventory-2026-09-06.md` 仍写 89 单测、skill TODO | 该文是 2026-09-06 快照 | ✅ 已加 `Status: frozen snapshot (2026-09-06)` |
| ADR-0017 标题 “device measurement” | 正文承认模拟器证据、设备目标 NOT_MET | ⏳ 未改：接受记录的标题不宜单方面改写，需 owner 裁决“改标题”或“加 caveat” |
| 150+ 篇 research / architecture 无 Status | 扫描结果 37/186 | ⏳ 不脚本回填；新文档/被改文档按 `document-control` 补，老文档按 owner 制度逐步补 |
| 无 Owner 制度 | 0 篇有 Owner | ⏳ 需团队决定是否引入；不建议脚本写空字段 |

---

## 6. 复现

```bash
# 文档结构与追溯
node scripts/doc-trace/index.mjs
node scripts/link-check/index.mjs
node scripts/naming-lint/index.mjs

# ArkTS 规则与测试
node --test scripts/doc-trace/tests/*.test.mjs
npm --prefix scripts/arkts-lint test
node --test scripts/arkts-lint/tests/*.test.mjs
```

实测（2026-10-18）：`doc-trace` 189 篇可达 / 索引完整 / 编号唯一；`link-check` 0 broken；`naming-lint` 0 violation；`doc-trace` 6 tests 全绿；`arkts-lint` curated 329/329；全量 707 / 692 pass / 15 fail（既有基线）。
