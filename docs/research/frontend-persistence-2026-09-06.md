# 前端状态序列化与持久化摸底 — 2026-09-06

> **Date:** 2026-09-06 晚
> **Scope:** MindTrace entry 状态持久化 4 层 (AppStorage / preferences / RDB / in-memory) 的覆盖面与生命周期
> **方法**: grep `AppStorage.*setOrCreate/get/set` / `preferences.getPreferences` / `DatabaseHelper.getStore` / `UiDataCacheService`, 全机提取
> **配套**: [`frontend-flow-walkthrough-2026-09-06.md`](./frontend-flow-walkthrough-2026-09-06.md) §C4 候选 · 本档聚焦于"什么状态存在哪里、生命周期谁管"

---

**TL;DR:** 4 层持久化面**边界还算清晰**, 但有 3 处问题: ① AppStorage 当**全局事件总线**用 (`notesVersion` 6 文件手工 bump/watch) — 错位, 应改用响应式; ② in-memory 的 UiDataCacheService 静态缓存 + `invalidateNotesSnapshots` 与 AppStorage notesVersion 双轨制, 关系不清 (谁触发谁?); ③ preferences 3 个 store (chat_history / kit_reminder_map / profile_auth) 各自命名但**没有 store 名中心登记**, 后续新增容易撞名。

---

## 1. 4 层持久化全景

### 1.1 AppStorage (全局 in-memory, 进程生命周期)
| 键 | 类型 | 写者 | 读者 | 备注 |
|---|---|---|---|---|
| `notesVersion` | number | 6 文件手工 `setOrCreate(v+1)` | 6 文件手工 `get` in onPageShow | ⚠ C4 候选: 当事件总线用 |
| `reminderFacade` | ReminderFacadeImpl | EntryAbility.onCreate (组合根) | ReminderFacadeImpl.getReminderFacade() | ✓ 单点注入 |
| `statusBarHeight` | number | EntryAbility.onCreate | 6 页面 `@StorageProp` + 2 浮层 `@StorageProp` | ✓ 单点种, 6 页面下传 @Prop 是问题 |

### 1.2 preferences (KV 持久化, 跨进程)
| store 名 | 位置 | 用途 | 备注 |
|---|---|---|---|
| `kit_reminder_map` (隐式常量) | `entry/kit/ReminderFacadeImpl.ets:53` | unitId → reminderId 映射 | ⚠ store 名是变量, 不在中心登记 |
| `chat_history` (字符串字面量) | `overlays/AgentFloatWindow/chat/ChatSession.ets:35` | 多会话对话历史 | ⚠ store 名是字面量, 同上 |
| `profile_auth` (字符串字面量) | `viewmodels/ProfileAuthViewModel.ets:98` | mock 登录态 | ⚠ 同上 |

**问题**: 3 个 store 名散落各文件, 中心无登记 (建议: `common/.../storage/StorageNames.ets`)。

### 1.3 RDB (关系数据库, MindTrace.db, schema v4)
| 表 | 用途 | DAOs |
|---|---|---|
| knowledge_unit (24 列, SM-2 字段) | 笔记 | NoteDao |
| study_plan | 学习计划 | StudyPlanDao |
| chat_message | 聊天消息 (与 preferences chat_history 重叠?) | ChatMessageDao |
| agent_memory | 智能体记忆 | AgentMemoryDao |

**重叠嫌疑**: `chat_message` (RDB) 与 `chat_history` (preferences) 两套聊天持久化并存 — 职责不清, 哪条管什么?

### 1.4 in-memory (UiDataCacheService, 进程生命周期, 静态缓存)
- `detailEntries: DetailCacheEntry[]` (笔记详情渲染缓存, LRU 淘汰)
- `invalidateNotesSnapshots()` (清笔记快照, 触发点: AiService.buildNoteDao 后)
- `PreloadQueue` (预加载队列)

**双轨制嫌疑**: `UiDataCacheService.invalidateNotesSnapshots()` (in-memory) 与 `AppStorage.setOrCreate('notesVersion', v+1)` (全局) 在 AiService.buildNoteDao 同一行调用 — 谁触发谁刷新? 看了三处才确认两个都触发, 关系不清。

---

## 2. 状态归属与生命周期

| 状态类 | 持久化层 | 生命周期 | 触发回收 |
|---|---|---|---|
| 笔记数据 | RDB (knowledge_unit) | 永久 | 显式 delete |
| 对话历史 | preferences (chat_history) | 永久 | 显式清空 |
| 智能体记忆 | RDB (agent_memory) + preferences(?) | 永久 | 显式清空 |
| 学习计划 | RDB (study_plan) | 永久 | 显式 delete |
| 提醒映射 | preferences (kit_reminder_map) | 永久 | 取消提醒时删 |
| Mock 登录 | preferences (profile_auth) | 永久 | mock 重置 |
| 状态栏高度 | AppStorage | 进程 | 进程退出 |
| ReminderFacade | AppStorage | 进程 | 进程退出 |
| 笔记版本号 | AppStorage | 进程 | 进程退出 |
| 笔记列表快照 | UiDataCacheService | 进程 (LRU 淘汰) | invalidateNotesSnapshots / LRU |
| 笔记详情渲染 | UiDataCacheService | 进程 (LRU) | trimDetailCache |
| 当前会话列表 | AgentFloatWindow @State | 进程 (in-memory) | 浮窗卸载 (190ms 后) |
| AI 输入草稿 | AgentFloatWindow @State inputText | 进程 | 浮窗卸载即丢 ⚠ |

**⚠ 发现**: AI 输入草稿 (inputText) 关闭浮窗后即丢 — 用户"输了半句话误触关闭"时无任何恢复路径, P3.1 已记。

---

## 3. 评级

| 层 | 评 | 备注 |
|---|---|---|
| 持久化分层清晰度 | △ | 4 层各有职责, 但聊天持久化两套并存 |
| 跨层一致性 | ✗ | in-memory 失效 + AppStorage bump 双轨制, 关系不清 |
| 状态栏高度 (AppStorage) | △ | 单点种 OK, 6 页面下传 @Prop 是 C4 |
| ReminderFacade (AppStorage) | ✓ | 组合根单点注入 |
| notesVersion (AppStorage) | ✗ | 当事件总线用, 应改 @StorageProp 响应式 |
| preferences store 名 | ✗ | 散落无中心, 撞名风险 |
| in-memory 缓存 | ✓ | UiDataCacheService 单例 + LRU 清晰 |
| 输入草稿持久化 | ✗ | inputText 关闭即丢, 用户体验差 |

---

## 4. 应有但缺的结构

### 4.1 StorageNames 中心登记 (建议)
```typescript
// common/.../storage/StorageNames.ets
export const PREF_REMINDER_MAP = 'kit_reminder_map';
export const PREF_CHAT_HISTORY = 'chat_history';
export const PREF_PROFILE_AUTH = 'profile_auth';
export const APP_KEY_NOTES_VERSION = 'notesVersion';
export const APP_KEY_REMINDER_FACADE = 'reminderFacade';
export const APP_KEY_STATUS_BAR_HEIGHT = 'statusBarHeight';
```

### 4.2 C4 候选 (statusBarHeight + notesVersion)
详见 [`frontend-healthcheck-plan-2026-09-06.md`](./frontend-healthcheck-plan-2026-09-06.md) §1 C4 — 已升级到 Phase A 强候选 (路径走查证据)。

### 4.3 输入草稿持久化 (新候选建议 C8)
AgentFloatWindow.inputText 在 190ms 卸载后即丢 — 建议持久化到 preferences 的 `chat_draft:<sid>` 键, 重新打开浮窗时自动恢复。可作为后续单独候选。

### 4.4 聊天持久化两套并存 (新候选建议 C9)
RDB chat_message + preferences chat_history 各自管什么? 待核实职责分工, 若重叠 → 合并; 若分工 → 写 ADR 明确边界。

---

## 5. 与现有契约的冲突

- **不冲突**: 与 spec 012 / 014 / CONTEXT.md 无明确接口
- **机会**: C4 (AppStorage 响应式) 与 frontend-healthcheck-plan §1 C4 是同一项, 优先级 Phase A 强候选
- **机会**: C8 输入草稿是新发现, 可独立 PR

---

## 6. 待补充资料

§5 第 6-10 项不变, 新增:
11. **preferences store 名列表**: 我 grep 的 3 个是否完整 (含未引用的 store 名)
12. **RDB chat_message 表实际使用**: 是否还在写, 还是已被 preferences 取代 — 决定 C9 是否需要治理
13. **UiDataCacheService 与 AppStorage notesVersion 调用先后顺序**: 决定两者谁触发谁刷新

---

## Last updated

2026-09-06 晚
