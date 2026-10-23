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

### 4.5 UI 扩展注册形态（SDK / 运行时源码确认）

- 类型值：`module.json5` → `extensionAbilities[].type = "agentUI"`（`toolchains/modulecheck/module.json` 枚举里存在）
- 类：`AgentUIExtensionAbility` 是 `UIExtensionAbility` 的空子类（`@ohos.app.agent.AgentUIExtensionAbility.d.ts`），生命周期全部来自父类
- 页面：`onSessionCreate(want, session)` → `session.loadContent('pages/<卡片页>')`
- 与 `AgentExtensionAbility` **同进程**运行（官方文档约束）
- `services/abilitymgr/resource/ams_extension_config.json` 里 `agentUI` 只登记了锁屏策略，没有额外 metadata 要求

### 4.6 实测：小艺不会自动拉起 `agentUI` 扩展（2026-10-23）

- 扩展已注册成功：`bm dump` 可见 `extensionTypeName: agentUI`、`name: AgentUIExtAbility`
- 构建、装机均通过
- 但真机发消息后：**小艺侧无任何 `agentUI` / `UIExtension` 日志，扩展进程未被启动**
- `AgentHostProxy` 只有 `sendData` / `authorize`，没有“请求显示 UI”的方法
- `AgentCard.d.ts` 里没有 UI 相关字段
- 结论：**触发条件在闭源的小艺客户端里**，公开 SDK 与文档都查不到

### 4.7 资料调研结果（2026-10-23）

| 来源 | 结论 |
|---|---|
| 官方 `openharmony/docs` | 只有 1 页 API 存根（1781 字节），没有触发方式 |
| `toolchains/modulecheck/module.json` | 确认 `type: "agentUI"` 合法 |
| `ams_extension_config.json` | 只登记锁屏策略，无 metadata 要求 |
| `AgentHostProxy.d.ts` | 只有 `sendData` / `authorize`，无显示 UI 的方法 |
| `AgentCard.d.ts` | 无任何 UI 字段 |
| 全网代码检索 `uiExtensionCard` / `ability.want.params.payload` | **只在 1 篇社区文章里出现**，官方仓库与其他实现零命中 |

**实测该社区方案**：在 task 的 `artifacts[].parts[]` 里追加 `{type:'uiExtensionCard', payload:{...}}` 后，
小艺**连文本气泡都不再渲染**（响应 600 字节被整条丢弃），扩展进程也没有被拉起 → 该格式不被当前客户端接受。

### 4.8 补查：触发方式找到了，但依赖 API 26

后续从《端A2A协议技术规范》相关文档确认：

- **Part 没有 `type` 字段**，合法字段是 `text / raw / url / data / mediaType / filename / metadata`；卡片指令放在 **`data`** 里
- 小艺收到 `data` 中的 `uiExtensionCard` 指令后拉起 `AgentUIExtensionAbility`，payload 经 `ability.want.params.payload` 透传
- Part / Artifact / TaskArtifactParam 与 `createA2AServer` 都来自 **`@kit.AgentFrameworkKit`，起始版本 API 26**

**本机约束**：DevEco SDK 与本机 OS 都是 **API 24**（`6.1.0.135`）。我们没有 AgentFrameworkKit 的 Part 类型，只能手写 JSON；实测在 task 的 `artifacts[].parts[]` 里追加带 `data` 的第二个 part 后，**整条响应不再渲染**（`ok:false`）。回滚后文本回复恢复（`ok:true`）。

**结论**：A 路线阻塞于 **API 26 SDK + 官方 A2A Server**，不是靠猜 JSON 能解决的。需要：升级 SDK 到 API 26 → 用 `createA2AServer` 构造 Part/Artifact → 再验证卡片。

**当前判断**：P1 先走文字引导 + 应用内入口；A 记为 ⛔ 阻塞（依赖 API 26）。

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
