# D3 — 前端仿 React 组件化与组件接缝

> **Status**: in progress (shared 组件三层已拆; overlay/service 迁移待做; 进度以 [`index.md`](./index.md) 为准)
> **Date**: 2026-09-05
> **Source decision**: GitHub issue #10
> **Scope**: 仅架构规范化，不引入新组件库与状态管理依赖。

## Why this ticket

MindTrace 前端目前 5 个 Tab 页面 + 多个 Overlay 和 shared components，结构无统一 seam：

- `entry/src/main/ets/pages/{Home,Notes,AI,Review,Profile,MainTabs,AiSettings}/`
- `entry/src/main/ets/overlays/*/components/`
- `entry/src/main/ets/shared/components/`

- 页面直接调 service、UI 状态与业务逻辑混在一起
- 跨页面复用没有一致接缝：有的拆 `components/`，有的全写在 Page 文件
- `@State` / `@Prop` / `@Link` 边界含糊

- 改造落地前需要先规范接缝、文件命名和职责划分，否则团队协作会出现反复重构。

## Goals

1. 把 5 Tab + Overlay 整理成 Page / Template / Organism / Molecule / Atom 五层目录与文件名 PascalCase 化
2. 明确页面与 service / viewmodel 的依赖方向，禁止 Page 直接 import 数据库和业务服务实现
3. 给出 viewmodel ↔ service ↔ dao 的接缝模板代码，供新页面复用
4. 不引入新依赖（不使用 React/Vue/Tailwind 等）
5. 不增加新功能

## Non-goals

- 不引入新组件库或状态管理框架
- 不修改 .ets 业务逻辑实现
- 不改造 Profile / Home 等已有页面的样式与交互

## Layering rules

| Layer | 目录 | 文件名 | 依赖方向 |
|---|---|---|---|
| **Atom** | `entry/src/main/ets/shared/atoms/` | `PascalCase.ets` | 0 依赖内部模块 |
| **Molecule** | `entry/src/main/ets/shared/molecules/` | `PascalCase.ets` | Atom |
| **Organism** | `entry/src/main/ets/shared/organisms/` 或 `< `page>/components/` | `PascalCase.ets` | Atom + Molecule + Service 接口 |
| **Template** | `< `page>/templates/` 或页面根 | `PascalCase.ets` | Organism + Atom + Molecule |
| **Page** | `< `page>/` | `PascalCase.ets` | Template + ViewModel |

依赖方向只能自上而下：Page → Template → Organism → Molecule → Atom。

页面禁止直接 `import` 任何 dao、数据库、HTTP、KnowledgeModel 之类业务实现。

## Naming rules

- 目录与文件名 PascalCase：`SearchField.ets`、`NoteCard.ets`、`HomePage.ets`
- 文件头注释含：组件名 / 所属层 / 依赖列表 / 状态字段
- 不在文件名加类型前缀：`noteService.ts` → `NoteService.ets`

## Migration plan

按风险递增排序，每个 PR 仅做一件事：

1. **PR1**：`entry/src/main/ets/shared/components/` 拆分 `atoms/` 与 `molecules/`
2. **PR2**：5 Tab 页面统一文件头注释与依赖方向声明
3. **PR3**：viewmodel 接缝模板 + smoke test 模板

每 PR 由 lint 与 Node 测试守门。

## Acceptance criteria

- [ ] `scripts/naming-lint` 通过
- [ ] 5 Tab 页面符合依赖方向约束
- [ ] 至少 3 个示例组件从 Page 拆为 Organism/Molecule/Atom 三层
- [ ] Page 文件头注释统一
- [ ] 不执行 build / push / 未授权 commit

## Out of scope

- 状态管理方案（继续用 `@State` + `@Observed`）
- 主题、暗色模式、可访问性增强
- 性能优化（`List` + `LazyForEach`）