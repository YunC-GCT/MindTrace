# 清空对话历史实施设计

> **Status**: draft (2026-10-24)
> **Related**: (implicit) [spec 021 — Chat 流式增量 Markdown/LaTeX 渲染与持久化降载](../specs/021-chat-streaming-incremental-rendering.md) · [spec 018 — Agent workflow architecture](../specs/018-agent-workflow-architecture.md)
> **Code**: `entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets` · `entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatSession.ets` · `entry/src/main/ets/services/ChatHistoryPersistence.ets` · `entry/src/main/ets/services/ChatContextProjectionService.ets` · `entry/src/main/ets/services/AgentMemoryService.ets` · `entry/src/main/ets/services/SessionDeletionCoordinator.ets` · `common/src/main/ets/DatabaseHelper.ets`
> **Verified by**: 只读源码追踪 + 用户提供的真机 DB/进程/偏好事实；未修改源码、未提交、未运行 hvigor 构建

本文是给 DSH 的实施设计。当前仓库没有清空全局对话历史的生产入口；本文不把设计写成已实现功能。

## 结论先行

题设列出的设备 DB、force-stop、DB 家族删除、Preferences 排查、源码 grep 和第 38 条设备现象均作为既定事实采信；本文不把这些事实重新当作待验证步骤。源码追踪只负责说明当前 checkout 能证明的写入链，并对无法由当前代码解释的细节明确标记为“未定位”。

37 条消息的**内容与稳定 ID 的回填路径已定位**：浮窗启动 → 加载应用私有 `filesDir/chat-history/sessions.json` → 将快照映射为上下文投影 → `AgentMemoryService.saveMessage` → `ChatMessageDao.upsert` 写回 `chat_message`。`force-stop` 只结束进程，不删除应用私有快照，所以重启时该路径再次执行。

当前源码还不能解释“删除前后 37 行的 `created_at` 完全相同”。投影写入的 `createdAt` 是 `Date.now()`；因此精确时间戳的来源仍是**未定位**，不能把它归因给某个 fixture 或缓存。第 38 条开场白也没有在当前 `.ets` 源码中找到对应的插入语句；`ConversationWorkflow.ets:1218` 只是 fallback 文本识别条件。实施前应把安装包版本、快照内容和启动日志对齐，否则可能在旧编译产物上修复错误的路径。

推荐把“清空全部对话”放在 AI 浮窗的会话历史面板底部；现有会话长按删除继续表示“删除单个会话”。清空操作由一个 entry 服务协调：先建立持久化 clear epoch 和 pending 状态，阻断旧快照投影，再以 RDB 事务删除聊天及会话派生数据，最后原子提交空快照。清空成功后，知识笔记、复习数据、知识图谱边和学习画像保持不变。

## A. 回填来源定位

### A.1 已定位的启动调用链

| 顺序 | 文件与行 | 代码事实 | 对回填的作用 |
|---|---|---|---|
| 1 | `entry/src/main/ets/pages/Index.ets:95-101` | 生产根页面创建 `AgentFloatWindow`；benchmark 分支才传 `benchmarkFixtureMode` | 正常打开浮窗会走真实历史加载，性能 fixture 不应进入该路径 |
| 2 | `entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets:137-144` | `aboutToAppear()` 在非 benchmark 模式调用 `loadHistory()` | 浮窗首次出现就是回填触发时机 |
| 3 | `entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets:193-195` | 读取 `ChatFilesDirSeam` 并把 `filesDir` 交给 `ChatSessionManager` | 解析应用私有快照位置；不是 DB 路径 |
| 4 | `entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatSession.ets:59-67` | `init()` 构造 `ChatHistoryPersistence`，然后 `persistence.load()` | 取得历史会话并缓存到 `ChatSessionManager.latestSessions` |
| 5 | `entry/src/main/ets/services/ChatHistoryPersistence.ets:899-929` | 只要快照文件存在，优先读取并解码文件；不会先读 RDB | `filesDir/chat-history/sessions.json` 是当前生产历史真源 |
| 6 | `entry/src/main/ets/services/ChatHistoryPersistence.ets:938-964` | 只有快照不存在时才读 `chat_history` Preferences 的旧 `sessions` 字符串并迁移 | Preferences 是迁移兜底，不是已有快照时的首选来源 |
| 7 | `entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets:381-388` | 过滤旧 `s1` 后调用 `deletionCoordinator.replay()`，再调用 `ChatContextProjectionService.reconcile(...)` | 启动时把快照消息重新投影到 RDB |
| 8 | `entry/src/main/ets/services/ConversationSnapshotMapper.ets:36-52` | 每条消息映射为 `ConversationMessageSnapshot`；`messageKey` 优先沿用快照值 | 解释了观测到的 `runId:assistant:id` 形式稳定 ID |
| 9 | `entry/src/main/ets/services/ChatContextProjectionService.ets:41-71` | 遍历所有会话；跳过空正文/不可作上下文的消息；其余调用 `memory.saveMessage` | 37 条已完成消息会逐条写回 |
| 10 | `entry/src/main/ets/services/AgentMemoryService.ets:42-61` | 以 `request.messageKey` 同时作为 `id` 和 `messageKey`，创建 `ChatMessageRecord` | 生成与快照一致的主键；当前 `createdAt` 取 `Date.now()` |
| 11 | `entry/src/main/ets/database/ChatMessageDao.ets:12-29` | `insert('chat_message', ..., ON_CONFLICT_REPLACE)` | 对已删除/不存在的行重新插入；对已有行执行幂等替换 |

因此，启动时的实际链路可以表示为：

```text
AgentFloatWindow.aboutToAppear
  -> loadHistory
  -> ChatSessionManager.init
  -> ChatHistoryPersistence.load
  -> filesDir/chat-history/sessions.json
  -> ChatContextProjectionService.reconcile
  -> AgentMemoryService.saveMessage
  -> ChatMessageDao.upsert(ON_CONFLICT_REPLACE)
  -> chat_message
```

### A.2 为什么能绕过 force-stop 后的删除

`force-stop` 只使应用进程退出；它没有清理 `filesDir` 下的会话快照，也没有写入“用户已清空”的持久化意图。下一次启动时，`ChatHistoryPersistence.load()` 仍会把旧快照解码成 37 条 `ChatMsg`，而 `reconcile()` 不检查用户是否曾经主动删除过这些消息。即使外部把 DB 主文件、`-wal`、`-shm`、`.dwr` 和 `.compare` 一起删掉，应用重建 RDB 后仍会执行同一投影，因此数据库删除本身不会阻止回填。

这一机制也解释了“DB 主文件 mtime 没变却多回行”的现象：RDB 行是应用启动后的投影写入，不是外部删除失败。`ON_CONFLICT_REPLACE` 使投影可重复执行；当前实现没有 clear epoch、tombstone 或旧快照失效标记。

### A.3 已排除或不是本次 37 行来源的路径

| 怀疑点 | 源码/事实证据 | 结论 |
|---|---|---|
| `EntryAbility.onCreate` 直接 seeding 聊天 | `entry/src/main/ets/entryability/EntryAbility.ets:58-63` 只初始化 `DatabaseHelper` 并刷新卡片 | 不写 `chat_message`；它只是让 DB 可用 |
| `CardSnapshotStore` 反灌聊天 | `common/src/main/ets/kit/CardSnapshotStore.ets:17-55` 只保存/读取 5 个 number；`CardSnapshotService.ets:24-49` 只统计 `knowledge_unit` | 不含聊天正文，也没有 chat 表调用 |
| `GalaxyPreviewSeedService` 演示 fixture | `entry/src/main/ets/services/GalaxyPreviewSeedService.ets:73-97` 只通过 `NoteDao`/`KnowledgeRelationDao` 创建 KnowledgeUnit 和关系；开关名为 `ENABLE_GALAXY_PREVIEW_UNITS` | 会影响知识笔记/图谱，不会写 `chat_message` |
| `AgentFloatWindow` benchmark fixture | `AgentFloatWindow.ets:137-144` 在 `benchmarkFixtureMode` 下只把 prop 复制到内存；`aboutToDisappear` 也跳过 flush | 仅渲染基准，不是正常生产回填 |
| AppStorage 快照 | `EntryAbility` 只放 benchmark、facade、状态栏和 `ChatFilesDirSeam`；`ChatFilesDirSeam.ets:89-99` 只存路径 seam | 没有聊天正文快照；进程退出后 AppStorage 也不可靠 |
| `chat_history` Preferences 直接回填 | `ChatHistoryPersistence.ets:938-964` 仅在私有快照不存在时读取；题设已排除聊天文本 Preferences | 当前设备更可能是私有文件快照；旧迁移兜底仍需在实现中加 guard |
| `ConversationWorkflow` 开场白 seeding | `ConversationWorkflow.ets:1213-1224` 的 `matchesFallbackShape()` 只检查回复文本是否包含“我是 MindTrace AI 数学助手”或“笔记检索：”；没有 DAO、`saveMessage` 或 `addAiMessage` 调用 | 不能把该行写成启动插入点 |

### A.4 两个尚未闭合的证据点

1. **`created_at` 完全相同：未定位。** `AgentMemoryService.ets:48-60` 明确用当前 `Date.now()` 组装记录，`ConversationSnapshotMapper` 也没有把快照的 `ts` 映射到 `createdAt`。所以这条源码链解释了稳定 ID、正文和行数，却解释不了“删除前后时间戳逐行相同”。实现前应在同一 APK/同一源码版本上：导出快照 JSON 的 `messageKey`/`ts`、记录 clear 前后 `created_at`、并采集 `ChatProjection`/`ChatMessageDao` 日志。若时间戳仍相同，应继续查运行中的旧 HAP/HSP 或 RDB 恢复层；本文不猜测。
2. **第 38 条开场白：源码级写入点未定位。** 题设把它归因到 `ConversationWorkflow.ets:1218`，但当前文件该行是 `indexOf` 判断，且没有“历史里没有开场白就补一条”的分支。题设运行时现象应保留为验收事实；当前仓库源码不能证明其插入者。清空设计必须禁止所有快照/fixture/ensure 路径在 clear 后新增系统消息，并把“重启后不出现第 38 条”作为真机验收项。

这两个未定位项不阻塞设计本身：clear epoch 必须在所有历史读取、投影和未来的开场白 ensure 之前生效；目标 APK 的实际写入者由 DSH 在实现阶段按日志和版本对齐闭合，不能用当前 `indexOf` 判断冒充写入点。

## B. 清空功能设计

### B.1 入口和交互

**入口选定：AI 浮窗 → 会话历史面板 → 底部“清空全部对话”。** 现有面板由 `SessionsPanel.ets:27-53` 渲染，现有单会话删除由 `SessionChip` 长按 → `AgentFloatWindow.onRequestSessionDelete()`（`AgentFloatWindow.ets:808-839`）→ `SessionsPanelController`（`SessionsPanelController.ets:21-47`）确认。全局清空与单会话删除放在同一面板，用户能看到作用域，也不受“我的”页登录状态影响。

交互建议：

1. 点击 HistoryChip 打开会话面板；面板底部显示危险色、带无障碍文本的 `清空全部对话` 行。没有任何消息时禁用。
2. 点击后弹出原生二次确认。建议文案：
   - 标题：`清空全部对话？`
   - 正文：`将删除所有会话的聊天消息、聊天上下文和未完成的整理草稿，且无法恢复。已保存的知识笔记、复习记录和学习画像不会受影响。`
   - 按钮：`取消`、`清空`（危险色）。
3. 确认后立即禁用发送、新建会话和重复点击；显示短暂进度态。只有服务返回 `completed` 才清空 UI、关闭面板并显示 `对话历史已清空`。
4. 失败显示 `清空失败，历史未完成清理，请稍后重试`，保留原会话视图（或标为恢复中），不要显示成功 toast。当前 `AgentMessageList.ets:87-96` 已有空状态组件，成功后把消息数组置空即可显示空状态。
5. 单会话长按继续走原有“删除会话”确认；全局清空不复用单会话 tombstone，避免只删了 active session 而旧 session 仍回灌。

### B.2 服务边界和数据处理

新增 entry 服务/协调器（建议名：`ChatHistoryClearCoordinator`），由页面/浮窗调用；UI 不直接拿 `RdbStore`、不直接删除文件。服务复用 `DatabaseHelper`、`ChatHistoryPersistence`、`ConversationRunCoordinator`、`NoteGenerationRepository` 的边界。

| 数据/缓存 | 清空动作 | 理由与边界 |
|---|---|---|
| `chat_message` | 在一个 RDB transaction 中删除全部行（不按当前 `activeSid`） | 它是聊天上下文投影；全局功能必须覆盖多会话 |
| `agent_memory` `summary`、`pending_note`、`ocr_result` | 同一 transaction 删除全部 session-scoped 派生行 | 它们会把旧聊天/OCR/待整理材料带回后续 prompt；不清会造成“聊天已空但模型仍记得” |
| `agent_memory` `profile` | **保留**，不执行按表全删 | `profile` 是学习画像；题目要求不得误伤画像。若未来支持“清除画像”，应是另一项明确操作 |
| `note_generation_run` / `source` / `checkpoint` / `log` | 取消并删除与会话关联、且没有 `note_generation_commit` 的未完成 run；删除其 source/checkpoint/log/run | 防止清空后 `restoreDraftsAfterHistoryLoad()` 恢复旧草稿；`NoteGenerationRepository.hasCommitForRun()` 认定有 commit marker 的 run 视为已提交，不删除 |
| `note_generation_commit` | 保留 | 它是 KnowledgeUnit 已提交的耐久标记，删除会破坏 note provenance/恢复判定 |
| `knowledge_unit`、`note_revision` | 保留，清空 transaction 不触碰 | 已保存的知识笔记不属于聊天历史 |
| `kg_edge`、`rag_chunk`、`rag_embedding`、study plan | 保留 | 知识结构、检索索引和复习计划与聊天记录无同义删除关系 |
| `filesDir/chat-history/sessions.json` | 写入一个带当前 `historyEpoch` 的合法空快照；使用现有 atomic write 语义 | 这是当前 UI 历史真源；只删 RDB 会被启动 projection 再写回 |
| `chat_history` Preferences 的旧 `sessions` | 清空快照提交后写空值或记录“已迁移/已清空”；读取侧仍必须检查 clear control | 防止快照丢失时旧迁移源复活；Preferences 不再作为生产保存真源 |
| `mindtrace_card_snapshot` | 不删除、不置零；成功后调用 `CardSnapshotService.refresh()` | 它只缓存知识笔记统计，不含聊天文本；置零会误导复习卡片 |
| `ChatSessionManager` / `ChatHistoryPersistence` 内存 | 清理 timer、pending snapshot、waiter、`latestSessions` 和失败重试；清空成功后保存 `[]` | 避免后台 flush 用旧数组覆盖空快照 |
| `AgentFloatWindow` / `AgentInputViewModel` | 取消运行、清理 draft/error/retry/session 状态，`sessions=[]`、`messages=[]`、`activeSid=''` | 运行态不能在清空后把旧消息重新保存 |
| AppStorage / UI cache | 不把 AppStorage 当历史源；清理聊天相关 seam/本地引用，知识缓存只做必要 refresh | AppStorage 是进程内状态，不能承担防回填凭据 |

`agent_memory` 的删除谓词必须是 `type IN ('summary', 'pending_note', 'ocr_result')`，不能写成只按 `session_id` 全删；这样即使画像记录使用特殊 session scope，也不会误伤 `profile`。

### B.3 防回填：持久化 clear epoch + 投影 guard

仅写一个进程内 boolean 不可靠：force-stop 后静态变量和 AppStorage 都会丢失。建议新增独立 Preferences 控制存储（名称可为 `chat_history_control`），至少包含：

```text
clear_state: 'none' | 'pending' | 'completed'
history_epoch: integer
pending_token: string
```

同时给 `ChatHistorySnapshot` 增加向后兼容的 `historyEpoch` 字段；没有该字段的旧快照按 epoch 0 处理。

写入/读取规则：

1. 每次全局清空先把 `history_epoch` 加一、写 `clear_state=pending`、flush Preferences，再允许删除。这个 marker 是跨进程/跨重启的恢复凭据。
2. `ChatHistoryPersistence.load()` 在加载会话前读取 control。看到 `pending` 时先进入 clear recovery；恢复未完成则返回 blocked/empty 结果，不能把旧快照交给 UI 或 projection。
3. `ChatContextProjectionService.reconcile()` 必须再次检查 control，并只投影 `snapshot.historyEpoch === control.history_epoch` 的消息。旧快照、无 epoch 的快照在存在 clear marker 时一律跳过；这是真正阻断 37 行回填的 guard。
4. `ChatHistoryPersistence.save()` 总是给新快照写当前 epoch。清空后新建的消息属于新 epoch，可以正常持久化和在后续重启时恢复；不需要把 `cleared=true` 永久设成阻断所有未来聊天。
5. `AgentMemoryService.saveMessage()` 增加 clear barrier/epoch 校验，并在写入前再次读取或使用本进程已同步的 epoch。清空开始后旧 `ConversationRunRef` 的迟到回调必须被拒绝，返回 `CHAT_HISTORY_CLEAR_IN_PROGRESS`，不能绕过 projection guard 直接 upsert。
6. 任何未来的演示/预览 seeding 若产生聊天快照，也必须通过同一 `ChatHistoryClearGuard`；`GalaxyPreviewSeedService` 当前不写 chat，不应被硬接到该 guard 以外。

`clear_state=completed` 不等于永久禁写：它表示空快照已经提交。新消息写入当前 epoch 后可正常投影。epoch 比单个 `cleared` boolean 更可靠，因为它既阻断旧快照，又允许清空后的新会话工作。

### B.4 跨文件/RDB 的失败与恢复协议

RDB transaction 与文件 atomic rename 不是同一个物理事务，不能假装它们天然原子。协调器要用 pending marker 把可恢复状态写清楚，并遵循以下顺序：

1. **Prepare**：获取全局 clear mutex；阻止新 run；等待/取消所有 `ConversationRuntime` in-flight 操作；写 `pending` marker；把空快照写到临时文件，但暂不替换正式 `sessions.json`。
2. **RDB transaction**：在同一 transaction 删除 `chat_message`、三类派生 `agent_memory`，以及没有 commit marker 的未完成 generation artifacts。任何一条删除失败都 rollback；不要逐表独立提交。
3. **Verify RDB**：在 transaction commit 后重新计数，确认 `chat_message=0` 且三类派生行=0；确认 `profile`、KnowledgeUnit、revision、kg_edge 的计数/版本未被修改。
4. **Commit snapshot**：原子 rename 临时空快照为正式快照；写入当前 `historyEpoch`。成功后清理临时文件和旧 `chat_history/sessions` 迁移值。
5. **Finalize**：再次验证 control、快照 epoch 和计数，写 `clear_state=completed`；释放 barrier；清空 UI/内存快照；刷新卡片统计；打成功日志。

中途失败的规则：

- Prepare 或 RDB transaction 失败：临时文件删除，RDB rollback，旧快照保持可读；`clear_state` 保持 `pending` 以便用户重试/下次启动恢复，UI 不宣布成功。
- RDB 已 commit、正式快照尚未 rename：旧快照不得被加载或投影；`pending` marker 使重启先完成 snapshot commit。当前进程显示恢复中/失败，不触发旧快照投影。
- 正式快照已 rename、`completed` 尚未写入：重启检测 `pending`，验证 RDB/epoch 后只补写 `completed`，不重复删除已提交数据。
- 任何恢复步骤都必须幂等；删除空集合、重复清理 incomplete run、重复写空快照都不应失败。超过重试上限只能报告失败并保留 `pending`，不能清掉 marker 让旧数据重新回灌。

这套顺序把“部分清空”限制在可恢复的 pending 状态：RDB 表内没有半个 transaction，正式快照不会在 RDB 未成功前被换掉，旧快照也不会在 pending 状态下重新投影。

### B.5 内存、并发和缓存失效

- 清空按钮确认后，先调用运行时的可等待 quiesce（不能只调用当前 `cancelAllRuns()` 的同步外壳），确保 `inFlight` promise 和 draft cancel 都完成。
- `ChatSessionManager` 增加 clear barrier；清空期间 `save/flush/retry` 不能接受旧 `sessions`，并取消 `STREAM_SAVE_THROTTLE_MS` timer 与旧 waiter。成功后把 static `latestSessions` 置为空快照。
- `AgentFloatWindow` 在 coordinator 返回 completed 后执行 `sync()`、`sessions=[]`、`messages=[]`、`activeSid=''`、清空 `generatedDraft` 和 `inputVm` 的 session-scoped error/retry；不要通过 `ensureActiveSession()` 立即创建带开场白的会话。
- `ChatContextProjectionService` 和 `AgentMemoryService` 都做 guard；只在 UI 层清空数组不足以阻止后台回调写库。
- `CardSnapshotService.refresh()` 只重算知识笔记统计；不把 card snapshot 作为聊天清空的删除对象。
- 不清理 `UiDataCacheService` 的知识数据快照，除非 refresh 发现知识库真的变化；本功能没有知识库写入。

### B.6 日志与埋点

沿用 hilog domain `0xA2A0`，TAG 建议 `ChatHistoryClear`。日志只记录状态、阶段、行数和 epoch，不记录正文、会话标题、message id 或 token。

成功一条：

```text
I 0xA2A0/ChatHistoryClear: code=CHAT_HISTORY_CLEAR_SUCCEEDED scope=all chatRows=0 derivedRows=0 epoch=%{public}d
```

失败一条：

```text
E 0xA2A0/ChatHistoryClear: code=CHAT_HISTORY_CLEAR_FAILED stage=%{public}s retryable=%{public}d epoch=%{public}d
```

同一用户操作只在最终成功或最终失败各打一条结果日志；中间恢复可以用 debug 级阶段日志，但必须继续脱敏。`chatRows=0` 是验证后的结果，不是“计划删除数”。

## C. 范围、选择和验收

### C.1 多会话策略

建议“清空对话历史”**全清所有 session**。用户看到的是全局历史功能，若只删 active session，其他会话仍可在历史面板出现，也会继续把旧上下文投影回来；全局 epoch 和一次 transaction 的实现也比“每个 session 单独设置 clear marker”可靠。现有长按删除继续提供按会话删除，避免把两种语义混在一个按钮里。

### C.2 不得误伤的边界

- `knowledge_unit`、`note_revision`、`kg_edge`、`rag_*`、study plan：清空前后主键、version、正文和计数一致。
- `agent_memory`：只删 `summary`/`pending_note`/`ocr_result`；`profile` 行、画像内容和更新时间保持不变。
- `note_generation_commit` 与已经提交的 KnowledgeUnit：保留；只有没有 commit marker 的未完成草稿 artifacts 才清理。
- 卡片快照：保留并刷新；不能因为聊天为空把复习统计显示成 0。
- 私有快照/旧 Preferences：都不能再提供旧 37 条消息给 projection；新的 epoch 消息仍可保存。

### C.3 真机验收清单

以下每一项都应在同一签名 APK、同一设备上执行；DB 计数用设备现有 sqlite3/诊断脚本读取，路径按题设包名解析，不把开发机绝对路径写进日志。

- [ ] **入口可达**：打开 AI 浮窗，点击 HistoryChip，能看到 `清空全部对话`；空历史时该操作禁用；无障碍朗读包含“清空全部对话”。
- [ ] **取消无副作用**：点击清空后选择“取消”，会话列表、消息正文、`chat_message` 计数和三类派生 `agent_memory` 计数均不变。
- [ ] **二次确认文案**：确认框标题、正文、取消/清空按钮与 B.1 一致；确认期间重复点击和发送入口被禁用。
- [ ] **全会话清空**：预先创建至少两个不同 `session_id`，确认清空后面板无旧会话，消息区显示 `EmptyStateHint`，没有自动插入开场白。
- [ ] **RDB 结果**：成功日志出现后查询 `chat_message` 为 0；`agent_memory` 的 `summary`、`pending_note`、`ocr_result` 为 0；`profile` 计数不变。
- [ ] **知识边界**：清空前后抽样比对 `knowledge_unit`、`note_revision`、`kg_edge` 的主键/版本/正文和计数，全部一致；卡片统计仍与知识库一致。
- [ ] **force-stop 回灌防护**：清空成功后执行 `aa force-stop`，确认进程计数为 0，再启动 App；查询 `chat_message=0`，旧 37 条的稳定 ID 不存在，且不会出现第 38 条开场白。
- [ ] **DB 家族删除后的防护**：在清空完成后按既有测试流程删除 DB 家族并让 App 重建，再启动；由于 clear control 和空快照仍在，`chat_message` 仍为 0，不能重新投影旧快照。
- [ ] **清空后新消息**：清空后发送一条新消息，确认只出现新 epoch 的消息；force-stop → 重启后新消息能恢复，旧 ID 不恢复。
- [ ] **旧 Preferences 迁移防护**：存在旧 `chat_history/sessions` 值时执行清空并重启；空快照/clear guard 优先，旧值不再迁移成聊天行。
- [ ] **进行中 run 竞争**：回复流式生成期间点击清空；run 被取消且等待结束后 `chat_message=0`，无迟到 assistant 回写，无未完成草稿卡片复活。
- [ ] **generation 边界**：清空前保留一个已提交知识笔记并制造一个未完成草稿；清空后笔记仍可打开，未完成草稿不再恢复，`note_generation_commit` 仍存在。
- [ ] **失败/回滚**：通过一次受控 debug fault 或在日志标记的阶段 force-stop，覆盖 RDB transaction 失败和 snapshot rename 前崩溃；重启后看到 pending recovery，不能看到“半删”成功状态，重试后最终达到全清。
- [ ] **日志脱敏**：`hilog` domain `0xA2A0` 能找到一条 `CHAT_HISTORY_CLEAR_SUCCEEDED` 或 `CHAT_HISTORY_CLEAR_FAILED`；日志不含聊天正文、标题、message id、API key。
- [ ] **重复点击/幂等**：连续确认两次或在恢复后再次确认，不产生重复错误；最终仍为 `chat_message=0`，画像/知识数据不变。
- [ ] **空状态截图**：保存清空成功后的浮窗截图，包含空状态提示、无旧 session chip、无开场白；作为 UI 验收证据。

### C.4 实施顺序

1. 先为 control store、epoch、快照解码和 clear state 写纯逻辑测试，覆盖旧快照、pending recovery、重复调用和失败阶段。
2. 实现 clear coordinator、RDB transaction、generation artifact 清理和 snapshot staged commit；先接入日志与计数验证。
3. 在 `ChatHistoryPersistence.load/save`、`ChatContextProjectionService.reconcile`、`AgentMemoryService.saveMessage` 加 guard 和 epoch 传递；确认所有 `chat_message` 写入口都经过 barrier。
4. 接入 `ChatSessionManager`/`ConversationRuntime` 的 quiesce、内存失效和重启恢复。
5. 在 `SessionsPanel` 增加全局入口和确认控制器，接入成功/失败 toast 和空状态。
6. 按 C.3 真机清单执行；只有拿到 `chat_message=0` 的重启证据、空状态截图和成功/失败日志后，才把设计转为 implemented。

## 未决项（实施前必须闭合）

以下是源码与运行包之间仍需闭合的实施前置，不是要求重做题设已经完成的设备实验。

- [ ] 将目标安装包版本与当前 checkout 绑定；若实现阶段能读取其私有快照，只需用于确认版本对应关系，不重复题设已完成的 DB/force-stop 实验。
- [ ] 用运行中 APK 的版本信息对齐当前仓库源码，解释 `created_at` 删除前后完全相同的事实；若仍不符，继续查旧 HAP/HSP 或 RDB 恢复层。
- [ ] 找到题设第 38 条开场白的实际写入者；当前 `ConversationWorkflow.ets:1218` 不是写入点，不能作为 guard 的唯一依据。
- [ ] 决定快照 schema 的 epoch 字段版本号和旧快照迁移策略，并让 DSH 在实现 PR 中同步测试/文档索引。

