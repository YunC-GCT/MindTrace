# 031 — 小艺唤起批量整理 (P1–P3)

> 状态: 进行中 · 起点: 2026-10-23 · 主线: v1 端A2A
> 上游: [`phase-tracker.md`](../agents/phase-tracker.md) P1/P2/P3

## 1. 背景

P0 已打通「小艺 → `AgentExtensionAbility` → 回复」。现在用户在小艺里说「把相册里的数学题整理成笔记」，只能拿到一段静态计划，应用不会出现。

本 spec 把这条路接到真实能力：**小艺 → 拉起应用半屏浮窗 → 用户选图 → OCR → 落库 → 回执**。

## 2. 已定决策

| 决策 | 选择 | 理由 |
|---|---|---|
| 应用被拉起后的形态 | **半屏浮窗**，用户再点选图 | 不打断当前界面；复用现有 `AgentFloatWindow` |
| 取消选图 | 回「已取消，需要时再叫我」 | 需异步通道，见 §6 风险 |
| 范围 | P1+P2+P3 合并推进 | 只拿到 URI 不算可用 |

## 3. 数据流

```
小艺 SendStreamingMessage
   → AgentExtAbility.handleTask(query)
      → 命中意图(batch_capture)
      → startAbility(EntryAbility, parameters{ mtAction, mtQuery })
      → 立即回 task 快照「已打开应用，请在浮窗里选图」
   → EntryAbility.onCreate / onNewWant 读 parameters
      → AppStorage.setOrCreate('mtPendingAction', {...})
   → Index.ets 监听 → activeOverlay = 'float' + batchMode = true
   → AgentFloatWindow 显示「选图整理」入口
      → AlbumPickerLauncher.pick(ctx, 20)   ← P2 改多选
      → uris[]
      → Dispatcher.dispatch(...)            ← P3 接现有编排
      → 落库 + 卡片/列表刷新
```

### 3.1 已否决：`AgentExtensionAbility` 直接拉起应用

2026-10-23 实测编译失败（`Property 'startAbility' does not exist on type 'AgentExtensionContext'`）。

**原因（SDK 证据）**：`AgentExtensionContext extends ExtensionContext extends Context`，整条链上没有 `startAbility`；扩展进程不能启动 UIAbility。

**正确路径**：用 `AgentUIExtensionAbility`（`UIExtensionAbility` 子类，SDK `@ohos.app.agent.AgentUIExtensionAbility.d.ts`，API 24），它的 `UIExtensionContext` 提供 `startAbility`，且必须与 `AgentExtensionAbility` **同进程**运行。

因此 P1 拆成两步：

| 票 | 内容 |
|---|---|
| T1a | 新增 `AgentUIExtensionAbility` + 卡片页（半屏内容：「选图整理」按钮） |
| T1b | 卡片按钮 `context.startAbility(EntryAbility)` → 应用打开并弹 Picker |

## 4. 接口契约

### 4.1 Want parameters（A2A → 应用）

| key | 类型 | 说明 |
|---|---|---|
| `mtAction` | string | 固定 `batch_capture` |
| `mtQuery` | string | 用户原话，用于浮窗展示 |

### 4.2 AppStorage key

| key | 类型 | 说明 |
|---|---|---|
| `mtPendingAction` | `{ action: string; query: string; at: number }` | 页面消费后置空 |

### 4.3 选图接口

```ts
// 现状: maxSelectNumber = 1
// 目标: 显式传入上限，默认 1，批量路径传 20
static async pick(context: common.UIAbilityContext, maxCount: number = 1): Promise<string[]>
```

### 4.4 意图识别（v1 用关键词，不接模型）

命中集合：`整理` / `笔记` / `数学题` / `相册` 任意两个词，或整句包含「整理…笔记」。

未命中 → 保持现有静态计划回复（不改变 P0 行为）。

## 5. 分票

| # | 票 | 验收 |
|---|---|---|
| T1 | 意图识别 + `startAbility` + AppStorage 传递 | 小艺说话后应用到前台并进浮窗；日志可见 `mtAction=batch_capture` |
| T2 | `AlbumPickerLauncher.pick(ctx, maxCount)` 多选 20 | 选 20 张不崩，URI 全可读 |
| T3 | 选图 → `Dispatcher.dispatch` → 落库 | 杀掉应用重启，笔记仍在 |
| T4 | 回执：浮窗显示「已整理 N 条」；小艺侧下一轮可查询 | 数字与库内一致 |
| T5 (spike) | 异步回「已取消」：保持 A2A 流不结束 | 能验证就做，不能就把取消写进应用内记录 |

## 6. 风险

| 风险 | 影响 | 处理 |
|---|---|---|
| **A2A 单向**：回完 task 即结束，应用侧事件推不回小艺 | T5 取消回话做不到 | 先做 T1–T4；T5 单独 spike，失败则降级为「应用内提示」 |
| 半屏浮窗需要前台 UI 上下文 | A2A 里不能直接弹 Picker | 必须走 `startAbility`，由页面拉起 |
| `Dispatcher.dispatch` 依赖网络/模型 | 无网时落库失败 | 失败要显式报错，不静默 |
| 多选 20 张内存 | 低端机可能 OOM | 先按 10 张验收，再放开 20 |

## 7. 验收（对应 phase-tracker）

- P1：真机小艺说「整理相册里的数学题」→ 应用进前台浮窗
- P2：选 10 张成功返回 URI
- P3：笔记落库，重启仍在
- 全程 `node scripts/agent-gate/index.mjs` 为 PASS
