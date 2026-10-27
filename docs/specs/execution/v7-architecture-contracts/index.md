# v7 契约层与 NoteAgent 迁移 · 执行包

**Status:** `ready-to-execute`（2026-10-27，尚未开始写代码）
**对应票：** [#237](https://github.com/YunC-GCT/MindTrace/issues/237) · [#238](https://github.com/YunC-GCT/MindTrace/issues/238) · [#239](https://github.com/YunC-GCT/MindTrace/issues/239) · [#240](https://github.com/YunC-GCT/MindTrace/issues/240) · [#241](https://github.com/YunC-GCT/MindTrace/issues/241) · [#242](https://github.com/YunC-GCT/MindTrace/issues/242)
**设计来源：** [`docs/system-architecture-layered.md`](../../../system-architecture-layered.md) §17（v7 目标态，含 §17.5 契约与 §17.6 迁移顺序）；外评审 [`review-v7-2026-10-27.md`](../../../architecture/review-v7-2026-10-27.md)。

| 文件 | 内容 |
|---|---|
| [`plan.md`](./plan.md) | **交接文档**：给接手会话的读法、已完成项、票单与顺序、硬约束、环境命令、已知坑、阻塞项 |
| [`tasks.md`](./tasks.md) | 逐票勾选清单与证据要求 |
| [`raw/index.md`](./raw/index.md) | #239 golden 快照对照表：文件 / 命令 / 终态 / ADR-0019 条款 / 证明的行为 |
| `raw/` | #239 的 golden 快照（已生成；测试直接读，移动目录必须同 commit 改引用） |

**#239 行为基线：** ✅ 已落地。15 条 golden 快照落在 [`raw/`](./raw/index.md)，测试为
[`v7-golden-dispatch.test.mjs`](../../../../scripts/arkts-lint/tests/v7-golden-dispatch.test.mjs)；
默认模式读快照比对，`V7_GOLDEN=record` 重录。快照如实保留 capture 取消抛错、hash 不匹配无
`errorCode` 等现状，作为 #241 迁移的等价判据。

设计变更写回 §17 或 `docs/adr/`，不在本 bundle 里改设计（见 `docs/style/naming-conventions.md` §3.9）。
