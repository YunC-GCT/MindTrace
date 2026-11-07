# 阶段进度与验收 (phase tracker)

> 唯一进度口径。代码里做了什么以本表为准；改完功能不同步本表，视为未交付。
>
> 当前主线：**v1 收尾（P3/P4 云端已通）→ v2 `KnowledgeModel` 拆分（#209–#215）**。复赛版本已冻结，不再往 v1 加功能。
>
> 2026-10-30 口径修正：**项目处于测试态，不推进上架**。P6 暂缓、P5 合规随 P6 缓做；不上架只影响两项验证——「意图注册（Intents Kit）」与「Agent Framework Kit 拉起智能体」，不影响应用内链路与 A2A 白名单链路。
>
> 2026-10-25 口径修正：P1 的「小艺拉起应用选图」**不在 v1 范围**。小艺侧只能走 A2A 回话，`agentUI` 拉起真机返回 `start_ability_fail`（1011），v1 的入口是应用内 `+ → 批量`。

## 状态词

| 词 | 含义 |
|---|---|
| ✅ 已验收 | 有真机证据，命令可复现 |
| 🟡 已实现未验收 | 代码在，缺真机/端到端证据 |
| ⬜ 未开始 | 只有设计，没有代码 |
| ⛔ 阻塞 | 依赖外部（平台审核 / SDK 版本 / 权限） |
| ⏸ 暂缓 | 明确不在当前阶段推进（测试态 / 等外部条件成熟） |

## 阶段表

| 阶段 | 目标 | 实现 | 验收标准 | 证据 |
|---|---|---|---|---|
| **P0 协议接入** | 小艺能调起 `AgentExtensionAbility` 并拿到回复 | ✅ | 真机小艺发消息后出现 agent 气泡 | `python scripts/a2a_smoke.py --text "整理数学题"` 返回 `ok: true`；hilog 出现 `onCreate → onConnect → onData → sendData` |
| **P1 意图与入口** | v1 入口 = 应用内 `+ → 批量`；小艺侧只回话不拉 UI | ✅ | 应用内批量入口可拉起多选 | `AlbumPickerLauncher.pick(ctx, 20)` 真机可拉起多选；小艺拉起 `agentUI` 返回 `start_ability_fail`（1011），已移出 v1 |
| **P2 批量选图** | Picker 多选，最多 20 张，复制进沙箱 | ✅ | 选 20 张不崩、URI 全部可读 | 「+ → 批量」入口已上线；`pick(ctx, 20)` 真机可拉起多选 |
| **P3 真实编排** | `handleTask` 接 `OcrNode → StructureNode → PersistNode` | ✅ | 生成的笔记杀掉应用重启后仍在 | `node scripts/e2e-capture/run.mjs` → `stage=done ok=2 failed=0 totalMs=87860`，两张图 `insert ok=1`，卡片 `units=20 due=12 new=9` |
| **P3b 文搜图** | 落库图片建索引，按文字检索命中 | ✅ | 两条 query 各命中 5 张 | `stage=search q=一元二次方程 hits=5 ms=61`、`q=平方根 hits=5 ms=30`（spec 034 §8；Worker 化后不再阻塞主线程） |
| **P4 模型网关** | 端侧优先；端侧不可用则走用户模型并标注「已降级」 | 🟡 云端 ✅ / 端侧待 2in1 | 两种路径都能给出可区分的结果 | 云端真机：App 首字 741ms（#226 后）、小艺 1347ms / 54 字 / 341 字节快照；端侧 `localChatModel` 限 PC/2in1，待设备验证 |
| **P4 结果回执** | 对话/卡片报「本次整理 N 条」 | ✅ | 小艺里能问到刚生成的条数 | 2026-10-31：A2A 就地入库后回「已整理入库：…（学科）· 本次整理 1 条」并写入 receipt；问「本次整理了几条」回「本次整理 3 条：成功 3 条，失败 0 条」，a2a_smoke 双用例 `ok:true` |
| **P5 合规落地** | AI 标识 + 导出元数据 | ⏸ 随 P6 缓做 | 导出的文件带 `AI生成 / MindTrace / mindtrace-note-agent` | 测试态不产出发布包，暂不验收 |
| **P6 上架运营** | 平台审核通过并发布 | ⏸ 暂缓（测试态不上架） | 恢复上架时按 `system-architecture-layered.md` §15 清单重新走；当前不验收 | 曾提交过一次审核，结果不阻塞开发 |

> **现状（2026-10-30 复核）**：A2A **已能就地入库**。`handleTask` 三条分支：① 回执意图命中 → 读 `receipts/last-capture.json` 回执（不调模型）；② 带图片或「存笔记」→ `AgentIngestService.ingest` → `OcrService`（仅图片）→ `AiService.ingestText` → `Dispatcher` → `KnowledgeUnitWriteService` 落库，失败退 `AgentInboxQueue`；③ 其余对话 → `ReplyService.complete`。**「小艺只能对话、不会写库」的旧结论作废**（`64008c3` 推翻）。剩余缺口：P4 结果回执（回复里还没有「本次整理 N 条」）、图片 part 客户端不下发。

> **2026-11-07 补充（检索与判重质量线，不属于 P 阶段）**：RAG 已从「关键词检索」升级为五路混合召回——整句 FTS / 数学签名 / 词 OR / 短词 LIKE / 稠密向量，RRF 融合；稠密向量走本地 BGE 服务（`tools/embedding_service`，模型/端点未配置时自动退回词面）；向量头部差距 < 0.05 时做一次摘要重排，< 0.03 时追加一次 LLM 查询改写。回答前加 LLM 证据判定（`EvidencePolicy`：strict / balanced / expansive，默认 balanced），语料外负样本命中从 5/5 降到约 1/5（概率性）。写前判重升级为 L1 规则 + 向量兜底（0.75）+ LLM 三分类仲裁（same / supplement / different），supplement 照常写入并发 `action=append` 建议。状态：代码与真机探针已验证；学习模式与建议请求未接 UI（仅编排层 / 日志）。证据：`docs/research/agent-framework-layering-review-2026-11-02.md` §37–§49。

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
| 端A2A 真机冒烟 | `python scripts/a2a-smoke/a2a_smoke.py --text "整理数学题"`（`ok` / `reply_text` / `hilog`） |
| 构建（无 DevEco） | 见 `AGENTS.md` §常用命令 |
| 装机 | `hdc install -r entry/build/default/outputs/default/entry-default-signed.hap` |
| 协议日志 | `hdc shell "hilog -x" \| grep MindTraceA2A` |

## 已知阻塞

| 项 | 影响阶段 | 说明 |
|---|---|---|
| 小艺上架审核 | P6（⏸ 暂缓） | 测试态不推进；审核通过前只有白名单账号能调起，换机/换账号需重新加白名单 |
| 意图注册（Intents Kit） | P1 / skill 的 7 个 action | 官方要求意图注册关联**已上架应用**，测试态无法联调 |
| Agent Framework Kit 拉起智能体 | 入口 | 官方口径「在小艺开放平台**上线**智能体后」才可通过 UI 控件拉起，测试态不可验 |
| 设备重装后必须重启小艺 | P0 复测 | 旧连接不释放，日志里连 `onCreate` 都没有 |
| 平台「服务名称」= `abilityName` | P0 | 填错就是 `extension ability not exist`，改完必须重新导入 AgentCard |
| 端A2A 图片不进报文 | P1 图片通道 | 小艺侧已上传成功（`HwVA_ObsAbilityRequestTask: uploadToObs fileId=…`）、待发送区有缩略图，但发出的 `message.parts` 只有 `[{"mediaType":"text/plain"}]`；整包 475 B，见 `MindTraceA2A: raw=`。卡片声明 `image/*` + 五种显式 MIME（v1.0.2）后仍复现。平台下发的 agentEntity 里 `supportPlusInputModes=["image","camera","file"]`、`agentApiType=[]`。扩展侧已兼容 `url`/`raw`/`file`/`data` 四种 part 形状，待定位客户端为何不填 parts |；**已落地降级通道（2026-11-01）**：A2A 意图路由（chat / OCR / 存笔记 / 拍题卡片 / 计划推进）+ checkpoint 规划（继续/第N题/全部/取消）一题一题来；图片请求先 OCR 出识别摘要再入库（真机 `e2e=agentImagePlan`：1 图 → 3 题规划 → 第 1 题入库；文本 `e2e=agentTextPlan`：2 题规划 → 第 1 题入库） |

## 维护规则

- **改代码 → 先看本表**：确认自己在哪个阶段，不要跨阶段顺手做
- **改协议 / 改 `agent_config.json`**：必须重新导入平台 + 重发真机测试 + 重启小艺，三件事缺一不可
- **阶段推进**：只有证据齐全才能把 ⬜ 改 ✅；🟡 只能由**跑过验收命令**的人改
- **上架口径**：测试态下不写「已上架 / 待上架」；P5 / P6 状态只在本表改，其他文档引用本表
