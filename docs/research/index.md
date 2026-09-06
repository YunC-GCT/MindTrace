# Research index

> **Scope**: 调研产物索引(一手底料 + 项目定位 + 架构体检)。
> **Convention**: `<topic-slug>-YYYY-MM-DD.md` (kebab-case),HTML 镜像同 slug。
> **Source-of-truth**: 本目录文件均为 research 一次性产物,落定后不再修改;新版本开新文件并把旧的挪 `docs/legacy/`。

## Active

| File | Date | Topic | Status |
|---|---|---|---|
| [`agent-framework-comparison-2026-09-02.md`](./agent-framework-comparison-2026-09-02.md) (.html) | 2026-09-02 | MindTrace 是否使用 LangGraph 等价框架?结论:不用,自建 Dispatcher + sub-agent 同步链 | **decided** (2026-09-05: 采纳 LangGraph 设计模型,ArkTS 自建 CaptureGraph 承载,见 [ADR-0008](../adr/0008-capturegraph-self-built-runtime.md) / spec 011) |
| [`langgraph-migration-2026-09-02.md`](./langgraph-migration-2026-09-02.md) (.html) | 2026-09-02 | MindTrace → LangGraph 迁移可行性调研 | **decided** (2026-09-05: 不引入 LangGraph 运行时依赖;采纳其设计模型,ArkTS 自建 CaptureGraph) |
| [`project-positioning-2026-09-04.md`](./project-positioning-2026-09-04.md) | 2026-09-04 | 项目定位(摘要 + 详细双节),团队对齐与评委 pitch 用 | active |
| [`harmonyos-kits-survey-2026-09-05.md`](./harmonyos-kits-survey-2026-09-05.md) | 2026-09-05 | 12 个官方 kit 家族能力 + MindTrace 适配点 + 成本档位;P0 = FormKit/Reminder/BackgroundTasks,P1 = AIEngine/NLP | active (D4 依据) |

临时原料 [`_positioning-facts-2026-09-04.md`](./_positioning-facts-2026-09-04.md)(下划线前缀)按约定不入正式索引。

## Cross-reference

- 关联审计: [`../legacy/mindtrace/architecture/audit-full-2026-09-01.md`](../legacy/mindtrace/architecture/audit-full-2026-09-01.md)
- ADR / Spec: [`../adr/`](../adr/) / [`../specs/`](../specs/)

## Naming convention

| 类别 | 规则 |
|---|---|
| 调研文档 | `<topic-slug>-YYYY-MM-DD.md` |
| 临时原料 | `_<topic-slug>-YYYY-MM-DD.md`(下划线前缀,不入正式索引) |
| HTML 镜像 | 同 slug `.html`,与 md 并列 |
| 归档 | 移入 `docs/legacy/research/` 后保留日期与 slug |

## Maintenance

- 新增调研:复制 `docs/template/research-*.md` 模板,文件名按 `<topic-slug>-YYYY-MM-DD.md` 命名
- 索引追加:在本表 Active 段加一行,标注日期 / 主题 / 状态
- 归档:旧调研从 Active 移到 Legacy 段,文件本身保留

## Last updated

2026-09-06 (修正命名约定自反 + langgraph 两篇标记 decided)
