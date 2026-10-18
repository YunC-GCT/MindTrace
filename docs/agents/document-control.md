# 文档控制与追溯 (Document Control)

> **用途**: 规定 `docs/` 里每篇文档的**状态、关联和可追溯链**，让人类和 AI agent 都能回答三个问题：
> 1. 这篇文档现在还算数吗？
> 2. 它对应哪个决策 / 哪份 spec / 哪段代码？
> 3. 改了代码或决策后，应该同步改哪些文档？
>
> **适用**: `docs/` 下的现行文档（`adr/` / `specs/` / `research/` / `architecture/` / `agents/` / `style/`）。`docs/legacy/` 是冻结历史，只遵守“可追溯”，不要求更新状态。

---

## 1. 状态词汇（只许用这 8 个）

| Status | 含义 | 典型位置 |
|---|---|---|
| `draft` | 还在写，不能作为实现依据 | spec / research |
| `proposed` | 方案已成型，等评审 / 裁决 | ADR / spec |
| `accepted` | 决策已采纳，代码可以跟 | ADR |
| `implemented` | 已落地到 `develop`；可注明 device acceptance pending | spec / execution |
| `in progress` | 部分落地，剩余工作有明确 ticket | spec / architecture |
| `superseded` | 被新文档 / ADR 取代；必须写 `by <link>` | ADR / spec |
| `frozen` | 历史快照，不再更新；只作证据 | legacy / audit |
| `reference` | 术语、清单、索引类，不承载决策 | CONTEXT / index / glossary |

> 不要用 `done` / `WIP` / `active` / `deprecated` 等自造词。状态必须能和 [`docs/specs/index.md`](../specs/index.md)、[`docs/adr/index.md`](../adr/index.md) 对上。

---

## 2. 现行文档的控制块

新文档、或被实质修改的文档，在 H1 之后加：

```markdown
> **Status**: implemented (2026-10-18)
> **Related**: [ADR-0008](../adr/0008-capturegraph-self-built-runtime.md) · [spec 018](../specs/018-agent-workflow-architecture.md)
> **Code**: `common/src/main/ets/workflow/StateGraph.ets` · `agents/src/main/ets/graph/CaptureGraph.ets`
> **Verified by**: `npm --prefix scripts/arkts-lint test` · issue #N / PR #N
```

字段规则：

| 字段 | 必填 | 说明 |
|---|---|---|
| `Status` | 是 | 只能用 §1 的词；带日期 |
| `Related` | 设计/实现类必填 | 上游 ADR / spec；没有就写 `(implicit)` 并说明原因 |
| `Code` | 实现类必填 | 至少一个真实存在的仓库相对路径；不要写行号区间（会漂移） |
| `Verified by` | 实现/验收类必填 | 可复现命令、issue、PR 或 execution bundle |
| `Owner` | 否 | 只有明确负责人时写；不要编造 |

> 历史文档不强制补控制块；被重新引用或修改时再补。`docs/legacy/` 统一视为 `frozen`。

---

## 3. 追溯链（必须闭合）

```
AGENTS.md
  → docs/index.md
    → <directory>/index.md
      → 文档
        → ADR（why）
        → spec（what / how）
        → code path（实现）
        → test / command（证据）
```

规则：

1. **可达**: 每篇 `docs/**/*.md` 必须能从 `docs/index.md` 沿相对链接走到（目录索引也算一跳）。
2. **索引完整**: 每个目录的 `index.md` 必须列出该目录下所有非 `index.md` 文件；bundle 目录也一样。
3. **状态一致**: spec / ADR 的头部 `Status` 必须与对应 `index.md` 表格一致；改一处必须改另一处。
4. **决策可回指**: 设计/实现文档必须能指回至少一个 ADR 或 spec；没有上游决策时写 `(implicit)` 并说明理由。
5. **代码可落地**: `Code` 里的路径必须存在；移动文件时同 commit 改文档。
6. **证据可复现**: `Verified by` 不能只写“已测试”，要写命令 / issue / PR / bundle。
7. **历史不污染现行**: `legacy/`、`frozen`、`superseded` 文档里的结论不得被当作当前指引；现行文档引用它们时必须标注“历史证据”。

---

## 4. 自动检查

```bash
# 一条命令：文档 + 代码边界 + lint（agent 交付前必跑）
node scripts/agent-gate/index.mjs          # 当前改动集
node scripts/agent-gate/index.mjs --all    # 全仓

# 文档结构单项
node scripts/doc-trace/index.mjs

# 链接 + 命名
node scripts/link-check/index.mjs
node scripts/naming-lint/index.mjs
```

`agent-gate` 会跑 `.ets` 卫生（BOM / 文件头 / 模块边界）、`arkts-lint`、`naming-lint`、`link-check` 与 `doc-trace`。`doc-trace` 检查的是**结构**，不判断技术结论；技术冲突仍需人 / agent 读 ADR 与 spec。

---

## 5. 新增 / 修改文档的检查单

- [ ] 文件名符合 [`naming-conventions.md`](../style/naming-conventions.md)（kebab-case、日期后缀）
- [ ] 放在正确的目录：决策 → `adr/`；设计 → `specs/`；执行证据 → `specs/execution/<bundle>/`；调研 → `research/`；稳定架构描述 → `architecture/`；流程 → `agents/`
- [ ] H1 下有 `Status`；设计/实现类有 `Related` / `Code` / `Verified by`
- [ ] 从所在目录的 `index.md` 可达
- [ ] 引用其他文档用相对链接；引用代码用仓库相对路径
- [ ] 改状态时同步改 `index.md`
- [ ] 跑 `doc-trace` / `link-check` / `naming-lint`

---

## 6. 当前基线（2026-10-18）

| 指标 | 值 |
|---|---|
| `docs/` Markdown | 186 |
| orphan（无入链） | 0 |
| 缺 `index.md` 的目录 | 0 |
| 带显式 Status 的文档 | 37（多数为 ADR / spec；research / architecture 多数未标） |
| Owner 字段 | 0（尚无负责人制度） |

结论：**链接与索引层已经闭合；“状态 / 负责人”层还没闭合**。因此本文件只强制新文档和被修改文档补控制块，不对 150+ 篇历史文档做一次性回填——回填应由 owner 制度配合，而不是脚本猜。
