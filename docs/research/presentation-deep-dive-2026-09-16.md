# 呈现段深度调研 — MindTrace

> 调研日期: 2026-09-16
> 调研范围: 入库**后**用户能看到什么(笔记列表 / 笔记详情 / 知识星系);严格隔离入库链(`Dispatcher` / `CaptureGraph` / `NoteDaoAdapter` / `AiService.capture` 内部 / `DatabaseHelper.init` 内部),只在涉及呈现层错误处理时引用。
> 调研目的: 深挖 `docs/research/data-presentation-flow-2026-09-16.md` 已覆盖的"读出段 → 呈现段"接缝,补 Q1-Q5 五类问题。
> 约束: 只读不改,只做调研,不做修建议;**所有论断必须带 file_path:line_number**;**全部相对路径**(仓库根 `D:\HMgent\MindTrace\`,文档以仓库根为起点)。
>
> 前置依赖: `docs/research/data-presentation-flow-2026-09-16.md`(入库 + 持久化 + 读出 + 顶层序列化)。本报告专注其 §5.2 / §6.1 / §7 中提及的 3 个 ViewModel + 3 个 Page。

---

## 1. TL;DR

呈现段最严重的不是渲染,而是 **3 个 ViewModel 全部静默吞错 + DB 写后端从不让用户知道失败**:

1. **写入端 bug(对呈现段是致命约束)**: `agents/src/main/ets/agents/KnowledgeModel.ets:1222-1223` `KnowledgeModel.toKnowledgeUnit` 把 `prerequisites: []` 和 `related: []` 硬编码为空数组。**所有从 AI 入库的新笔记,其关系字段都为空**——即便把渲染逻辑修到完美,数据本身就是空的,所以"关系线空"不是 UI bug,是数据 bug。
2. **渲染端 bug(纵深问题)**: `entry/src/main/ets/pages/Review/ReviewGraphView.ets:1220-1225` + `:1677-1688` — `RelationLine` 只在用户 **点行星** 触发 `focusedPlanetId` 后才渲染,即便关系线存在,用户也得先点;并且 `KnowledgeGalaxyViewModel.ets:498` `buildLinks` 按学科内 `bundles` 查找,**跨学科关系永远找不到**。
3. **错误处理 bug(用户看不见失败)**: 3 个 ViewModel 全部 `console.warn` + 返回空 / false,**无任何用户可见反馈**。`HomePage` 和 `NotesPage` 的 `vm.loadNotes` 失败时只 `promptAction.showToast` 弹"加载失败"或"Failed to load notes",`KnowledgeGalaxyViewModel.load` 失败时 `ReviewGraphView` 弹"知识星系加载失败"但 UI 继续渲染空星系列。`SubjectDetailPage` 失败 toast 之后 `ensureSubject()` 会把 `subject` 清空,导致用户连学科都找不到。

最严重的综合场景: **DB init fire-and-forget 失败** → `UiDataCacheService` 缓存 `null` → 3 个 Page 全显示空状态/EmptyState,但用户 **完全无感知**,且 3 个 ViewModel 都各跑一次 `DatabaseHelper.init`(双倍开销、并发不安全)。

---

## 2. 文件清单与确认

呈现段实际渲染路径(以代码为准,AGENTS.md §关键架构提到的 `pages/KnowledgeGalaxy*` 不存在,**已确认**:

| AGENTS.md 提到的 | 实际文件 | 备注 |
|---|---|---|
| `pages/Notes*` (列表页) | `entry/src/main/ets/pages/Notes/NotesPage.ets` | 入口是学科网格(`SubjectGrid`),**不是直接 NoteCard 列表**;真正的 NoteCard 列表在 `SubjectDetailPage` 内 |
| `pages/Notes/NoteDetail*` | **不存在** — 不存在独立 NoteDetail Page | 详情/编辑 UI 在 `entry/src/main/ets/overlays/NoteDetailOverlay/NoteDetailOverlay.ets`(9 个文件),由 `HomePage` / `SubjectDetailPage` / `ReviewGraphView` 三处按需挂载 |
| `pages/KnowledgeGalaxy*` | **不存在** — AGENTS.md 失实 | 真实位置是 `entry/src/main/ets/pages/Review/ReviewGraphView.ets:125` 的 `ReviewGraphView` + `SubjectUniverseView` + `SubjectGalaxyView` 三个组件 |

**这些页面是 sibling,不是 nested** (`entry/src/main/ets/pages/Index.ets:47-65` `Tabs` 的 5 个 `TabContent`):Home / Notes / 占位(AI 浮窗触发)/ Review / Profile,NoteDetailOverlay 是 **在 Page 上覆盖的浮层**,不是 push 出去的页面。

---

## 3. Q1 数据流(从 store → UI)

### 3.1 笔记列表 / 详情 — `NotesPage` × `SubjectDetailPage`

| 阶段 | 文件:行 | 说明 |
|---|---|---|
| **入口触发** | `entry/src/main/ets/pages/Notes/NotesPage.ets:29-38` | `aboutToAppear` + `onPageShow` 都调 `reloadNotes()`;`@StorageProp('notesVersion') @Watch('onNotesVersionChange')` (`NotesPage.ets:23`) 写后自动重拉 |
| **Page → ViewModel** | `NotesPage.ets:50` | `this.vm.loadNotes(getContext(this))` — 同步 fire-and-forget,但 `loadedNotesVersion` / `loadingNotesVersion` 去重(`NotesPage.ets:46-49`) |
| **ViewModel → 缓存** | `entry/src/main/ets/viewmodels/NotesViewModel.ets:34-57` | `UiDataCacheService.loadNotesSnapshot(context, version)` 走 `notesVersion` 缓存键;`getSubjectGroups(version)` 缓存命中免重算分组 |
| **缓存 → DAO** | `entry/src/main/ets/services/UiDataCacheService.ets:268-292` | 缓存未命中走 `DatabaseHelper.init` + `new NoteDao(store).queryAllMetadata()`(`NoteDao.ets:311-331`) |
| **ViewModel → Page** | `NotesPage.ets:50` | `this.vm` 是 `@State`(`NotesPage.ets:24`),ArkTS `@State` + `@Observed class` 双驱动;失败仍写 `this.vm.notes = []`,UI 自然重渲染空 |
| **学科详情二级页** | `entry/src/main/ets/pages/Notes/SubjectDetailPage.ets:29-37` | `@Entry @Component` 真路由页;`readParams` 读 router params 的 subject(`SubjectDetailPage.ets:43-49`);`reloadNotes` 用 `version + subject` 作为 reloadKey 去重(`SubjectDetailPage.ets:51-70`) |
| **学科笔记列表** | `SubjectDetailPage.ets:176-179` `SubjectNoteList` | 真正的 LazyForEach List |
| **详情打开** | `SubjectDetailPage.ets:111-119` `openDetail` | `this.vm.loadNote(...)` 走 `UiDataCacheService.loadDetail` (LRU 8 条 / 512KB,`UiDataCacheService.ets:111-112` + `:294-320`) |
| **详情浮层渲染** | `NotesPage.ets:114` 不开 overlay;`SubjectDetailPage.ets:186-195` 挂 `NoteDetailOverlay` | 详情的 listItem 点击 → `openDetail` → `NoteDetailOverlay({ note, unit, units, onClose, onDelete, onSaved })` |

**ForEach / LazyForEach 使用情况(列表段)**:

| 文件:行 | 容器 | key 函数 | 是否稳定 |
|---|---|---|---|
| `NotesPage.ets:33` 不在 — 不直接 ForEach 笔记 | — | — | — |
| `entry/src/main/ets/pages/Notes/NotesList.ets:31-43` | `List + ForEach` | `(note) => note.id.toString()` | 是 |
| `entry/src/main/ets/pages/Notes/SubjectNoteList.ets:79-97` | `List + LazyForEach + IDataSource` | `(note) => note.id.toString()` (`SubjectNoteList.ets:96`) | 是 |
| `entry/src/main/ets/pages/Notes/SubjectGrid.ets:33-47` | `Grid + ForEach` | `(group) => group.subject` | 是(但同 subject 重复会冲掉,场景少见) |
| `entry/src/main/ets/pages/Notes/NotesSummaryPanel.ets:69-80, 88-97, 110-128` | `Row + ForEach` × 3 处 | 各自稳定 (item.label / group.subject + "_bar" / group.subject + "_legend") | 是 |
| `entry/src/main/ets/pages/Notes/TypeTabRow.ets:19-31` | `Scroll(Row) + ForEach` | `(type) => type` | 是 |

### 3.2 知识星系 — `ReviewGraphView` × `KnowledgeGalaxyViewModel`

| 阶段 | 文件:行 | 说明 |
|---|---|---|
| **路由入口** | `entry/src/main/ets/pages/Index.ets:58-62` Review Tab → `ReviewPage({onGoAI})` | Review Tab 是 `Index.ets:47-65` 第 4 个 TabContent |
| **Tab 切换** | `entry/src/main/ets/pages/Review/ReviewPage.ets:286-288` `else { ReviewGraphView(...) }` | `REVIEW_TAB_GRAPH = 1`(`ReviewPage.ets:20`) |
| **页面触发** | `entry/src/main/ets/pages/Review/ReviewGraphView.ets:143-153` | `aboutToAppear` 调 `reloadGalaxy(false)`;`@StorageProp('notesVersion') @Watch('onNotesVersionChange')` 写后重拉(reset rotation) |
| **Page → ViewModel** | `ReviewGraphView.ets:155-175` | `this.vm.load(getContext(this)).then(ok => ...)`;`ok = false` 走 toast,`ok = true` 走选择状态恢复 |
| **ViewModel → DAO 直连** | `entry/src/main/ets/viewmodels/KnowledgeGalaxyViewModel.ets:215-243` | `load()` → `loadPersistedUnits()` → **不走 `UiDataCacheService`**;直接 `await DatabaseHelper.init(context) → new NoteDao(store).queryAll()`(`KnowledgeGalaxyViewModel.ets:237-238`) |
| **ViewModel → Page** | `ReviewGraphView.ets:128` `@State vm: KnowledgeGalaxyViewModel = new KnowledgeGalaxyViewModel()` + `@Observed` 类(`KnowledgeGalaxyViewModel.ets:207`) | 嵌套 `SubjectSystem.planets[].note` 也是 `NoteItem`,需要 `@Observed` 链才能深刷新 |
| **空数据 → UI** | `ReviewGraphView.ets:380-381` | `vm.systems.length === 0` → `EmptyState()`(`ReviewGraphView.ets:470-518`),画"还没有知识星系"+"打开 AI"按钮 |

**ForEach / LazyForEach 使用情况(星系段)**:

| 文件:行 | 容器 | key 函数 | 风险 |
|---|---|---|---|
| `ReviewGraphView.ets:573-583` | `Stack + ForEach + ForEach` (9 元素 tile 网格) | `"overview_tile_x_" + copyX` / `"overview_tile_y_" + copyY` | 稳定 |
| `ReviewGraphView.ets:623-628` | `Stack + ForEach` (systems) | `system.subject` | **同 subject 重复会冲掉**(罕见但理论可能) |
| `ReviewGraphView.ets:643-648, 712-722` | `ForEach` × 2 (orbits / planets) | `system.subject + "_" + orbit.chapter + "_..."` | 稳定 |
| `ReviewGraphView.ets:1213-1218` | `ForEach` (orbits) | `orbit.chapter` | 同一 chapter 在多 subject 下会冲突;但 `SubjectGalaxyView` 只画单学科,实际安全 |
| `ReviewGraphView.ets:1220-1225` | `ForEach` (`focusedLinks()`) | `link.type + "_" + link.fromId + "_" + link.toId` | **空时 ForEach 不进**,符合预期 |
| `ReviewGraphView.ets:1404-1416` | `ForEach + ForEach` (PlanetLayer back/front) | `orbit.chapter + "_" + planet.id + (isBackLayer ? "_back" : "_front")` | 稳定 |
| `ReviewGraphView.ets:763-768, 1487-1497` | 星空背景 `ForEach` | `"overview_star_" + index` | 稳定 |
| **没有 LazyForEach** | (整个星系组件都是绝对定位 Stack,不是 List) | — | 渲染量受 `maxOverviewPlanets` (`ReviewGraphView.ets:1125-1136`) 限制 |

### 3.3 Home 顶环 + 最近笔记(`HomeViewModel` 旁支)

| 阶段 | 文件:行 | 说明 |
|---|---|---|
| **触发** | `entry/src/main/ets/pages/Home/HomePage.ets:38-48` | 同 `NotesPage`,3 个触发点:`aboutToAppear` / `onPageShow` / `onNotesVersionChange` |
| **Page → ViewModel** | `HomePage.ets:50-67` `reloadHome` | 同 `NotesPage` 的 `loadedNotesVersion` 去重模式 |
| **ViewModel → 缓存** | `entry/src/main/ets/viewmodels/HomeViewModel.ets:25-41` `loadNotes` | 走 `UiDataCacheService.loadNotesSnapshot`(`UiDataCacheService.ets:268-292` → `queryAllMetadata`),**与 NotesViewModel 共享同一缓存键** |
| **详情打开** | `HomePage.ets:69-78` `openDetail` | 同 `SubjectDetailPage.openDetail`,走 `UiDataCacheService.loadDetail` |
| **空 / 少数据 UI** | `HomePage.ets:167-168` `if (!this.reviewRingCollapsed && this.vm.notes.length < 3)` → `ReminderBanner` | "0 笔记" / "1-2 笔记" 给提示,3+ 笔记隐去 |

**HomeViewModel 不渲染列表本身** — 只喂给 `HeroBanner` / `HomeCollapsedReview` / `ReminderBanner` / `HomeRecentNotes` 的 `notes` prop。

---

## 4. Q2 错误处理路径(关键)

### 4.1 三态对比表

| ViewModel | 拉数据失败 | 静默空状态 | 显式错误状态 | UI 反馈 |
|---|---|---|---|---|
| `HomeViewModel.loadNotes` (`HomeViewModel.ets:34-40`) | `console.warn` + `this.notes = []` + 返回 `false` | 是 | 否 | `HomePage.ets:60` `promptAction.showToast({ message: "Failed to load notes" })` — **国际化残缺**(中文 vs 英文混用) |
| `HomeViewModel.loadNote` (`HomeViewModel.ets:43-53`) | `console.warn` + 返回 `null` + 不更新 `this.selectedUnit` | 是(`selectedUnit = null`) | 否(`NoteDetailOverlay.effectiveUnit()` 返回 `unit` 或 `localUnit`,两者都 null → `LoadingState()` (`NoteDetailOverlay.ets:213-237`)) | **LoadingState 永久转圈**(因为没人触发二次重试),用户看到"正在加载笔记内容"卡死 |
| `NotesViewModel.loadNotes` (`NotesViewModel.ets:34-57`) | 同 HomeViewModel — 静默空数组 + false | 是 | 否 | `NotesPage.ets:54` toast `"笔记加载失败"`(中文) |
| `NotesViewModel.loadNote` (`NotesViewModel.ets:59-69`) | `console.warn` + 返回 null | 是 | 否 | 同 HomeViewModel.loadNote,**LoadingState 永久转圈** |
| `KnowledgeGalaxyViewModel.load` (`KnowledgeGalaxyViewModel.ets:215-233`) | `console.warn` + 全字段清零 + 返回 `false` | 是(`systems = []` → `EmptyState`) | 否 | `ReviewGraphView.ets:158` toast `"知识星系加载失败"`,但 `EmptyState()` 仍渲染,用户既看到 toast 又看到"还没有知识星系" — **信号混乱** |
| `KnowledgeGalaxyViewModel.loadNote` (`KnowledgeGalaxyViewModel.ets:245-260`) | `console.warn` + 返回 `null` | 是(`selectedUnit` 保持 null,沿用 planet.unit 的 NoteItem) | 否 | **无任何反馈** — 用户期望查看详情,看到 NoteDetailOverlay 用 `planet.unit`(来自 `bundle.unit`,`KnowledgeGalaxyViewModel.ets:602-616`)做 fallback,但 fallback 内容是 `unitsToNotes` 阶段的副本,**与数据库可能不一致**(写后版本冲突检测不到) |
| `KnowledgeGalaxyViewModel.loadPersistedUnits` (`KnowledgeGalaxyViewModel.ets:235-243`) | `console.warn` + 返回 `[]` | 是(被 `withPreviewUnits` 吞,preview 默认关闭) | 否 | 取决于上层 `load` 的 toast |
| `KnowledgeGalaxyViewModel.deleteNote` (`KnowledgeGalaxyViewModel.ets:262-277`) | `console.warn` + 返回 `false` | 是 | 否 | `ReviewGraphView.ets:295` toast `"删除笔记失败"` |

### 4.2 错误处理关键代码片段

**ViewModel 一致的"console.warn + 空"模式**(用 HomeViewModel.loadNotes 为例,其他 5 处完全同构):

```ts
// entry/src/main/ets/viewmodels/HomeViewModel.ets:25-41
async loadNotes(context: Context): Promise<boolean> {
  try {
    const version: number = UiDataCacheService.currentNotesVersion()
    const snapshot: NotesSnapshot = await UiDataCacheService.loadNotesSnapshot(context, version)
    this.units = snapshot.units
    this.notes = snapshot.notes
    this.refreshStats()
    PreloadQueue.preloadHome(context)
    return true
  } catch (e) {
    console.warn("[HomeViewModel] loadNotes failed: " + ((e as Error).message ?? String(e)))
    this.units = []
    this.notes = []
    this.refreshStats()
    return false
  }
}
```

**Page 层"toast 但继续渲染"模式**(用 ReviewGraphView 为例):

```ts
// entry/src/main/ets/pages/Review/ReviewGraphView.ets:155-175
private reloadGalaxy(keepSelection: boolean): void {
  this.vm.load(getContext(this)).then((ok: boolean): void => {
    if (!ok) {
      try { promptAction.showToast({ message: "知识星系加载失败", duration: 1500 }) } catch (_e) {}
      this.stopRotation()
      return
    }
    ...
  })
}
```

**SubjectDetailPage 失败后 subject 被清空**(边角 bug):

```ts
// entry/src/main/ets/pages/Notes/SubjectDetailPage.ets:51-70 + 72-82
private reloadNotes(): void {
  ...
  this.vm.loadNotes(getContext(this)).then((ok: boolean): void => {
    if (!ok) {
      try { promptAction.showToast({ message: "笔记加载失败", duration: 1500 }) } catch (_e) {}
      return  // ⚠ enter success branch 上没走 ensureSubject, 但 loadedReloadKey 也没更新
    }
    this.ensureSubject()  // ⚠ 如果 vm.subjectGroups 为空(notes=[]), 这里把 this.subject 清成 ""
    this.loadedReloadKey = version.toString() + "|" + this.subject
  })
  ...
}
private ensureSubject(): void {
  if (this.vm.subjectGroups.length === 0) {
    this.subject = ""   // ⚠ 失败后用户连学科都看不到,UI 仍渲染但全空
    return
  }
  ...
}
```

### 4.3 与 #3(DB init fire-and-forget)的呼应

- `entry/src/main/ets/entryability/EntryAbility.ets:44-49` 启动时 `DatabaseHelper.init` fire-and-forget → 失败 `hilog.error` 不到 toast。
- 用户进入 App → 5 Tab 任意一个 `aboutToAppear` 触发 `ViewModel.load → DatabaseHelper.init(...)` → 首次失败 throw → ViewModel `console.warn` + 空 → Page toast `"...加载失败"` + 空状态/EmptyState。
- **致命场景**: DB init 失败时,`UiDataCacheService.queryNotesSnapshot`(`UiDataCacheService.ets:288-291`)的 `DatabaseHelper.init` throw,**缓存 key 永远不更新**。每次 `loadNotes` 都会重试 init + toast + 空状态 — **用户每次切回 Tab 都看到一次 toast**,且数据永远空。

### 4.4 错误信息 i18n 混用

- `HomePage.ets:60`: `"Failed to load notes"`(英文)
- `SubjectDetailPage.ets:60`: `"笔记加载失败"`(中文)
- `SubjectDetailPage.ets:137, 139`: `"Note deleted"` / `"Delete failed"`(英文)
- `NotesPage.ets:54`: `"笔记加载失败"`(中文)
- `NotesPage.ets:75`: `"\u641c\u7d22\u529f\u80fd\u5f00\u53d1\u4e2d"`(中文 unicode escape)
- `ReviewGraphView.ets:158`: `"知识星系加载失败"`(中文)
- `ReviewGraphView.ets:293, 295`: `"已删除笔记"` / `"删除笔记失败"`(中文)
- `ReviewPage.ets:56`: `"复习数据加载失败"`(中文)
- `ReviewPage.ets:139`: `"请输入复习计划"`(中文)
- `ReviewPage.ets:162, 170, 213, 221, 229, 234`: `"已加入实时队列"` 等(中文)
- `NoteDetailOverlay.ets:350, 418, 422, 442, 651`: `笔记仍在加载` / `请输入标题` / `摘要和正文至少填写一项` / `笔记已被修改,请重新打开后再保存` / `分享功能暂未开放`(中文)

**`HomePage` 和 `SubjectDetailPage` 的 toast 中英混用**(`Failed to load notes` + `Note deleted` + `Delete failed` 三处英文),与项目其他位置的中文 toast 不一致 — 大概率是早期版本未统一 i18n。

---

## 5. Q3 缓存一致性

### 5.1 `UiDataCacheService` 命中逻辑(共享层)

- **缓存键**: `notesVersion`(`AppStorage.get<number>('notesVersion')`) + `studyPlanVersion`(私有静态 `UiDataCacheService.studyPlanVersion`(`UiDataCacheService.ets:123`))
- **3 个快照字段**(`UiDataCacheService.ets:115-126`):
  - `notesSnapshot: NotesSnapshot | null`(`UiDataCacheService.ets:116`) — 由 `HomeViewModel` / `NotesViewModel` 共享
  - `subjectGroupsSnapshot: SubjectGroupsSnapshot | null`(`UiDataCacheService.ets:117`) — 由 `NotesViewModel` 共享
  - `studyPlanSnapshot: StudyPlanSnapshot | null`(`UiDataCacheService.ets:118`) — `StudyPlanViewModel` 私有(本次不深入)
- **in-flight join**(`UiDataCacheService.ets:268-286`): `notesLoadingPromise` 在同 version 下复用,**避免并发 `queryAllMetadata`**。**`studyPlanLoading` 同理**(`UiDataCacheService.ets:341-352`)。
- **详情 LRU**(`UiDataCacheService.ets:111-112`): 8 条 / 512KB;`detailLoadingEntries` 同 in-flight join(`UiDataCacheService.ets:294-334`)。

### 5.2 谁走缓存 / 谁绕过

| 调用方 | 入口 | 走的路径 | 是否共享缓存 |
|---|---|---|---|
| `HomeViewModel.loadNotes` (`HomeViewModel.ets:28`) | `UiDataCacheService.loadNotesSnapshot` | ✅ 共享 notesSnapshot | 是 |
| `HomeViewModel.loadNote` (`HomeViewModel.ets:48`) | `UiDataCacheService.loadDetail` | ✅ 共享 detail LRU | 是 |
| `NotesViewModel.loadNotes` (`NotesViewModel.ets:37`) | `UiDataCacheService.loadNotesSnapshot` | ✅ 同 HomeViewModel 共享 | 是 |
| `NotesViewModel.loadNote` (`NotesViewModel.ets:64`) | `UiDataCacheService.loadDetail` | ✅ 同 HomeViewModel 共享 | 是 |
| `KnowledgeGalaxyViewModel.load` (`KnowledgeGalaxyViewModel.ets:237`) | **`new NoteDao(store).queryAll()`** 直连 | ❌ **绕过缓存** | **否** |
| `KnowledgeGalaxyViewModel.loadNote` (`KnowledgeGalaxyViewModel.ets:255`) | **`new NoteDao(store).queryById()`** 直连 | ❌ **绕过缓存**(不走 `loadDetail`) | **否** |
| `KnowledgeGalaxyViewModel.deleteNote` (`KnowledgeGalaxyViewModel.ets:271`) | `new NoteDao(store).deleteById` | 无对应缓存失效(只手动 `AppStorage.setOrCreate('notesVersion', v+1)` `KnowledgeGalaxyViewModel.ets:291-292`) | — |
| `NotesViewModel.deleteNote` (`NotesViewModel.ets:74`) | 同上 + `UiDataCacheService.invalidateNote(id)` (`NotesViewModel.ets:73`) | ✅ **有失效逻辑** | 是 |
| `HomeViewModel.deleteNote` (`HomeViewModel.ets:57`) | 同上 + `UiDataCacheService.invalidateNote(id)` (`HomeViewModel.ets:57`) | ✅ | 是 |

### 5.3 数据不一致风险(双跑)

- **`queryAllMetadata` vs `queryAll` 并发**: HomeViewModel 与 KnowledgeGalaxyViewModel 在 `aboutToAppear` 同时触发,前者走 `queryAllMetadata`(`NoteDao.ets:311-331`),后者走 `queryAll`(`NoteDao.ets:288-308`)。**两个 SELECT 列集合不同**,SQL 解析时间不同,但 RDB 共享同一 store 句柄 — 不会有数据冲突,但有 **double DB read**。
- **`loadNote` 路径分叉**: HomePage / SubjectDetailPage 走 `UiDataCacheService.loadDetail`(`UiDataCacheService.ets:294-320`),ReviewGraphView 走 `KnowledgeGalaxyViewModel.loadNote → queryById`(`KnowledgeGalaxyViewModel.ets:253-259`)。
  - **场景**: 用户在 HomePage 打开笔记详情 → `loadDetail` 写入 LRU(cs 7 / 7 条)。用户切到 Review Tab,点行星 → `KnowledgeGalaxyViewModel.loadNote` **绕过 LRU**,直查 DB。
  - **后果**: ① 重复 IO;② 写后 `notesVersion` 递增,**`loadDetail` 的 cache key (`detailKey = id|updatedAt|unitVersion|version` `UiDataCacheService.ets:370-372`)与 queryById 不同步** — 但因为 queryById 也不写 LRU, 所以"绕过"反而绕过了 LRU 的版本检查,理论上能拿到最新数据;但**如果 NotesViewModel.deleteNote 后 invalidate 了 LRU,ReviewGraphView 拿到的也是最新**,一致性是侥幸维持的。
- **`deleteNote` 三处实现**: 全部 `AppStorage.setOrCreate('notesVersion', v+1)` + `loadNotes` 重拉,但 `KnowledgeGalaxyViewModel.deleteNote` 用 `vm.load(context)` 自己重拉(`KnowledgeGalaxyViewModel.ets:272`),**`UiDataCacheService` 没被失效**(`UiDataCacheService.invalidateNote(id)` 仅在 NotesViewModel / HomeViewModel 中调) — 写后 HomePage 和 NotesPage 会重拉(因 `notesVersion` 变化),但 **UiDataCacheService.notesSnapshot 仍在**,新数据只在 `queryNotesSnapshot` 写入后覆盖(`UiDataCacheService.ets:289-292`)。

---

## 6. Q4 字段差异量化

### 6.1 NoteDao 查询列对比(SQL 等价文本)

**`NoteDao.queryAll()`**(`entry/src/main/ets/database/NoteDao.ets:288-308`):
```sql
SELECT * FROM knowledge_unit ORDER BY created_at DESC
```
返回 **22 列**(实际表 22 列 — `id` / `title` / `content` / `summary` / `tags` / `subject` / `category` / `chapter` / `difficulty` / `source` / `created_at` / `updated_at` / `review_status` / `next_review_at` / `interval_days` / `ease_factor` / `repetitions` / `prerequisites` / `related` / `embedding` / `user_id` / `version`),通过 `NoteDao.rowToUnit`(`NoteDao.ets:358-383`)填充。

**`NoteDao.queryAllMetadata()`**(`entry/src/main/ets/database/NoteDao.ets:311-331`):
```sql
SELECT id, title, summary, tags, subject, category, chapter, difficulty, source,
       created_at, updated_at, review_status, next_review_at, interval_days,
       ease_factor, repetitions, user_id, version
FROM knowledge_unit
ORDER BY created_at DESC
```
列定义在 `NoteDao.ets:29-33`:
```ts
const NOTE_METADATA_COLUMNS: string[] = [
  'id', 'title', 'summary', 'tags', 'subject', 'category', 'chapter', 'difficulty', 'source',
  'created_at', 'updated_at', 'review_status', 'next_review_at', 'interval_days',
  'ease_factor', 'repetitions', 'user_id', 'version',
]
```
**18 列**。通过 `NoteDao.rowToMetadataUnit`(`NoteDao.ets:385-410`)填充,**4 个字段硬编码为空**:

```ts
// entry/src/main/ets/database/NoteDao.ets:404-406 (rowToMetadataUnit)
prerequisites: [],
related: [],
embedding: [],
```

### 6.2 字段差异表(22 → 18)

| # | 列名 | queryAll | queryAllMetadata | 解码方式 |
|---|---|---|---|---|
| 1 | `id` | ✅ | ✅ | `readString` |
| 2 | `title` | ✅ | ✅ | `readString` |
| 3 | **`content`** | ✅ 实际读 | ❌ **硬编码 `''`** | `readString` / `content: ''`(`NoteDao.ets:389`) |
| 4 | `summary` | ✅ | ✅ | `readString` |
| 5 | `tags` | ✅ | ✅ | `parseArray(readString(...))` |
| 6 | `subject` | ✅ | ✅ | `readString` |
| 7 | `category` | ✅ | ✅ | `readString` |
| 8 | `chapter` | ✅ | ✅ | `readString` |
| 9 | `difficulty` | ✅ | ✅ | `parseDifficulty(readLong)` |
| 10 | `source` | ✅ | ✅ | `readString` |
| 11 | `created_at` | ✅ | ✅ | `readLong` |
| 12 | `updated_at` | ✅ | ✅ | `readLong` |
| 13 | `review_status` | ✅ | ✅ | `parseReviewStatus(readString)` |
| 14 | `next_review_at` | ✅ | ✅ | `readLong` |
| 15 | `interval_days` | ✅ | ✅ | `readLong` |
| 16 | `ease_factor` | ✅ | ✅ | `readDouble` |
| 17 | `repetitions` | ✅ | ✅ | `readLong` |
| 18 | **`prerequisites`** | ✅ 实际读 | ❌ **硬编码 `[]`** | `parseArray(readString)` / `prerequisites: []`(`NoteDao.ets:404`) |
| 19 | **`related`** | ✅ 实际读 | ❌ **硬编码 `[]`** | `parseArray(readString)` / `related: []`(`NoteDao.ets:405`) |
| 20 | **`embedding`** | ✅ 实际读 | ❌ **硬编码 `[]`** | `parseNumberArray(readString)` / `embedding: []`(`NoteDao.ets:406`) |
| 21 | `user_id` | ✅ | ✅ | `readString` |
| 22 | `version` | ✅ | ✅ | `readLong` |

### 6.3 KnowledgeGalaxyViewModel 实际用的字段

| 字段 | 来源 | 渲染位置 |
|---|---|---|
| `unit.id` | queryAll 行 1 | `PlanetNode.id` (`KnowledgeGalaxyViewModel.ets:80`), `link.fromId/toId` (`KnowledgeGalaxyViewModel.ets:71-72`), ForEach key |
| `unit.title` | queryAll 行 2 | `NoteItem.title` (走 `unitToNoteItem`(`utils/NoteItemMapper.ets:106-126`)) → `planetLabel()`(`ReviewGraphView.ets:116-123`) |
| `unit.subject` | queryAll 行 6 | `SubjectSystem.subject`(`KnowledgeGalaxyViewModel.ets:157`);`buildSystems` 按 subject 分组(`KnowledgeGalaxyViewModel.ets:468-491`) |
| `unit.category` | queryAll 行 7 | `NoteItem.type` → `PlanetNode.type`(`KnowledgeGalaxyViewModel.ets:608`);`typeColor()`(`KnowledgeGalaxyViewModel.ets:609`) |
| `unit.chapter` | queryAll 行 8 | `ChapterOrbit.chapter`(`KnowledgeGalaxyViewModel.ets:750-753`);`buildChapterOrbits` 按 chapter 分组(`KnowledgeGalaxyViewModel.ets:535-576`) |
| `unit.difficulty` | queryAll 行 9 | `PlanetNode.size` 计算(`KnowledgeGalaxyViewModel.ets:600` 通过 `repetitions`);不直接渲染 |
| `unit.source` | queryAll 行 10 | 未渲染 |
| `unit.createdAt` | queryAll 行 11 | `NoteItem.date`(`NoteItemMapper.ets:93-96`);星系本身不渲染日期 |
| `unit.updatedAt` | queryAll 行 12 | LRU key(`UiDataCacheService.ets:370-372`),星系不读 |
| `unit.reviewStatus` | queryAll 行 13 | `NoteItem.conf`(`NoteItemMapper.ets:98-104`) → `PlanetNode.mastery`(`KnowledgeGalaxyViewModel.ets:597`);`PlanetNode.size`(`KnowledgeGalaxyViewModel.ets:600`);`PlanetNode.alpha`(`KnowledgeGalaxyViewModel.ets:601`);**最重要:决定星球颜色深浅和大小** |
| `unit.repetitions` | queryAll 行 17 | `PlanetNode.size`(`KnowledgeGalaxyViewModel.ets:600`) |
| **`unit.prerequisites`** | queryAll 行 18 | `buildLinks` 读 `bundle.unit.prerequisites`(`KnowledgeGalaxyViewModel.ets:627-642`) |
| **`unit.related`** | queryAll 行 19 | `buildLinks` 读 `bundle.unit.related`(`KnowledgeGalaxyViewModel.ets:644-659`) |
| `unit.embedding` | queryAll 行 20 | **不渲染**,目前只用于语义检索(本项目未启用) |
| `unit.userId` / `unit.version` | queryAll 行 21-22 | 不渲染 |

**结论**: KnowledgeGalaxyViewModel **确实**依赖 `prerequisites` / `related` 画关系线。`queryAll()` 路径完整,**数据层不丢字段**。

### 6.4 "GalaxyViewModel 走 queryAll 却仍关系线空"的核心问题

数据层不缺字段(见 §6.3),问题在 §7 渲染逻辑与 §1.1 数据写入端。

---

## 7. 星系"关系线空"的具体复现路径

### 7.1 三条独立 bug 链(任意一条都足以让关系线空)

#### Bug 链 A — **写入端硬编码空(数据层,确定性)**

`agents/src/main/ets/agents/KnowledgeModel.ets:1222-1223`(`toKnowledgeUnit`):

```ts
// agents/src/main/ets/agents/KnowledgeModel.ets:1213-1228 (节选)
return {
  id: id,
  title: ...,
  content: ...,
  ...
  prerequisites: [],   // ← 这里
  related: [],         // ← 这里
  embedding: [],
  ...
}
```

`Dispatcher.ets:321-330` `copyRegeneratedUnit` 是 **passthrough**(`prerequisites: unit.prerequisites`),但因为源 unit 已经被 `toKnowledgeUnit` 设成 `[]`,**regenerate 路径也救不回来**。

**结论**: **所有从 AI 入库的新笔记,DB 里 `prerequisites` 和 `related` 都是 `[]` 字符串**。即便渲染完美,数据本身就是空的。

#### Bug 链 B — **渲染端按学科内 bundles 查找(逻辑层)**

```ts
// entry/src/main/ets/viewmodels/KnowledgeGalaxyViewModel.ets:493-515 (buildSystems)
while (index < subjectNames.length) {
  const orbits: ChapterOrbit[] = this.buildChapterOrbits(subjectBundles[index])
  const planets: PlanetNode[] = this.flattenPlanets(orbits)
  const links: GalaxyLink[] = this.buildLinks(subjectBundles[index])  // ← 注意:传 subjectBundles[index]
  ...
}
```

```ts
// entry/src/main/ets/viewmodels/KnowledgeGalaxyViewModel.ets:621-663 (buildLinks)
private buildLinks(bundles: UnitBundle[]): GalaxyLink[] {
  ...
  for (const bundle of bundles) {
    for (const prerequisiteId of bundle.unit.prerequisites) {
      const fromBundle: UnitBundle | null = this.findBundleById(bundles, prerequisiteId)  // ← 只在传入 bundles 中找
      if (fromBundle !== null && fromBundle.unit.id !== bundle.unit.id) {
        ...
        links.push(new GalaxyLink(...))
      }
    }
    for (const relatedId of bundle.unit.related) {
      const relatedBundle: UnitBundle | null = this.findBundleById(bundles, relatedId)  // ← 同上
      ...
    }
  }
  return links
}
```

`findBundleById`(`KnowledgeGalaxyViewModel.ets:665-676`)只在传入 bundles 数组内 for-loop 找匹配的 unit.id。

**结论**: 即便 A 链修复了(prerequisites/related 填了跨学科 ID),**跨学科关系仍找不到**;同学科内才找得到。

#### Bug 链 C — **渲染端聚焦门控(UI 层)**

```ts
// entry/src/main/ets/pages/Review/ReviewGraphView.ets:1220-1225 (SubjectGalaxyView.build)
ForEach(this.focusedLinks(),
  (link: GalaxyLink): void => {
    this.RelationLine(link)
  },
  (link: GalaxyLink): string => this.linkKey(link)
)
```

```ts
// entry/src/main/ets/pages/Review/ReviewGraphView.ets:1677-1688 (focusedLinks)
private focusedLinks(): GalaxyLink[] {
  const links: GalaxyLink[] = []
  if (this.system === null || this.focusedPlanetId.length === 0) {
    return links       // ← 没点行星就空
  }
  for (const link of this.system.links) {
    if (link.fromId === this.focusedPlanetId || link.toId === this.focusedPlanetId) {
      links.push(link)
    }
  }
  return links
}
```

```ts
// entry/src/main/ets/pages/Review/ReviewGraphView.ets:1304-1329 (RelationLine)
@Builder
RelationLine(link: GalaxyLink) {
  if (this.hasPlanet(link.fromId) && this.hasPlanet(link.toId)) {  // ← 还要确认两端都在 system 内
    Row()
      .width(this.linkDistance(link))
      ...
      .position({ x: this.linkLeftX(link), y: this.linkTopY(link) })
    Text(this.linkLabel(link))
      ...
  }
}
```

`hasPlanet`(`ReviewGraphView.ets:1694-1696`)遍历 system.orbits.planets 查找。

**结论**: 即便 B 链修复了(同学科关系能建出),用户必须 **先点(hover 也行,但 hover 用 `onHover`,只有触摸屏有问题)`focusedPlanetId`,`RelationLine` 才渲染**。即便 focused,如果两端行星不在 system.planets 内(同 bug B),`hasPlanet` 返回 false,`RelationLine` 内 if 不进,**仍然空**。

### 7.2 用户视角的 tight feedback loop 起点

**步骤(对应代码定位)**:

1. **启动 App**(HarmonyOS 启动)
2. **导航到 Review Tab**(Review TabContent,`Index.ets:58-62`)
3. **切到"图谱"子 Tab**(`ReviewPage.ets:151-153` `changeTab(1)`,触发 `ReviewGraphView` 渲染)
4. **`ReviewGraphView.aboutToAppear`**(`ReviewGraphView.ets:143-145`)调 `reloadGalaxy(false)`
5. **`KnowledgeGalaxyViewModel.load`**(`KnowledgeGalaxyViewModel.ets:215-233`)→ `loadPersistedUnits → queryAll`
6. **看 DB 数据**:用户拿一个 sqlite/rdb 客户端查 `knowledge_unit` 表,看 `prerequisites` 列 — 大概率全部是 `"[]"`。
   - **如果为空**:确认 Bug 链 A(`KnowledgeModel.ets:1222-1223`)
   - **如果有值**:进入 Bug 链 B / C 验证
7. **点学科进入星系**(`enterSubject` `ReviewGraphView.ets:189-198`,`selectedSubject` 被设置)
8. **点一个行星**(`selectGalaxyPlanet` `ReviewGraphView.ets:251-257` → `openPlanet` `ReviewGraphView.ets:230-242` 或 `hoverPlanet` `ReviewGraphView.ets:244-249`,**设 `focusedPlanetId`**)
9. **观察 RelationLine**:行星亮起 + 周围关系线出现 / 不出现
   - **如果出现**:B + C 链 OK,只剩 A 链
   - **如果不出现**:再确认 `subject.links.length`(通过 hilog 加断点),如果 `links.length === 0` 说明 B 链过滤掉了所有关系;如果 `links.length > 0` 但 UI 仍空,说明 C 链聚焦门控问题或 `hasPlanet` 失败
10. **没有 touch 屏幕的话**(`hoverPlanet` 不会触发):`focusedPlanetId` 永远为空,**C 链永远触发,关系线永远不显示** — 这是 touch-only 设备的常见 user-visible bug。

### 7.3 三链的相对严重度

| 链 | 类型 | 修复成本 | 用户可见度 | 严重度 |
|---|---|---|---|---|
| **A(写入端硬编码)** | 数据 bug | 高(改 KnowledgeModel + LLM 调用) | 100%(所有新笔记都受影响) | **最高** |
| **B(渲染按学科)** | 逻辑 bug | 中(改 buildLinks + buildSystems) | 部分用户(只跨学科受影响) | 中 |
| **C(focus 门控)** | 交互设计 | 低(改 SubjectGalaxyView 渲染循环) | 100%(无 hover 设备都受影响) | **高** |

**注意**: 即便 C 修了,**没有数据(A)** 关系线还是空。所以 **A 是 root cause,其他两个是放大器**。

---

## 8. 阻塞 / 漏洞高发点清单

> 排序按"症状报告相关性 × 排查难度 × 修复成本"。

### 8.1 高优先

| # | 位置 | 为什么是漏洞 | 证据(file:line) |
|---|---|---|---|
| 1 | **`KnowledgeModel.toKnowledgeUnit` 硬编码 prerequisites/related 为空** | **root cause of"关系线空"**。所有 AI 入库的新笔记的 KG 关联字段是 `[]`,即便渲染逻辑修好,关系线也空。 | `agents/src/main/ets/agents/KnowledgeModel.ets:1222-1223` |
| 2 | **`KnowledgeGalaxyViewModel` 绕过 `UiDataCacheService`** | 写入时 Home/Notes 走 cache 失效,Galaxy 走 `queryAll`,**双跑 + 不同字段**;Home 改 `notesVersion` 后 Galaxy 通过 `@Watch` 触发重拉,但 cache 中 notesSnapshot 没失效(`KnowledgeGalaxyViewModel.deleteNote` 没调 `UiDataCacheService.invalidateNotesSnapshots`)。 | `entry/src/main/ets/viewmodels/KnowledgeGalaxyViewModel.ets:235-243, 262-277` |
| 3 | **`SubjectGalaxyView.RelationLine` focus-gated** | 用户必须主动点行星(`focusedPlanetId`),关系线才渲染;touch 设备无 hover,用户难以发现。 | `entry/src/main/ets/pages/Review/ReviewGraphView.ets:1220-1225, 1304-1329, 1677-1688` |
| 4 | **`buildLinks` 按学科内 bundles 查找** | 跨学科关系(同一 note 引其他学科 ID)永远 `findBundleById` 返回 null,链接被静默丢。 | `entry/src/main/ets/viewmodels/KnowledgeGalaxyViewModel.ets:498, 627-659, 665-676` |
| 5 | **3 个 ViewModel 错误处理全是 `console.warn` + 空状态** | DB init 失败 / DB query 失败时,用户看到空状态 + 至多 1 个 toast,但 toast 一闪而过。**没有任何持久的错误指示**(无错误页面 / 无 banner)。 | `entry/src/main/ets/viewmodels/HomeViewModel.ets:34-41, 43-53, 55-67`;`entry/src/main/ets/viewmodels/NotesViewModel.ets:34-57, 59-69, 71-83`;`entry/src/main/ets/viewmodels/KnowledgeGalaxyViewModel.ets:215-243, 245-260, 262-277` |
| 6 | **`SubjectDetailPage.ensureSubject` 失败时清空 subject** | `vm.subjectGroups` 为空(因 DB 失败)时 `this.subject = ""`(`SubjectDetailPage.ets:72-82`),导致 UI 渲染时 `subjectNotes()` 返回空,`SubjectHeader` 显示空标题,`TypeTabRow` 显示 "全部" — **用户不知道学科不存在还是加载失败**。 | `entry/src/main/ets/pages/Notes/SubjectDetailPage.ets:51-70, 72-82` |
| 7 | **`NoteDetailOverlay.effectiveUnit()` 永久 LoadingState** | `selectedUnit === null` + `note.title` / `note.body` 都为空时,`canRenderReadOnlyDetail()` 返回 false,触发 `LoadingState()`(`NoteDetailOverlay.ets:213-237`),**但没人触发重试**;`HomeViewModel.loadNote` 失败后只 console.warn,UI 永久转圈。 | `entry/src/main/ets/overlays/NoteDetailOverlay/NoteDetailOverlay.ets:146-154, 308-313`;`entry/src/main/ets/viewmodels/HomeViewModel.ets:43-53` |
| 8 | **错误 toast i18n 混用(中英)** | `HomePage.ets:60` 英文 vs `NotesPage.ets:54` 中文,`SubjectDetailPage.ets:137, 139` 英文 vs 其他中文 — **早期版本未统一**,体感差。 | `entry/src/main/ets/pages/Home/HomePage.ets:60`;`entry/src/main/ets/pages/Notes/SubjectDetailPage.ets:137-139` |

### 8.2 中优先

| # | 位置 | 为什么是漏洞 | 证据(file:line) |
|---|---|---|---|
| 9 | **`HomeViewModel.loadNotes` 失败 toast 但继续渲染空状态** | toast "Failed to load notes" + `HomePage` 继续渲染 `HeroBanner` + 空 `HomeRecentNotes`,用户看到"全新"空 App,**不知道是空还是故障**。 | `entry/src/main/ets/pages/Home/HomePage.ets:50-67` |
| 10 | **`KnowledgeGalaxyViewModel.loadNote` 静默吞错** | 用户在星系里点行星打开详情,`loadNote` 失败时 `selectedUnit = null` 但 UI 继续用 `planet.unit` 做 fallback(`ReviewGraphView.ets:230-242`),**fallback 内容可能与 DB 不一致**(版本冲突检测不到)。 | `entry/src/main/ets/pages/Review/ReviewGraphView.ets:230-242`;`entry/src/main/ets/viewmodels/KnowledgeGalaxyViewModel.ets:245-260` |
| 11 | **`KnowledgeGalaxyViewModel.deleteNote` 没失效 cache** | 删除后只 `AppStorage.setOrCreate('notesVersion', v+1)`(`KnowledgeGalaxyViewModel.ets:291-292`),但 `UiDataCacheService.notesSnapshot` / `detailEntries` 没失效 — **HomePage / NotesPage 因 notesVersion 触发 reload 时,cache 已被其他路径失效**;若用户没切 Tab 直接回星系,`queryAll` 拿到的数据已最新,但 cache 是脏的。**实际触发概率低**,但 latent。 | `entry/src/main/ets/viewmodels/KnowledgeGalaxyViewModel.ets:262-277` |
| 12 | **`PrefabSettings = false` 关闭 preview 数据** | `ENABLE_GALAXY_PREVIEW_UNITS: boolean = false`(`KnowledgeGalaxyViewModel.ets:13`)。**preview 单元(11 条带完整 prerequisite/related 关系的虚拟数据)永不显示** — 关系线渲染逻辑在 preview 数据下能验证工作正常,关闭后无法 demo。 | `entry/src/main/ets/viewmodels/KnowledgeGalaxyViewModel.ets:13, 287-298, 325-466` |
| 13 | **`SubjectDetailPage` 用 `version + subject` 作 reloadKey,但 subject 变化时 key 不重置** | 用户从一个学科切到另一个学科(`router.pushUrl` 的 params),`reloadNotes` 在 `aboutToAppear` 时 subject 已经改变,`loadedReloadKey = "0\|OldSubject"`,新 key `"0\|NewSubject"` 没匹配,会触发新 load — **正确行为**;但 `onPageShow` 仍会触发,如果用户在两学科间来回切,**每次都重拉**。 | `entry/src/main/ets/pages/Notes/SubjectDetailPage.ets:29-70` |
| 14 | **`StartRotation` 定时器与 `animateTo` 状态写入竞态** | `startRotation` 每 800ms 写 `orbitOffset`(`ReviewGraphView.ets:218-221`);同时 `enterSubject` / `leaveSubject` / `zoomIn` 等用 `animateTo` 包裹写 `orbitOffset`(`ReviewGraphView.ets:189-198, 200-212, 308-330`)。在 ArkUI 中,**动画期间对同一 `@State` 的赋值会被动画驱动覆盖或争抢**。 | `entry/src/main/ets/pages/Review/ReviewGraphView.ets:189-228, 308-330` |

### 8.3 低优先

| # | 位置 | 为什么是漏洞 | 证据(file:line) |
|---|---|---|---|
| 15 | **`NotesViewModel.loadNote` 失败后 `selectedUnit = null`,UI 仍渲染 NoteDetailOverlay** | `SubjectDetailPage.ets:111-119` 失败时 `this.selectedUnit = unit`(null),但 `NoteDetailOverlay` 仍打开,显示 `LoadingState`(`NoteDetailOverlay.ets:213-237`)。 | `entry/src/main/ets/pages/Notes/SubjectDetailPage.ets:111-119` |
| 16 | **`UiDataCacheService.notesSnapshot.units` 是 `KnowledgeUnit[]`,但 `units` 字段(`HomeViewModel.ets:13`)也是同类型 — 在 list 页面没用** | HomePage / NotesPage 只用 `notes`(NoteItem),`units` 仅 `NoteDetailOverlay.units` 用作列表参考。但 `setNotesSnapshot` 总同时算两份(`UiDataCacheService.ets:144-149`)。冗余但不影响功能。 | `entry/src/main/ets/services/UiDataCacheService.ets:144-149` |
| 17 | **`ReviewGraphView.linkKey` 在 type + fromId + toId 上拼字符串,key 长度无限制** | 如果 uuid 长度过长(36 字符 × 2 + 13 字符 type prefix ≈ 85 字符),`ForEach` key 解析开销低,但生成哈希可能重复 — **极小概率**。 | `entry/src/main/ets/pages/Review/ReviewGraphView.ets:1690-1692` |
| 18 | **`NotesViewModel.deleteNote` / `HomeViewModel.deleteNote` 在 cache 失效后,`UiDataCacheService.invalidateNote` 调 `invalidateNotesSnapshots` 但 detailEntries 留其他 entry** | 删除笔记后,**其他笔记的 LRU entry 没被删**,只失效对应 id(`UiDataCacheService.ets:201-204, 379-387`)— **正确行为**;但如果用户频繁切换 subject,LRU 的 8 条可能不够覆盖活跃笔记,导致冷笔记每次都重查 DB。 | `entry/src/main/ets/services/UiDataCacheService.ets:201-204` |

---

## 9. 留待 `/diagnosing-bugs` 处理的 tight feedback loop 起点

> 每条针对一个 bug,**起点 → 终点 → 期望观察**三步。

### Loop #1 — "关系线空"的根因定位

- **起点**: 启动 App,跑一次拍照入库(产生 1 条真实笔记)
- **终点**: 用 hilog 或 sqlite client 查 `knowledge_unit` 表的 `prerequisites` 列
- **预期**:
  - 若值是 `"[]"` → 确认 Bug 链 A(`KnowledgeModel.ets:1222-1223`),fix 在 agents 模块
  - 若值是 `["some_id"]` → 进入 Loop #2

### Loop #2 — 跨学科关系是否被 buildLinks 静默丢

- **起点**: 手动改一条记录的 `prerequisites` 为 `[另一学科的某条 id]`,重启 App
- **终点**: hilog 注入 `console.warn` 到 `KnowledgeGalaxyViewModel.ets:627`(`for (const prerequisiteId of bundle.unit.prerequisites) { console.warn("link scan", bundle.unit.id, "->", prerequisiteId, "found:", found !== null) }`),打开星系进入对应学科
- **预期**: 看到日志里 `found: false`,确认 Bug 链 B。

### Loop #3 — focus-gated 渲染的真机验证

- **起点**: Deploy 到真机(触摸设备),打开星系,进入任一学科
- **终点**: 不点行星,直接用单步验证 `ReviewGraphView.ets:1679` `if (this.focusedPlanetId.length === 0)` 为 true
- **预期**: 验证 "点行星前无关系线" 是设计还是 bug,与产品对齐。

### Loop #4 — DB init 又一次 toast

- **起点**: 模拟 DB init 失败(例如把 `DatabaseHelper` 的 storeName 改坏,或在 init 前 throw)
- **终点**: 启动 App,点 Home Tab → Notes Tab → Review Tab 三次,每次等 1.5s
- **预期**: 看到 3 次 toast("Failed to load notes" / "笔记加载失败" / "知识星系加载失败"),**每次重试 init**(因为 cache key 不更新)。
- **确认**: HomeViewModel.ets:36 / NotesViewModel.ets:50 / KnowledgeGalaxyViewModel.ets:237 三处分别打 console.warn。

### Loop #5 — `NoteDetailOverlay` 永久 LoadingState

- **起点**: 在 `HomeViewModel.loadNote` 入口处加 throw,启动 App,点任意笔记
- **终点**: 观察 NoteDetailOverlay 是否显示 LoadingState 超过 5s
- **预期**: 永久转圈,无重试,无错误反馈。

### Loop #6 — SubjectDetailPage 学科清空

- **起点**: 同 Loop #4(DB init 失败)→ router 切到 `pages/Notes/SubjectDetailPage`(push 任意 subject 名)
- **终点**: 观察 `SubjectHeader.subject` 字段
- **预期**: 显示空字符串(因为 `SubjectDetailPage.ets:73-76` `ensureSubject` 在 `vm.subjectGroups.length === 0` 时 `this.subject = ""`)。

---

## 10. 未确认 / 读不懂的地方

1. **`KnowledgeGalaxyViewModel.linkKey` 在不同 subject 共享的 `system.links`**: 是否有可能 system.links 跨 subject 共享?目前看 `system.links = this.buildLinks(subjectBundles[index])`(`KnowledgeGalaxyViewModel.ets:498`),**不会跨 subject**。但 `SubjectGalaxyView` 内 `this.system.links`(`ReviewGraphView.ets:1220`)是从 active system 取,所以同星系内不会跨学科。**确认安全**。
2. **`NoteDetailOverlay.units` 实际怎么用**: 列表在 `NoteDetailOverlay.ets:41` `@Prop units: KnowledgeUnit[] = []`,在 `NoteDetailMeta` 和 `NoteDetailBody` 引用,但本次未读这两个文件,**未确认 units 在详情里做什么**。
3. **`HomeCollapsedReview` 是否复用 ReviewGraphView 渲染**: 看名字像,但 `HomePage.ets:133-148` 显示是独立组件,**未读源码**;与本次范围(呈现段)略相关但优先级低。
4. **`isWrongNote` 过滤掉错题**: `KnowledgeGalaxyViewModel.ets:476-478`,`note.type === "错题"` 的笔记不进 system,**也不会参与关系线** — 与 A 链共同作用,加大"关系线空"概率。
5. **`buildSystems.applyUniverseLayout` 与 `SubjectUniverseView.subjectWorldCenterX/Y` 的渲染顺序**: system.x / system.y 在 `applyUniverseLayout`(`KnowledgeGalaxyViewModel.ets:695-729`)里设置,但 `SubjectUniverseView` 重新计算 `subjectWorldCenterX/Y`(`ReviewGraphView.ets:1023-1046`),**有可能 layout 被覆盖**(但代码看上去是兼容的)。
6. **`HomePage.onPageShow` 与 `aboutToAppear` 竞态**: `aboutToAppear` 立即调 `reloadHome`(`HomePage.ets:38-40`),`onPageShow` 也调(`HomePage.ets:42-44`),`loadedNotesVersion` 去重保护(`HomePage.ets:50-67`)— 但 `loadedNotesVersion` 是 `-1` 初始,两个调用并发触发,后者等前者。**实际安全但并发 API 不优雅**。
7. **`UnitBundle.unit` 在 `withPreviewUnits` 后引用的是原始 unit 还是 copy**: `withPreviewUnits` 用 `units.slice(0)` + push(`KnowledgeGalaxyViewModel.ets:291-296`),**引用原对象**;如果原对象被外部 mutate,会影响 buildSystems。但 ViewModel 内部 mutate 都在 load 阶段,外部不触发,**确认安全**。
8. **`SubjectGalaxyView.focusedLinks` 与 `RelationLine.hasPlanet` 双重过滤**: 当 link.fromId 或 link.toId 不在 system.planets 内时,RelationLine 内 `hasPlanet` 返回 false,Row 不渲染(`ReviewGraphView.ets:1304-1329`)。**用户感知**:点了行星但看不到关系线。原因可能是 buildLinks 用了 fromChapter/toChapter 但 hasPlanet 只在 orbits.planets 内找 — **逻辑正常**,但 buildLinks 产出的 link.fromId 如果来自 preview unit(`galaxy_preview_xxx`),而 preview 关闭(`ENABLE_GALAXY_PREVIEW_UNITS = false`),`hasPlanet` 找不到,**关系线空**。

---

## 11. 调研覆盖度自检

| 层 | 已读文件 | 备注 |
|---|---|---|
| 3 Page | `NotesPage.ets`、`NotesList.ets`、`SubjectDetailPage.ets`、`SubjectNoteList.ets`、`SubjectGrid.ets`、`SubjectCard.ets`、`NotesSummaryPanel.ets`、`NotesEmptyState.ets`、`TypeTabRow.ets`、`ReviewGraphView.ets`(全 1880 行)、`ReviewPage.ets`、`Index.ets` | `NoteDetailOverlay.ets` 全 657 行(详情浮层);`HomePage.ets` 全 216 行 |
| 3 ViewModel | `HomeViewModel.ets` 全 103 行、`NotesViewModel.ets` 全 110 行、`KnowledgeGalaxyViewModel.ets` 全 790 行 | |
| 1 缓存服务 | `UiDataCacheService.ets` 全 512 行 | |
| 1 DAO | `NoteDao.ets` 全 639 行 | |
| 1 Mapper | `NoteItemMapper.ets` 全 134 行 | |
| 1 Common | `CommonTypes.ets` 全 145 行 | |
| 写入端抽样 | `KnowledgeModel.ets`(grep 1222-1223)、`Dispatcher.ets:315-330` | 仅查 `prerequisites/related` 写入路径,未读其他 |

---

**调研完成。** 文件:`docs/research/presentation-deep-dive-2026-09-16.md`
