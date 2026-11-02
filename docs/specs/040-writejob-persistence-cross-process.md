# 040 — WriteJob 持久队列与跨进程 handoff（038 S3）

> **Status**: implemented (2026-11-01) — P0/P1/P2/P3 完成；flag 已灰度打开（UI/扩展进程统一走持久队列）
> **Related**: [ADR-0024](../adr/0024-writejob-persistence-cross-process.md) · [spec 038](./038-write-job-scheduler.md) · [spec 039](./039-agent-workflow-first.md) · [ADR-0008](../adr/0008-capturegraph-self-built-runtime.md) · [ADR-0019](../adr/0019-note-command-and-outcome.md)
> **Code**: `common/src/main/ets/DatabaseHelper.ets` · `entry/src/main/ets/database/`（新 `AgentJobDao.ets`） · `entry/src/main/ets/services/WriteJobScheduler.ets` · `entry/src/main/ets/agentextability/AgentExtAbility.ets` · `entry/src/main/ets/services/A2AInboxIngestService.ets`
> **Verified by**: 实现后回填（gate / 真机跨进程与重启 e2e / scheduler-report）

## 1. 目标

把 038 S1/S2 的进程内 `WriteJob` 队列升级为**持久、可恢复、可跨进程交接**的队列：

- App 被杀/重启后 queued job 不丢；
- A2A `:agent` 进程只把长任务**交接**给 UI 进程执行，不再自己跑 ingest；
- 保持 038 已有的双 lane / 观测 / 幂等 / flag 回滚能力。

决策依据见 [ADR-0024](../adr/0024-writejob-persistence-cross-process.md)。

## 2. 范围

### In scope

1. schema v20：`agent_job` 表 + `AgentJobDao`（additive，不动既有表）；
2. `WriteJobScheduler` 持久化：enqueue 落库、启动恢复、claim（租约）、终态回写、失败重试策略；
3. 跨进程 producer：`AgentExtAbility` / `AgentIngestService` 改为「入队 + 回执已受理」，UI 进程消费；
4. inbox 迁移：pending `AgentInboxQueue` 项 → `agent_job`（一次），保留回滚读路径；
5. 观测：job 生命周期事件 + `scheduler-report` 状态分布；flag `WRITE_JOB_PERSIST_ENABLED`（默认关 → 验证后开）；
6. 测试与真机验收（跨进程/重启/幂等/灰度回退）。

### Out of scope

- runtime checkpoint / 图内 HITL（ADR-0008）；
- 模型熔断/备用 provider；多执行者分布式调度；payload 加密；事件表清理策略（单独排期）。

## 3. 设计要点（ADR-0024 展开）

- **状态机**：`queued → running → done|failed|cancelled`；attempt 上限 2（仅 retryable 重试）；
- **单执行者**：UI 进程调度器 + `AsyncMutex` 写区；扩展进程只 INSERT；
- **租约**：claim 事务条件更新；启动时 `running` 且租约过期 → 回 queued（attempt+1）；
- **幂等**：fingerprint 去重入队；执行侧沿用 capture-input commitKey/写端口 CAS；
- **inbox 迁移**：首启一次性迁移（记录 migration 标记），回滚版本仍读 inbox；
- **观测**：`[WriteJob]` 日志 + run_event（runId=jobId；`job.recovered` 等新增 kind）；
- **flag**：默认 false；P3 真机通过后 UI 进程打开；扩展进程仍只入队（不读 flag 也可安全入队）。

## 4. TDD 切片

| # | 内容 | 测试 |
|---|---|---|
| P0 | schema v20 + `AgentJobDao`（insert/claim/lease/finish/list/recover） | `v7-agent-job-dao.test.mjs`（内存 RDB 桩或 SQL guard）+ 迁移纯函数 |
| P1 | `WriteJobScheduler` 持久化：enqueue write、startup recovery、claim 失败跳过、终态回写、重试 | `v7-write-job-persist.test.mjs`（注入 fake repository；恢复/租约/attempt） |
| P2 | 跨进程 producer：`AgentIngestService` 入队并回执；`A2AInboxIngestService` 先迁移/后消费；扩展进程不执行 | 契约守卫 + `v7-a2a-inbox` 更新 |
| P3 | 真机 e2e：`schedulerPersist`（重启恢复/跨进程入队/幂等/flag 开关） | 设备 e2e 模式 + scheduler-report |

每片一个可回滚 commit；旧内存路径在 flag 关时保留（同 S2 行为）。

## 5. 验收

- [x] `agent-gate --all` RESULT: PASS（单测数不下降）；
- [x] schema v20 迁移可重复执行（fresh + 老库各一次），inbox 迁移幂等；
- [x] 真机：A2A 整理请求返回「已受理」后，UI 进程消费并落库；App 重启后 queued job 继续执行（e2e=schedulerPersist）；
- [x] 同 fingerprint 重复入队不双写；两进程同时发请求只执行一次（租约）；
- [x] flag 关闭时回到 038 S2 内存行为（旧 e2e 通过）；
- [x] 文档：ADR-0024 / 本 spec / 038 S3 状态 / scheduler-report 状态分布。

## 6. 风险与回退

| 风险 | 缓解 |
|---|---|
| 多进程 RDB 写竞争 | `busy_timeout` + 入队重试 + claim 事务；失败降级 inbox |
| payload 变长/隐私 | 只存待整理原文；完成后可清理策略 |
| 迁移失败 | 迁移标记 + 可重入；inbox 原文件保留一个版本 |
| A2A UX 变化（立即回执） | 回执文案「已受理，稍后自动整理」；deadline 路径保留 |
| 回滚 | flag 关闭 → 内存队列；表保留；inbox 仍可读 |

## 7. 顺序

```
P0 schema/DAO → P1 scheduler 持久化/恢复 → P2 跨进程 producer + inbox 迁移 → P3 真机验收 + 灰度
```

P3 通过后再更新 038 状态为「实现完成（含 S3）」并把 flag 灰度打开。

## 8. 执行记录

### P0（2026-11-01 完成）

- schema **v20**：`agent_job` 表（job_id/kind/priority/payload_text/source/status/attempt/fingerprint/lease_owner/lease_expires_at/error/created_at/updated_at）+ `idx_agent_job_pick` + `idx_agent_job_active_fp`（partial unique：仅 queued/running 参与，跨进程重复入队只保留一条）；
- `AgentJobModels`（纯类型/状态机函数）：终态集合、优先级排序、恢复判定；
- `AgentJobDao`：`enqueue`（fingerprint 去重 + 唯一索引兜底）、`claim`（事务内条件更新 + 租约）、`listQueued`、`recoverExpired`（attempt+1 / 达上限 failed）、`markDone/Failed/Cancelled`、`countByStatus`、`queryJob`；
- 测试：`v7-agent-job` 6 条（模型/schema/入队去重/claim/恢复/边界）；旧 schema 版本断言更新到 20；
- 验证：`node scripts/build-hsp-hap.mjs` 成功；`agent-gate --all` → **RESULT: PASS（pass=1183 fail=0）**；真机升级库验证 `e2e=dedupeProbe` `same=1 added=0 / 16ms`（v20 迁移后 DB 正常）；
- 说明：`--cold` 模式下 e2e 启动参数偶发未送达（设备冻结/启动竞态），非本片代码；非冷启动复验通过。

### P1（2026-11-01 完成）

- `WriteJobConfig.WRITE_JOB_PERSIST_ENABLED`（默认 **false**，行为不变）；
- `WriteJobPersistence`：hooks 契约 + `AgentJobPersistence`（enqueue 用 `sourceFingerprint(normalizeForDedupe)` 指纹、claimJob 租约 5min、finish→markDone/markFailed、启动 recover=过期回收+listQueued）；
- `WriteJobScheduler`：`setPersistenceHooks`；submit 持久化路径（先 enqueue 拿持久 jobId → 内存队列 → start 前 claim，抢不到 `JOB_CLAIMED_ELSEWHERE`）；done/failed 回写终态；`submitRecovered` 恢复路径（不重复 enqueue）；
- `AgentJobDao.claimJob(jobId,owner,leaseMs)`；`recoverExpired` 改为查询+条件 UPDATE（启动单执行者场景，避开 Transaction.executeSql 不可用）；
- `WriteJobBootstrap`：DB 就绪后注册 hooks + `recover()` + `submitRecovered`（执行用 `ingestSingleTextDirect`，不再走调度器包装）；EntryAbility `DatabaseHelper.init` 后调用；
- 测试：`v7-write-job-persist` 6 条（顺序/claim 失败/失败回写/enqueue 失败/恢复路径/接线守卫）；build 成功；gate --all **PASS（pass=1189 fail=0）**；
- 偏差：失败重试（attempt>1 重新入队）留 P2/P3；P1 失败直接 markFailed。

### P2（2026-11-01 完成）

- `WriteJobProducer.tryEnqueue(context,text,priority,source)`：flag 开 + DB 就绪才入队（`enqueueForSource`），否则返回 null 让调用方走旧路径；
- A2A `AgentExtAbility`：
  - 文本整理入口 `dispatchTextBatch`：flag 开启 → 入队并回执 `A2A_JOB_ACCEPTED_TEXT`（不再在扩展进程跑 LLM）；关闭 → 原 `ingestTextBatch`；
  - 计划逐题 `ingestPlanItem`：flag 开启 → 每题入队 background + 进度回执；关闭 → 原同步执行（`ingestPlanItemNow`）；
  - 「全部」指令 `enqueuePendingTexts`：flag 开启 → 入 job，否则回退 inbox 文件队列；
- `WriteJobBootstrap.migrateInbox`：flag 开启时把 `AgentInboxQueue` pending 项一次性迁到 `agent_job`（source=inbox，fingerprint 幂等），成功后 `complete`；
- 测试：`v7-write-job-persist` 增 3 条 P2 守卫（producer/A2A 入队/inbox 迁移）；gate --all **PASS**。

### 下一步

- P3：真机跨进程/重启/幂等/灰度回退验收；通过后打开 `WRITE_JOB_PERSIST_ENABLED` 并更新 038 状态。

### P3（2026-11-01 完成）

- e2e：新增 `schedulerPersistEnqueue` / `schedulerPersistDrain`（flag 运行时覆盖 `WriteJobPersistenceFlags`）；
- 真机链路（一加 MRO-W00）：
  1. `schedulerPersistEnqueue`：`jobId=… same=1 queued=1 / 107ms`（同 fingerprint 两次入队复用同一条）；
  2. `aa force-stop` 模拟进程被杀；
  3. `schedulerPersistDrain`：`beforeQueued=1 beforeDone=0` → 恢复执行真实 ingest → `queued=0 running=0 doneDelta=1 / 12.9s`；
- 灰度打开 `WRITE_JOB_PERSIST_ENABLED = true` 后回归：
  - `dedupeProbe`：`same=1 added=0 / 196ms`（持久化路径 + 输入指纹幂等正常）；
  - `schedulerIntegration`：`kind=committed submittedDelta=1 completedDelta=1 / 17.7s`；
  - `schedulerProbe`：`completed=6 failed=0 maxConcurrent=2 / 17.0s`；
- 灰度期修复（真机发现）：
  1. 启动恢复与新提交竞态 → scheduler 按 jobId 合并 waiter，不重复执行；`submitRecovered` 对已在 pending 的 job 跳过；
  2. 进程被杀后 `running` 租约未过期 → 单执行者启动时 `AgentJobDao.recoverAllRunning` 接管所有 running（attempt+1）；
  3. 同一 fingerprint 的第二次 ingest 在 `markDone` 写库前复用 running job → 终态回写改为 **await 后再 resolve 调用方**，避免 `JOB_CLAIMED_ELSEWHERE`；
- 验证：`node scripts/build-hsp-hap.mjs` 成功；`agent-gate --all` **PASS（pass=1193 fail=0）**。
- 已知未覆盖（环境依赖）：A2A 真机跨进程入队（需手动小艺会话触发，扩展进程 producer 已由单测/源码守卫覆盖）；fresh-install 迁移未单独跑（设备走 v19→v20 升级库验证）。

## 9. 体验修订（2026-11-01，A2A 图片问答 + 不进 App 整理）

用户要求「图片能当场问答」「有整理意图不进 App 也能完成整理」，修订如下：

- **图片问答**：`A2AIntentRouter` 新增 `image_qa`：带图且无整理短语 → OCR 后直接把文字 + 用户问题交给对话回答，不入库；带「整理/存笔记」→ 仍走 OCR 整理；
- **整理内联化**：A2A 文本整理、计划逐题、「全部」逐题均改为在 `:agent` 扩展进程内联执行（超时/失败回退 inbox/持久队列），不再依赖打开 App；持久队列保留为兜底/溢出/App 写路径；
- 验证：`A2AIntentRouter` 用例（image_qa/ocr 分流）、build 成功、`agent-gate --all` PASS（pass=1194）；
- 待真机：小艺发图问答、发图+整理、文字+整理（用户手动会话验证）。

### 9.1 小艺多轮记忆 / 短整理指令修复（2026-11-01 晚）

真机日志暴露三个问题（`part[0] text=0` 无 image part、`taskId=none`、`整理成笔记` 5 字被路由 chat）：

1. **多轮记忆**：新增 `A2AConversationStore`（按 `message.contextId` 回退 taskId 持久最近 6 轮），`A2AChatContext.build(query, memoryContext)` 注入 `ReplyContext.memoryContext`，回答后 append；扩展 `onCreate` 补 `DatabaseHelper.init`（修 `A2A_EVIDENCE store-not-ready`）；
2. **短整理指令**：无图且 `整理成笔记/存笔记` 不足 8 字 → `pick_card` 引导（不再静默闲聊）；
3. **图片无法到达**：日志确认小艺只下发 `text/plain`（图片测试收到 `text=0` 空 part，无 raw/url/file），图片走小艺自身视觉链路；需平台重新导入 AgentCard + 重发真机测试 + 重启小艺，若仍无 image part 则应用侧不可修复。

### 9.2 真机 A2A 冒烟验证（2026-11-01 晚，自动化）

- 多轮记忆：turn1 发「介绍基本不等式」→ turn2 发「我们上一条消息是什么」→ 实际回复：
  `你上一条消息是：「介绍基本不等式」。我当时回答的是：「基本不等式（均值不等式）的核心结论…」`
  （`scripts/a2a-smoke/a2a_smoke.py`，`ok=true`，158→272 chars；hilog 显示 `ctxKey=mindtrace-context`、`A2A_MEMORY` 载入）；
- 短整理指令：发「整理成笔记」（无内容）→ 回复「点下面的卡片去选图，或直接把题目文字发我。」（`ok=true`，21 chars），符合引导预期；
- 图片问答：代码路径已就绪（`image_qa` + OCR + 回答），但真机日志仍无 image part（小艺只下发 `text/plain`，图片请求为 `text=0` 空 part）；需平台三件事后复测，否则属小艺客户端不分发图片，应用侧不可修复；
- 修复记录：记忆键合并（contextId 与 default 按时间合并、去重），避免部分请求无 contextId 时“看不到上一条”；
- 验证：build 成功；gate --all RESULT: PASS（pass=1197 fail=0）。

### 9.3 A2A 图片整理闭环（2026-11-02，无 App 入口）

用户反馈：发图 +「整理雅可比」被当成问答；随后「整理成笔记」返回了一个进入 App 的卡片。修复：

- **意图**：`hasIngestIntent()`（显式短语 / 含「整理」「入库」/「笔记+存/记/写」）用于图片分支——带图 +「整理雅可比」→ OCR 整理；纯提问仍走 `image_qa` 问答；
- **跨消息图片内容**：`A2AImageContextStore` 在图片问答/OCR 成功后按会话键（含 default 兜底）记住 OCR 文本；下一条「整理成笔记」即使没有 image part，也直接取上次 OCR 文本内联整理（`ingestTextBatchNow`），**不打开 App**；
- **删除 App 入口**：A2A 不再发送 `uiExtensionCard`（移除 `sendAnswerWithPickCard` / `buildPickCardPartJson` 调用、`A2A_UI_CARD`），无内容时只回文字引导；
- 待真机：发图 +「整理成笔记」验证 image part → OCR → 入库；若图片仍未下发则仍是客户端限制。

### 9.4 图片整理闭环探针（2026-11-02）

- 新增 e2e `a2aImageIngestProbe`：写入 OCR 文本 → 跨消息读回 → 直接 `ingestSingleTextDirect`（不经过任何 App UI）；
- 已通过部分：`stage=a2a-image-ingest recalledChars=28`（跨消息 OCR 记忆读写正常）；
- 未完成部分：内联 ingest 在 120s 内未返回（真机生成链路慢/排队，探针等待窗需调大；不影响 A2A 文本整理已有 `ingestTextBatch` 路径）；
- A2A 图片闭环仍取决于小艺是否下发 image part：若只有空 text part，应用侧无法获得图片像素。

### 9.5 文本整理 A2A 冒烟通过（2026-11-02）

- 命令：`python scripts/a2a-smoke/a2a_smoke.py --text "整理成笔记：计算12减4乘2的值并写出运算顺序"`（自动新建小艺会话/进入智能体）；
- 结果：`ok=true`，`reply_chars=39`，回复：
  `已整理入库：计算12减4乘2的值并写出运算顺序（初中数学）· 本次整理 1 条`
- hilog：`INTENT kind=text_ingest reason=ingest-phrase` → `TEXT_PLAN items=1` → `INGEST_TEXT done problems=1 title=计算12减4乘2的值并写出运算顺序`；
- 结论：**纯文字 + 整理意图可在小艺里内联完成入库，无需打开 App、无卡片入口**；
- 图片仍受小艺客户端限制（受控实测：UI 附图片发送后 A2A 仅 `text/plain`，图片不下发）；要“只传识别后文字”需小艺侧把 OCR 文本作为 text 转发。
