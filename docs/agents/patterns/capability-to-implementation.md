# Pattern: Agent capability idea → implementation (skill chain)

> **When to use:** 推进一项 **agent 能力级**工作——工具层、调用协议、god-class 拆分、Kit 接线、意图接入。判别特征:改的是"agent 能什么",不是"某段代码长什么样"。

## Chain(6 步,每步一个落盘产物)

| 步 | Skill | 产物 | 说明 |
|---|---|---|---|
| 1 | `/research` | `docs/research/{slug}-{date}.md` | 供给面/现实核查,一手信源。已有相关调研则跳过,不重复 |
| 2 | `/grill-with-docs` 或用户裁决 | 裁决记录 | 澄清语义/范围/排期;goal 模式下可用 AskUserQuestion 代替多轮拷问 |
| 3 | `/domain-modeling` | ADR(新立/修订/supersede)+ CONTEXT.md 词条 | 三条件(难逆/后来者会问/真实取舍)满足才立 |
| 4 | `/codebase-design` | 接缝形状决定 | 谁持 seam、契约放哪个模块(参照 ADR-0009 契约注入哲学) |
| 5 | `/to-spec` | `docs/specs/NNN-{slug}.md` | 冲刺期可为 **spec-only**(零实现,如 spec 014);过时 spec 用新号 supersede(如 015→003) |
| 6 | `/to-tickets` + `/implement` | 曳光弹 ticket / 实现分支 | `/implement` 内部驱动 `/tdd`,收口跑 `/code-review` 双轴 |

## This-repo specifics

- **只读体检先行**:大动作前跑全仓清点落 `docs/architecture/{slug}-{date}.md`(先例:agent-tools-inventory-2026-09-06),发现项带 F 编号供 ADR 引用
- **日历分层**:复赛窗口只收 spec / 只做零回归风险段;动已工作代码的实施排赛后(inventory §6.1 模式)
- **写入纪律**:AGENTS.md 7 红线;spec/ADR 状态列跟着实现 PR 走(团队手册 PR 检查单有此条)
- **产物命名**:ADR `NNNN-slug` / spec `NNN-slug` / research `slug-date` / architecture `slug-date`;提交前 naming-lint + link-check

## When NOT to use

- 单点 bug → `/diagnosing-bugs`
- 纯行为不变的小重构 → 本目录 [`refactor-x.md`](./refactor-x.md)(本链是其上位流程)
- 改动小到一轮对话能定 → 直接 `/implement`,不要仪式化

## Anti-patterns

- **跳过 1–3 直接写代码**。教训:ADR-0005 在没核实命名意图的情况下定案,后被 ADR-0010 supersede(PR #28 改名再回滚)
- **调研与拷问合并成一轮**——研究喂拷问,不是替代拷问
- **冲刺期在 spec 里塞实现**——spec 014 的 spec-only 模式就是为零回归风险设计的
- **重复已有调研**——开工前先查 `docs/research/` 索引

## Related

- [`refactor-x.md`](./refactor-x.md) — 行为不变的机械重构(本链第 6 步的执行模式)
- [`investigate.md`](./investigate.md) — 单问题多解的调查
- [`add-new-adr.md`](./add-new-adr.md) — 第 3 步的 ADR 细则

## Last updated

2026-09-06(从 KnowledgeModel 拆分 goal 的实际执行路径中提炼)
