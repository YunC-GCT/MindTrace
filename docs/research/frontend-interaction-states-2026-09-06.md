# 前端交互五态完整性摸底 — 2026-09-06

> **Date:** 2026-09-06 晚
> **Scope:** MindTrace entry 全 UI 组件的 5 个交互态 (enabled/disabled/loading/empty/error) 覆盖率
> **方法**: grep `@State.*busy/loading/disabled/pending/empty/error/status` + try/catch 模式 + 空态分支, 全机提取
> **配套**: [`frontend-ui-design-inventory-2026-09-06.md`](./frontend-ui-design-inventory-2026-09-06.md) 静态清点 · [`frontend-flow-walkthrough-2026-09-06.md`](./frontend-flow-walkthrough-2026-09-06.md) 路径走查

---

**TL;DR:** 5 态实现严重失衡 — **loading 态只在 2 个文件** (CameraOverlay / AgentFloatWindow), 其他 7+ 个可能 loading 的位置 (save note / save settings / delete / refresh) **全靠 Toast 反馈 + 按钮变灰**, 用户无进度感; **disabled 态几乎不存在** (无 @State disabled), 全部走"按钮变灰"惯例; **error 态 165 处 try/catch 包裹但无结构化错误状态**, 全是 promptAction.showToast 即丢即忘; **empty 态有专门的 *EmptyState 类组件 (4 件)** 是规范亮点; **enabled 是默认, 无显式状态**。

---

## 1. Loading 态 — 全前端只有 2 处真实现

`@State busy` / `@State loading` 全文 grep:

| 文件 | 字段 | 用途 |
|---|---|---|
| `overlays/CameraOverlay/CameraOverlay.ets:23` | `@State busy: boolean` | 拍照中禁用其他按钮 |
| `overlays/AgentFloatWindow/AgentFloatWindow.ets:44` | `@State busy: boolean` + `:45 statusMeta: ChatStatusMeta \| null` | LLM 调用中, 13 步状态文案 (`statusFromStep`) |

**应 loading 却无 loading 态的位置 (高风险):**

| 位置 | 当前行为 | 问题 |
|---|---|---|
| AiSettings save (5 个 picker) | save → `promptAction.showToast` | 用户点完无反馈, 不知道是否在保存 |
| NoteEditForm save | 待核实 (save 路径未 grep) | 同上 |
| NoteDelete | `promptAction.showToast({ message: 'Note deleted', duration: 1200 })` | 删完才提示, 删除中无反馈 |
| HomePage `loadRecentNotes` | `.finally((): void => { ... })` | loading 收口位置, 但 UI 不显示 |
| Profile login (mock) | 立即回调 | mock 不真, 但若改真实现需补 loading |
| HexLogo | animateTo DUR_SLOWEST 1200ms ×3 | 用户点完 1.2 秒内无反馈 |

**判据缺失**: 任何 >200ms 的用户操作都应有 loading 态。`loading-mvp` 风格 = spinner + 禁用交互。

---

## 2. Disabled 态 — 几乎不存在 (全靠"按钮变灰"惯例)

全文 grep `@State.*disabled` **零命中**。

`disabled` 是 ArkUI 组件的内置属性, 但需要有人维护。证据:
- CameraOverlay 唯一可能的地方: `:23 busy` 期间禁用其他按钮 — 需核实是否 `.enabled(!this.busy)`
- AgentFloatWindow:44 busy 期间禁用 send — 需核实

**判据缺失**: 状态变化时 (busy=true) 必须显式 `.enabled(!busy)`, 否则用户可连点造成重入。

---

## 3. Empty 态 — 4 个专门组件, 是规范亮点

| 组件 | 位置 |
|---|---|
| `NotesEmptyState` | `pages/Notes/NotesEmptyState.ets` |
| `SubjectTypeEmpty` | `pages/Notes/SubjectTypeEmpty.ets` |
| `EmptyStateHint` | `overlays/AgentFloatWindow/chat/EmptyStateHint.ets` |
| `SubjectHeader` 内含空态分支 | `pages/Notes/SubjectHeader.ets` |

**亮点**: 这 4 件结构化了"无数据"提示, 没混在 List 组件里。**值得提升为 shared/atoms/EmptyStateHint**, 因为 AgentFloatWindow 内的同名件重复了一份。

**待补空态的位置 (按业务必有):**
- AgentFloatWindow 多会话切到空会话时 — 当前 EmptyStateHint 只在消息列表空, 多会话切换的"选个会话"空态缺失
- ReviewGraphView 知识星系在零笔记时 — 当前 `KnowledgeGalaxyViewModel` 应有 0/0/0 fallback, 待核实
- 相机相册 (album) 无照片时

---

## 4. Error 态 — 165 处 try/catch 但全 Toast 即丢

```
grep -rn '} catch' entry/src/main/ets --include="*.ets" | wc -l
  → 165
```

**主流模式**:
```typescript
try {
  await this.service.x()
  promptAction.showToast({ message: 'OK', duration: 1200 })
} catch (_e) {
  promptAction.showToast({ message: 'Failed', duration: 1500 })  // ← 吞掉 _e
}
```

**问题清单**:
1. **`_e` 被吞** — 没有日志、没有上报、没有结构化错误对象, 出问题后排障无门
2. **无 retry** — 失败后用户只能刷新整个页面或重做操作
3. **无错误状态** — UI 上看不出"上次操作失败", 没有红色横幅或"操作失败 重试"按钮
4. **错误分类缺失** — 网络错 (no network) / LLM 错 (rate limit / context too long) / OCR 错 (image not recognized) / IO 错 (file not found) 应区别处理, 当前全部 1 个 toast

**判据缺失**: 任何失败应有 (错误分类, 用户可读消息, 建议下一步) 三件套, 而不是一行 toast。

---

## 5. Enabled 态 — 默认, 无显式状态

ArkUI 组件默认 enabled, 业务代码不显式维护。**配合 disabled 缺失**, 整个"状态可变性"靠 .enabled 静态属性 + busy @State, 没有体系。

---

## 6. 评级

| 态 | 覆盖 | 评 | 风险 |
|---|---|---|---|
| enabled | 100% (默认) | ✓ | — |
| disabled | ≈10% (仅 2 浮层可能维护) | ✗ | 中 (重入 bug) |
| loading | ≈15% (2 文件真实现) | ✗ | 高 (评委走查会撞上) |
| empty | 60% (4 组件 + 列表 fallback) | △ | 中 (AgentFloatWindow 多会话切空态缺失) |
| error | ≈5% (有 toast, 无结构化) | ✗ | 高 (排障无门, 用户体验差) |

**最该修的 3 项 (不动, 只列)**:
1. **loading 态体系**: 加 @State loading 工具类 + 业务约定 (>200ms 操作必有 loading)
2. **error 态结构化**: ErrorBus module (AppStorage 或 Context) + UI ErrorBanner 组件 + 错误分类 (network / llm / ocr / io / unknown)
3. **disabled 态守门**: 静态检查工具扫描 `.enabled(` 调用面

---

## 7. 待补充资料

§5 第 6 项 (路径级核实) 不变, 新增:
7. **`@State busy` 是否配合 `.enabled(!this.busy)` 的实查**: 在 CameraOverlay / AgentFloatWindow 6 处可能的禁用点上核实; 若缺失, 列入 `frontend-healthcheck-plan-2026-09-06.md` 候选列表
8. **错误分类需求**: 真机演示中会出现的错误类型清单 (评审 demo 5 分钟内可能触发的失败), 用于 error 态体系设计

---

## Last updated

2026-09-06 晚
