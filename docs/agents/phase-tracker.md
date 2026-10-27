# 阶段进度与验收 (phase tracker)

> 唯一进度口径。代码里做了什么以本表为准；改完功能不同步本表，视为未交付。
>
> 当前主线：**v1 收尾（P3/P4 云端已通）→ v2 `KnowledgeModel` 拆分（#209–#215）**。复赛版本已冻结，不再往 v1 加功能。
>
> 2026-10-25 口径修正：P1 的「小艺拉起应用选图」**不在 v1 范围**。小艺侧只能走 A2A 回话，`agentUI` 拉起真机返回 `start_ability_fail`（1011），v1 的入口是应用内 `+ → 批量`。

## 状态词

| 词 | 含义 |
|---|---|
| ✅ 已验收 | 有真机证据，命令可复现 |
| 🟡 已实现未验收 | 代码在，缺真机/端到端证据 |
| ⬜ 未开始 | 只有设计，没有代码 |
| ⛔ 阻塞 | 依赖外部（平台审核 / SDK 版本 / 权限） |

## 阶段表

| 阶段 | 目标 | 实现 | 验收标准 | 证据 |
|---|---|---|---|---|
| **P0 协议接入** | 小艺能调起 `AgentExtensionAbility` 并拿到回复 | ✅ | 真机小艺发消息后出现 agent 气泡 | `python scripts/a2a_smoke.py --text "整理数学题"` 返回 `ok: true`；hilog 出现 `onCreate → onConnect → onData → sendData` |
| **P1 意图与入口** | v1 入口 = 应用内 `+ → 批量`；小艺侧只回话不拉 UI | ✅ | 应用内批量入口可拉起多选 | `AlbumPickerLauncher.pick(ctx, 20)` 真机可拉起多选；小艺拉起 `agentUI` 返回 `start_ability_fail`（1011），已移出 v1 |
| **P2 批量选图** | Picker 多选，最多 20 张，复制进沙箱 | ✅ | 选 20 张不崩、URI 全部可读 | 「+ → 批量」入口已上线；`pick(ctx, 20)` 真机可拉起多选 |
| **P3 真实编排** | `handleTask` 接 `OcrNode → StructureNode → PersistNode` | ✅ | 生成的笔记杀掉应用重启后仍在 | `node scripts/e2e-capture/run.mjs` → `stage=done ok=2 failed=0 totalMs=87860`，两张图 `insert ok=1`，卡片 `units=20 due=12 new=9` |
| **P3b 文搜图** | 落库图片建索引，按文字检索命中 | ✅ | 两条 query 各命中 5 张 | `stage=search q=一元二次方程 hits=5 ms=61`、`q=平方根 hits=5 ms=30`（spec 034 §8；Worker 化后不再阻塞主线程） |
| **P4 模型网关** | 端侧优先；端侧不可用则走用户模型并标注「已降级」 | 🟡 云端 ✅ / 端侧待 2in1 | 两种路径都能给出可区分的结果 | 云端真机：App 首字 741ms（#226 后）、小艺 1347ms / 54 字 / 341 字节快照；端侧 `localChatModel` 限 PC/2in1，待设备验证 |
| **P4 结果回执** | 对话/卡片报「本次整理 N 条」 | ⬜ | 小艺里能问到刚生成的条数 | `a2a_smoke.py` 的 `reply_text`（当前回复不含条数） |
| **P5 合规落地** | AI 标识 + 导出元数据 | ⬜ | 导出的文件带 `AI生成 / MindTrace / mindtrace-note-agent` | 导出样本文件 |
| **P6 上架运营** | 平台审核通过并发布 | 🟡 | 开放平台状态为「已上架」 | 平台截图 |

> **现状（2026-10-27 实测）**：`entry/src/main/ets/agentextability/`（3 个文件 671 行）里没有任何 `Dispatcher` / `CaptureGraph` / `NoteDao` / `KnowledgeModel` 引用，`handleTask` 只把用户那句文本交给 `ReplyService.complete` 换一句话回来。所以小艺现在**只能对话**：发「整理数学题」它只会追问要题目，既拿不到图，也不会往 RDB 写任何东西。P0「能调起」与 P3「真整理」之间的缺口就是这个。

## 每阶段的完成定义 (DoD)
一个阶段算「完成」必须同时满足四条，缺一条就是 🟡：

1. 代码合入分支，`node scripts/agent-gate/index.mjs` 为 `RESULT: PASS`
2. 库里有一条可比对的验收证据（命令输出 / 日志 / 截图路径）
3. 本表状态与证据列已更新
4. 受影响的文档（ADR / spec / AGENTS 指针）同步改过

## 验收命令速查

| 用途 | 命令 |
|---|---|
| 静态质量 | `node scripts/agent-gate/index.mjs` |
| 端A2A 真机冒烟 | `python scripts/a2a_smoke.py --text "整理数学题"` |
| 构建（无 DevEco） | 见 `AGENTS.md` §常用命令 |
| 装机 | `hdc install -r entry/build/default/outputs/default/entry-default-signed.hap` |
| 协议日志 | `hdc shell "hilog -x" \| grep MindTraceA2A` |

## 已知阻塞

| 项 | 影响阶段 | 说明 |
|---|---|---|
| 小艺上架审核 | P6 | 审核通过前只有白名单账号能调起 |
| 设备重装后必须重启小艺 | P0 复测 | 旧连接不释放，日志里连 `onCreate` 都没有 |
| 平台「服务名称」= `abilityName` | P0 | 填错就是 `extension ability not exist`，改完必须重新导入 AgentCard |

## 维护规则

- **改代码 → 先看本表**：确认自己在哪个阶段，不要跨阶段顺手做
- **改协议 / 改 `agent_config.json`**：必须重新导入平台 + 重发真机测试 + 重启小艺，三件事缺一不可
- **阶段推进**：只有证据齐全才能把 ⬜ 改 ✅；🟡 只能由**跑过验收命令**的人改
