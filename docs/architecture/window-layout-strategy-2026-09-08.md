# 窗口布局策略 module 设计 — 2026-09-08

> **状态**: implementation input（已完成拷问与原型验证；尚未进入实施 Spec）。
> **依据**: [`../research/harmonyos-multi-device-ui-adaptation-2026-09-08.md`](../research/harmonyos-multi-device-ui-adaptation-2026-09-08.md)。
> **范围**: `entry` 的窗口事实采集、布局语义映射、状态发布与页面消费；不改业务流程。

## 1. 已裁决产品语义

| 宽度档位 | 主导航 | Notes | AI |
|---|---|---|---|
| XS / SM | 底部导航 | 单栏，详情覆盖或跳页 | bottom sheet |
| MD | 左侧窄轨道 | 单栏，详情覆盖或跳页 | 右侧可收起 panel |
| LG / XL | 固定侧栏 | 列表—详情双栏 | 右侧 panel |

- 主从布局从 `WIDTH_LG` 开始，切点 840vp。
- 不采用 `NavigationMode.AUTO_WITH_ASPECT_RATIO`；布局策略显式输出 Stack/Split。
- 窗口宽度档位是主判据；高度档位只决定纵向压缩、滚动和键盘后的可用高度，不反向决定主从结构。
- 折叠屏专有信号本轮延期；折叠设备按普通可变窗口处理。
- XL 原型确认学科卡片维持两列，不因 XL 自动增加到四列。

## 2. 设计裁决

采用 **纯 `WindowLayoutPolicy` + `WindowLayoutStore` + AppStorage 发布 adapter**。

```text
Window + UIContext + UIObserver
             |
             v
WindowLayoutSourceImpl              entry/platform/
             |
             v
WindowLayoutStore                   entry/layout/
             |
             +--> WindowLayoutPolicy.resolve(facts)
             |          (纯映射，无 ArkUI / 无设备类型)
             v
WindowLayoutSnapshot                AppStorage('windowLayout')
             |
             +--> Index / Notes / independent @Entry pages / overlays
```

选择理由：

1. 当前存在 `Index`、`AiSettingsPage`、`SubjectDetailPage` 三个独立 `@Entry` 根；`@Provide/@Consume` 不能自然跨根传播。
2. `AppStorage` 已是项目既有跨页面通道，能在不提前迁移整个 router 的情况下覆盖所有页面。
3. 平台监听集中在每个 `WindowStage` 唯一的 store 内，页面不接触窗口 API。
4. 纯 policy 形成稳定测试面；未来把发布 adapter 从 AppStorage 换成 `@Provide` 时，policy 与 snapshot 无需变化。

拒绝：

- **页面各自监听窗口**：重复回调、生命周期泄漏、多真相源。
- **只用 `@Provide/@Consume`**：当前多 `@Entry` 根无法完整覆盖；若每个根各放 provider，会退化成重复监听。
- **静态进程单例 store**：所有权实际属于 `WindowStage`；未来多窗口会互相覆盖。
- **把所有页面尺寸都塞进 snapshot**：会形成布局上帝对象；局部尺寸仍由组件自身约束处理。

## 3. External seam：页面只学一个 snapshot

页面与测试的唯一 interface 是 `WindowLayoutSnapshot`。页面不获得 store、source、UIContext 或 Window。

### 3.1 建议类型

```ts
export enum AppNavigationMode {
  BOTTOM,
  RAIL,
  SIDEBAR
}

export enum AppDetailMode {
  STACK,
  SPLIT
}

export enum AssistantPresentation {
  BOTTOM_SHEET,
  SIDE_PANEL
}

export enum DetailPresentation {
  FULLSCREEN,
  SIDE_PANEL
}

export class WindowLayoutSnapshot {
  widthBreakpoint: WidthBreakpoint
  heightBreakpoint: HeightBreakpoint
  navigationMode: AppNavigationMode
  notesDetailMode: AppDetailMode
  assistantPresentation: AssistantPresentation
  noteDetailPresentation: DetailPresentation
  pageHorizontalPadding: number
  contentMaxWidth: number
  viewportWidth: number
  viewportHeight: number
  topInset: number
  bottomInset: number
}
```

Snapshot 的 interface 还包含这些不变量：

- `notesDetailMode` 只由宽度档位决定；LG/XL 永远为 SPLIT，其余为 STACK。
- `navigationMode` 只由宽度档位决定；XS/SM=BOTTOM，MD=RAIL，LG/XL=SIDEBAR。
- `assistantPresentation`：XS/SM=BOTTOM_SHEET，MD/LG/XL=SIDE_PANEL。
- `viewportWidth/Height` 和 inset 是当前可绘制区域事实，不是第二套断点。
- snapshot 是一次窗口观测的完整值；更新时整体替换引用，不修改 AppStorage 中对象的深层字段。
- snapshot 不含 current Tab、选中 Subject/KnowledgeUnit、滚动位置、聊天会话或任何业务数据。

### 3.2 为什么不输出 `subjectColumns`

原型对 XL 做过四列尝试，视觉过密；用户裁决恢复两列。现有 `SubjectGrid` 已把“一列列表 / 两列卡片”作为用户 `subjectViewMode` 偏好。

因此全局 snapshot 不拥有 Subject 列数：

- `SubjectGrid` 保留用户选择的 1/2 列。
- policy 只输出页面可用空间、padding、内容最大宽度和是否主从分栏。
- 避免窗口策略覆盖页面自身的信息密度偏好。

## 4. Internal seams

### 4.1 纯映射 policy

```ts
export interface IWindowLayoutPolicy {
  resolve(facts: WindowLayoutFacts): WindowLayoutSnapshot
}
```

`WindowLayoutFacts` 只包含一次观测的事实：宽高档位、drawable viewport、system avoid area。禁止包含 `deviceTypes`、方向字符串、机型名和折叠状态。

Policy 无状态、无 ArkUI import、无 AppStorage；所有断点映射、padding 和 max-width 表集中在此 module，页面禁止复制阈值。

### 4.2 平台 source

```ts
export interface IWindowLayoutSource {
  start(onChange: (facts: WindowLayoutFacts) => void): void
  stop(): void
  read(): WindowLayoutFacts
}
```

生产 adapter `WindowLayoutSourceImpl` 构造注入同一个 `window.Window`：

- `win.getUIContext().getWindowWidthBreakpoint()` / `getWindowHeightBreakpoint()`：初始断点。
- `win.getUIContext().getUIObserver().on('windowSizeLayoutBreakpointChange', cb)`：宽高档位事件。
- `win.getWindowProperties().drawableRect`：精确 viewport。
- `win.getWindowAvoidArea(AvoidAreaType.TYPE_SYSTEM)`：初始避让区。
- `win.on('windowSizeChange', cb)`：只用于刷新精确 viewport。
- `win.on('avoidAreaChange', cb)`：只用于刷新 inset。

所有 `on` 必须由同一个 adapter 保存 callback 引用，并在同一实例 `off`。`start/stop` 幂等。

### 4.3 store

```ts
export interface IWindowLayoutPublisher {
  publish(snapshot: WindowLayoutSnapshot): void
}

export class WindowLayoutStore {
  start(): void
  stop(): void
  current(): WindowLayoutSnapshot
}
```

Store 接受 source、policy 和 publisher：

1. `start()` 先 `source.read()`，保证事件到来前已有初值。
2. facts 变化后统一调用 policy，禁止不同事件各写一半状态。
3. 与当前 snapshot 值相同则不 publish，避免自由窗口拖动期间无意义重绘。
4. publish 时整体创建新的 snapshot 引用。
5. 任何部分注册失败都必须能由 `stop()` 清理已注册部分。

## 5. 所有权与生命周期

### 5.1 唯一 owner

`EntryAbility` 是 composition root，并拥有当前 `WindowStage` 的 store：

```text
onWindowStageCreate
  -> getMainWindow()
  -> configure immersive system bars
  -> create source/policy/publisher/store
  -> publish compact fallback
  -> loadContent('pages/Index')
  -> loadContent success callback
  -> store.start()

onWindowStageDestroy
  -> store.stop()
```

正式实现固定在 `loadContent` 成功回调后调用 `Window.getUIContext()` 并启动 store。`Window.getUIContext()` 返回与窗口内容关联的 UIContext；页面加载前提前调用会引入窗口状态异常分支，没有收益。首帧由 composition root 预置的 compact fallback 承担；store 启动后整体替换真实 snapshot。页面不得补建第二个监听。

### 5.2 AppStorage 发布 adapter

首版使用单一 key：`windowLayout`。

- composition root 在首个页面加载前设置 compact fallback。
- publisher 整体替换 `WindowLayoutSnapshot`。
- 页面使用 `@StorageProp('windowLayout')` 只读消费；禁止 `@StorageLink` 修改。
- 现有 `statusBarHeight` 在迁移期可由 publisher 同步维护，全部页面迁完后删除旧 key。

未来真正支持同时打开多个窗口时，AppStorage 必须改成 WindowStage 范围的 LocalStorage；本轮仅支持单主窗口。

## 6. 页面所有权

| 位置 | 可以做 | 禁止做 |
|---|---|---|
| `EntryAbility` | 构造/销毁 store；配置系统栏 | 决定导航或 Notes UI |
| `entry/layout/` | 映射窗口事实到跨页面布局语义 | 持业务状态；读取设备类型 |
| `entry/platform/` | 调 Window/UIObserver，成对监听 | 决定产品布局 |
| `Index` | 消费 navigationMode，排列同一组页面和共享导航 | 注册窗口监听；复制断点阈值 |
| `NotesPage` | 消费 notesDetailMode/content 约束，排列同一数据与详情 | 重建 NotesViewModel；按 tablet 判断 |
| Overlay | 消费 presentation/viewport/inset | 读取屏幕常量 `SCREEN_H` 决定窗口形态 |
| ViewModel/Service | 保持原业务状态与流程 | import layout module |

## 7. 正式目录建议

```text
entry/src/main/ets/
├── layout/
│   ├── WindowLayoutTypes.ets
│   ├── WindowLayoutPolicy.ets
│   ├── WindowLayoutStore.ets
│   └── WindowLayoutPublisher.ets
└── platform/
    └── WindowLayoutSourceImpl.ets
```

这些是非 UI module；页面表现仍留在既有 `pages/MainTabs/`、`pages/Notes/` 和 `overlays/`。原型文件和假数据不得复制进正式目录。

## 8. 测试面

### 8.1 Policy 表驱动测试

- WidthBreakpoint × HeightBreakpoint 全组合。
- XS/SM→BOTTOM；MD→RAIL；LG/XL→SIDEBAR。
- XS/SM/MD→STACK；LG/XL→SPLIT。
- XS/SM→BOTTOM_SHEET；MD+→SIDE_PANEL。
- 高度档位不得改变以上三项宽度语义。
- XL 保持 Notes 页面用户选择的 1/2 列，不存在 policy 四列输出。

### 8.2 Store/source 生命周期测试

- 初始 snapshot 在首个事件前发布。
- 重复 start 不重复注册。
- breakpoint 事件同时更新宽高档位。
- windowSizeChange 只更新 viewport，不改变宽度语义来源。
- avoidAreaChange 更新 inset。
- 相同 snapshot 不重复发布。
- stop 使用相同实例和 callback 注销，且幂等。

### 8.3 结构守门

- `entry/pages` 与 `entry/overlays` 禁止出现 `getWindowWidthBreakpoint`、`windowSizeLayoutBreakpointChange`、`deviceTypes`、`isFoldable`。
- `WindowLayoutPolicy` 禁止 import `@kit.*`、ViewModel、Service、DAO。
- `WindowLayoutSnapshot` 禁止出现业务类型。
- 每个业务页面只允许消费 snapshot 或经壳层传入的窄语义 Prop。

### 8.4 视觉/运行矩阵

- 599/600、839/840 边界。
- 300/360/768/1024/1440 代表宽度；每个宽度高窗与低窗。
- 真实窗口 auto 模式是正式验收；强制 width preset 只留在测试 harness，不进入生产 UI。
- SM→LG→SM 后当前 Tab、选中 Subject/KnowledgeUnit、滚动位置、聊天状态不丢失。
- 折叠状态、折痕区域不在本轮矩阵。

## 9. Phase 1—3 人员边界

### Phase 1 — 布局基础

单一 UI owner 独占 `entry/layout/`、`entry/platform/`、`EntryAbility` 和 AppStorage key。

退出条件：唯一事件源、成对注销、初值可用、状态连续、零业务流程迁移。

### Phase 2 — 应用壳 + Notes tracer bullet

沿用同一 owner，独占 `Index`、`pages/MainTabs/`、`NotesPage` 及布局共享文件。

退出条件：SM 底栏、MD 轨道、LG/XL 侧栏；Notes LG+ 双栏；不存在伪 AI Tab；页面/选中/滚动状态不丢失。

### Phase 3 — 页面并行迁移

可按 Home、AiSettings/Profile、浮层拆 worktree。页面 owner 只改自己的页面目录，不改 layout、platform、公共 token、Index 和共享导航；共享改动交 UI integrator。

YunCeH 后端/LLM workstream 不改 `entry` 页面。

## 10. Spec 必须明确的迁移期问题

1. `SubjectDetailPage` 是独立 `@Entry`，而 Notes LG+ 双栏要求复用其内容；Spec 应先提取可嵌入的详情 organism/template，再让独立路由页与双栏壳共同消费，禁止复制页面。
2. `AiSettingsPage` 也是独立 `@Entry`；AppStorage 是首版覆盖多根的理由，不能漏测。
3. 删除伪 AI Tab 时，`Index.lastContentIndex` 与 `HomePage.onGoReview` 的索引需同步迁移，单列 ticket。
4. `statusBarHeight` 的旧消费者较多；采用双写迁移，不在 Phase 1 一次删除。
5. XL 学科块固定两列的原型裁决必须进入 acceptance criteria。

## 11. 下一步

将本设计与研究报告、原型结论综合成实施 Spec，再拆 blocker-first tickets。不要直接把原型 ArkTS 复制进生产；原型只证明布局语义和生命周期可行。
