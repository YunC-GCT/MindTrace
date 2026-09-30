# 文档链接审计与修复报告 — 2026-09-30

> **基线**: `d3e965b` (Merge pull request #200)
> **工具**: `node scripts/link-check/index.mjs --json` (roots: `docs`, `CONTEXT.md`, `AGENTS.md`, `README.md`)
> **结果**: 修复前 `brokenCount = 272` → 修复后 `brokenCount = 0`, `passed = true`
> **范围**: 仅改动 `docs/**/*.md`(含子目录);未改 README / AGENTS / scripts / CI / 主计划

---

## 1. 分类计数

| 分类 | 数量 | 处置方式 |
|---|---|---|
| 归档文档坏链(`docs/legacy/mindtrace/research/*.md`) | 240 | 解除 Markdown 超链接(保留 label 文字)+ 顶部补「失效历史链接已移除，原引用可查Git历史」 |
| 活跃文档 — 相对路径错误(目标存在, 仅路径层级不对) | 20 | 修正为正确相对路径 |
| 活跃文档 — 目标已移至归档(有历史必要) | 4 | 修到真实归档路径 + 标注「历史参考」 |
| 活跃文档 — 来源全 Git 不存在 | 8 | 解除超链接 + 标注「原文未随仓库保留」 |
| **合计** | **272** | — |

活跃失效目标去重后共 **5 个**: 2 个「已移至归档」, 3 个「Git 从未存在」。

---

## 2. 活跃失效目标追踪(旧路径 → 新路径 / 历史 commit / 缺失证据)

### 2.1 已移至归档(修到真实归档路径, 标「历史参考」)

| 旧路径 | 新路径 | 证据 commit |
|---|---|---|
| `docs/research/agent-framework-comparison-2026-09-02.md` | `docs/legacy/mindtrace/research/agent-framework-comparison-2026-09-02.md` | `eb48a32` (R100 rename) |
| `docs/research/langgraph-migration-2026-09-02.md` | `docs/legacy/mindtrace/research/langgraph-migration-2026-09-02.md` | `eb48a32` (R100 rename) |

引用处(4 条, 均已修 + 「历史参考」):
- `docs/adr/0008-capturegraph-self-built-runtime.md:3` → `../legacy/mindtrace/research/agent-framework-comparison-2026-09-02.md`
- `docs/agents/handoff-langgraph-migration.md:24` → `../legacy/mindtrace/research/langgraph-migration-2026-09-02.md`
- `docs/research/agent-toolkit-and-skill-dispatch-2026-09-06.md:5`(2 条) → 上述两个归档路径

### 2.2 来源全 Git 不存在(解除超链接, 标「原文未随仓库保留」)

| 目标 | 引用数 | 缺失证据(全历史追溯结论) |
|---|---|---|
| `docs/research/llm-provider-patterns-2026-09-06.md` | 6 | `git log --all --name-only` 全历史仅命中 `docs/adr/0013-llm-provider-presets.md`(引用方), 从未作为文件提交; 该调研文档(493 行)自始未随仓库保留 |
| `docs/plans/knowledge-model-decomposition-plan.md` | 1 | `git log --all --name-only "*knowledge-model*"` 仅命中 `docs/adr/0006-knowledge-model-decomposition-plan.md` / `docs/specs/015-knowledge-model-decomposition-v2.md` / `docs/specs/003-knowledge-model-decomposition.md`; `docs/plans/` 下无此文件; 被引用的 §23.1-23.13(1733 行)补丁日志仅存在于引用方 `docs/agents/note-generation-fix-handoff-2026-09-20.md` 自身, 从未单独入库 |
| `docs/agents/handoffs/pr2-t2-vendorpicker-handoff-2026-09-08.md` | 1 | `git log --all --name-only` 全历史仅命中 `entry/src/main/ets/pages/AiSettings/VendorPicker.ets`(源码), 该 handoff 文档从未提交 |

引用处(8 条, 均已解除):
- `docs/adr/0013-llm-provider-presets.md:9`、`:56`
- `docs/adr/0014-asset-store-kit-migration.md:16`、`:68`
- `docs/agents/llm-settings-scope-2026-09-06.md:69`
- `docs/specs/016-llm-settings-redesign.md:5`
- `docs/agents/note-generation-fix-handoff-2026-09-20.md:7`
- `docs/specs/017-llm-settings-cleanup.md:7`

### 2.3 相对路径错误(目标存在, 仅层级不对, 已修正)

| 源文件 | 条数 | 修正方向 |
|---|---|---|
| `docs/agents/tickets/llm-settings/pr0-fix-pro-model.md` | 4 | `../specs|adr` → `../../../specs|adr`; scope → `../../llm-settings-scope-...` |
| `docs/agents/tickets/llm-settings/pr1-asset-store-kit-upgrade.md` | 3 | `../specs|adr` → `../../../specs|adr` |
| `docs/agents/tickets/llm-settings/pr2-t1-llm-config-data.md` | 3 | `../specs|adr` → `../../../specs|adr` |
| `docs/agents/tickets/llm-settings/pr2-t2-ui-redesign.md` | 2 | `../specs|adr` → `../../../specs|adr` |
| `docs/research/agent-float-window-component-research-2026-09-11.md` | 2 | `../../specs|adr` → `../specs|adr` |
| `docs/research/agent-reasoning-process-display-research-2026-09-11.md` | 5 | `../../specs|adr` → `../specs|adr`; `../chat-markdown` → `./chat-markdown` |
| `docs/research/frontend-healthcheck-plan-2026-09-06.md` | 1 | `../../agents` → `../agents` |

---

## 3. 归档文档解除链接清单(5 文件, 240 条)

> 统一处置: 解除 Markdown 超链接(保留 label 文字, 不删文字/历史事实), 顶部补一行 `> **失效历史链接已移除，原引用可查Git历史**`。有效链接一律未动。

| 文件 | 解除数 |
|---|---|
| `docs/legacy/mindtrace/research/capturegraph-processing-chain-2026-09-16.md` | 100 |
| `docs/legacy/mindtrace/research/tool-packaging-direct-kit-path-2026-09-16.md` | 68 |
| `docs/legacy/mindtrace/research/tool-packaging-mcp-path-2026-09-16.md` | 49 |
| `docs/legacy/mindtrace/research/capturegraph-tool-layer-and-patterns-2026-09-16.md` | 22 |
| `docs/legacy/mindtrace/research/langgraph-migration-2026-09-02.md` | 1 |

---

## 4. 验证

- `node scripts/link-check/index.mjs --json` → `passed: true, brokenCount: 0`
- `node scripts/naming-lint/index.mjs` → 见提交前运行输出(全绿)
- `git diff --check` → 无空白/冲突残留

初始报告保留为未跟踪临时文件 `.link-check-report.json` / `.link-check-report-after.json` / `.link-check-fix-archived.mjs`(未提交)。
