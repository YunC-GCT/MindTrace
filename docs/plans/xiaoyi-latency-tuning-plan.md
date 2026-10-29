# 小艺响应链路性能修复方案

> **Status**: proposed (2026-10-25)
> **Related**: (implicit) `docs/agents/phase-tracker.md` · `docs/specs/018-agent-workflow-architecture.md` · `docs/adr/0004-llm-call-layer-consolidation.md`
> **Code**: `entry/src/main/ets/agentextability/AgentExtAbility.ets` · `entry/src/main/ets/services/ReplyService.ets` · `common/src/main/ets/llm/LlmGuard.ets` · `common/src/main/ets/llm/LlmClient.ets` · `common/src/main/ets/llm/LlmConfig.ets` · `common/src/main/ets/llm/providers.ets` · `common/src/main/ets/llm/ModelCapabilities.ets`
> **Verified by**: 只读源码追踪、`git grep`、连接设备的只读偏好文件读取、DSH 源码只读比对；未修改源码、未提交、未运行 hvigor 构建、未运行端 A2A 冒烟

本文只给小艺端 A2A 的性能修复设计和实机验收协议。所有当前值均来自 checkout 中的代码或一次只读设备读取；目标值标为 `[推导]`，不能当作已经部署的行为。

外部源码引用前缀 `DSH_ROOT` 指向任务书提供并已实际读取的 DSH checkout；后续引用使用相对路径和行号。

外部源码引用前缀 `DSH_ROOT` 指向任务书提供并已实际读取的 DSH checkout；后续引用使用相对路径和行号。

## 0. 一页结论 + 模型适配的结论（含 §0.2 别名表）

当前慢的主因是四层时间预算互相覆盖：小艺扩展先等待配置最多 4 秒，随后以 60 秒的 `Promise.race` 等待一条完整回答；回答内部每次 HTTP 调用的连接和读取 timeout 参数都是 120 秒，JSON 守门最多启动 3 次尝试。简化的模型等待预算是 `[推导]` `3 × 120000 = 360000 ms`，但非流式请求没有单一总时限，因此这不是经 SDK 语义证明的真实硬上限。配置 timeout 获胜后，底层调用没有收到取消信号，仍可能继续占用网络和模型配额。证据：`AgentExtAbility.ets:192-224` — `setTimeout(..., 4000)` / `Promise.race(...)`；`ReplyService.ets:71-76` — `timeoutMs: 120000`；`LlmGuard.ets:69` — `while (attempt <= maxRetries)`。

修复不采用“把默认模型字符串替换成某个 flash 字符串”。提供商本次实测的规范模型 ID 是 `deepseek-flash`；`deepseek-v4-flash` 和 `deepseek-v4-flash-vision-exp` 都是服务端回显为 `deepseek-flash` 的别名。MindTrace 当前既没有 `deepseek-flash`，又会把含 `flash` 且不在旧白名单中的输入抛为 `NORMALIZE_KEYWORD_REJECTED`，证据见 `LlmConfig.ets:619-644`。

方案分三步落地：

1. 将 `providers.ets` 收敛为提供商路由表，将模型 ID、上下文、输出上限、输入模态和推理档位放入可物化的模型清单；目录内 ID 直接使用，别名只在解析表中归一化。
2. 让 `/models` discovery 只返回候选，不覆盖 `vendor_models` / `active_vendor_models` 的用户选择；目录或 discovery 不可用时保留“ID + 原因”，显式回退到该提供商的 catalog 默认。
3. 为 A2A 建立 35 秒端到端 deadline：配置等待 4 秒、一次 25 秒模型尝试、6 秒解析和发送余量；通过 `CancellationToken` 取消 HTTP 请求。`maxTokens` 从清单能力计算，不再把 12000 当作所有任务的请求预算。

本方案当前建议保留 `deepseek-v4-pro` 作为 DeepSeek catalog 的默认规范 ID，直到实机基线证明另一个已发现模型满足质量和速度门槛；这不是将默认值切成 `deepseek-flash`。用户显式选择的模型必须原样保留其意图并在降级时显示原因。

### 0.1 提供商官方清单证据

以下是任务书提供的实时响应原文摘要。命令为：

```bash
curl -s https://api.deepseek.com/models -H "Authorization: Bearer $DEEPSEEK_API_KEY"
```

`[实测·任务书原始输出]` 全量只有两条：

| 响应 `id`（规范 ID） | `name` | `context_window` | `max_output_tokens` | `input_modalities` | `effort` |
|---|---|---:|---:|---|---|
| `deepseek-flash` | DeepSeek-V4.1-Flash | 1048576 | 393216 | `text, image` | `low/high/max`，默认 `high` |
| `deepseek-v4-pro` | DeepSeek-V4-Pro | 1048576 | 393216 | `text` | `low/high/max`，默认 `high` |

本机同命令因代理连接失败，不能把本次会话说成重新拉取了官方清单：`curl: (7) Failed to connect to api.deepseek.com:443 over proxy 127.0.0.1` `[实测]`。因此 §0.1 采信任务书给出的原始输出，重新拉取列入 §8 待核实清单。

### 0.2 别名实测表

`[实测·任务书原始输出]` 对 `POST https://api.deepseek.com/chat/completions` 逐个请求后，HTTP 状态和响应体 `model` 为：

| 请求的 model（别名或规范 ID） | HTTP | 响应体 `model` | 结论 |
|---|---:|---|---|
| `deepseek-v4-flash`（别名） | 200 | `deepseek-flash`（规范 ID） | 服务端规范化 |
| `deepseek-v4-flash-vision-exp`（别名） | 200 | `deepseek-flash`（规范 ID） | 服务端规范化 |
| `deepseek-flash`（规范 ID） | 200 | `deepseek-flash`（规范 ID） | 直接使用 |
| `deepseek-v4-pro`（规范 ID） | 200 | `deepseek-v4-pro`（规范 ID） | 直接使用 |

“换一个写死字符串”与“模型适配”不同：提供商可以改变规范 ID，应用的解析表和清单必须能将别名映射到当前规范 ID，并把能力随清单物化。

## 1. 现状测量与证据

### 1.1 耗时构成

| 阶段 | 当前实现 | 当前数值 | 证据（原文片段） |
|---|---|---:|---|
| A2A 收包和异步派发 | `onData` 解析后调用 `handleQuery`，不等待模型 | 未设上限 | `AgentExtAbility.ets:96-120` — `this.handleQuery(taskId, query);` |
| 配置等待 | `configReady` 与 4 秒 fallback 竞速 | 4000 ms | `AgentExtAbility.ets:192-201` — `setTimeout(..., 4000)` |
| 外层回复兜底 | `Promise.race([this.answerIfConfigured(context), timeout])` | 60000 ms | `AgentExtAbility.ets:215-224` — `REPLY_TIMEOUT_MS` |
| A2A 实际调用 | 扩展直接调用 `ReplyService.complete` | 单次完整 JSON 回答 | `AgentExtAbility.ets:230-242` — `new ReplyService(...).complete(context)` |
| JSON 守门重试 | `while (attempt <= maxRetries)` | 默认 3 次尝试 | `LlmGuard.ets:47-83` — `DEFAULT_MAX_RETRIES = 2` |
| 每次非流式 HTTP | `connectTimeout` 与 `readTimeout` 同为 `timeoutMs` | 120000 ms | `ReplyService.ets:69-80` — `timeoutMs: 120000`；`LlmClient.ets:139-149` — 两个 timeout 字段 |
| 回答发送 | 单帧 task 快照 | 无独立计时 | `AgentExtAbility.ets:250-260` — `sendData(payload)` |

模型端的简化等待预算是 `[推导]` `N × T_attempt = (DEFAULT_MAX_RETRIES + 1) × 120000 = 3 × 120000 = 360000 ms`。`LlmClient.ets:139-149` 同时把 `timeoutMs` 传给 `connectTimeout` 和 `readTimeout`，但 JSON 路径没有额外绝对 deadline，因此 SDK 对两阶段 timeout 的实际总耗时语义需真机确认 `[未核实]`；360000 ms 不能宣称为数学意义上的最坏上限。配置等待若耗尽，用户可见的现有兜底上限约为 `[推导]` `4000 + 60000 = 64000 ms`。这些数字不是实机 P50/P95。

60 秒外层超时不会取消内层调用。`answerWithinTimeout` 没有创建或传入 `CancellationToken`，`answerIfConfigured` 也以无 token 的 `complete` 调用模型；因此超时后底层请求会继续到网络超时或守门结束。`Promise.race` 只会让扩展发送一次“模型响应超时”快照，晚到的 `answerIfConfigured` 结果不会再次触发这个 `race` 的 `.then`，当前路径也没有把它写入聊天存储；但它会继续消耗网络、CPU 和提供商配额。证据见 `AgentExtAbility.ets:215-242`，其中仅有 `Promise.race`、`complete(context)` 和耗时日志。

### 1.2 参数现状表（参数/现值/出处/真机落盘值）

| 参数 | 当前值 | 出处和原文 | 真机落盘值 |
|---|---|---|---|
| DeepSeek 默认模型 | `deepseek-v4-pro`（当前官方规范 ID） | `[源码常量]` `LlmConfig.ets:30-35` — `const DEFAULT_MODEL = 'deepseek-v4-pro'`；`providers.ets:28-36` — `defaultModel: 'deepseek-v4-pro'` | `model=deepseek-v4-pro`、`active_vendor_models.deepseek=deepseek-v4-pro` `[实测]` |
| flash 规范 ID | `deepseek-flash` 未出现在仓库 | `[源码检索]` 全仓 `git grep -n -F deepseek-flash` 无输出；旧别名只在 `LlmConfig.ets:641-643` | 无 |
| A2A `maxTokens` | 12000 | `[源码常量]` `ReplyService.ets:33-35` — `CHAT_REPLY_MAX_TOKENS = 12000`；`ReplyService.ets:69-75` — `maxTokens: CHAT_REPLY_MAX_TOKENS` | `max_tokens=12000.000000` `[实测]` |
| LlmConfig 默认 `max_tokens` | 12000，保存时 clamp 到 1–16000 | `[源码常量]` `LlmConfig.ets:30-35`；`LlmConfig.ets:345-350` — `Math.max(1, Math.min(16000, v))` | 12000 `[实测]` |
| A2A 内层 timeout | 120000 ms | `[源码常量]` `ReplyService.ets:71-76` — `timeoutMs: 120000`；请求体优先使用 request 值，见 `LlmClient.ets:93-109` | `timeout_ms=120000.000000` `[实测]` |
| JSON 守门重试 | `maxRetries=2`，语义是 3 次调用 | `[源码常量]` `LlmGuard.ets:62-83` — `while (attempt <= maxRetries)` | 未落盘，运行时常量 |
| A2A 外层 timeout | 60000 ms | `[源码常量]` `AgentExtAbility.ets:32-35` — `REPLY_TIMEOUT_MS = 60000` | 不落盘 |
| App fallback context window | 65536 tokens | `[源码常量]` `LlmConfig.ets:37` — `DEFAULT_CONTEXT_WINDOW_TOKENS: number = 65536`；缺失时 `LlmConfig.ets:219-228` 返回该值 | `model_context_windows.deepseek::deepseek-v4-pro=65536` `[实测]` |
| 提供商 context window | 1048576 tokens | `[实测·任务书原始输出]` §0.1 | 应由 catalog/discovery 写入能力清单，不应继续用 65536 猜测 |
| 思考默认档 | 提供商响应为 `high`；当前 A2A 请求对 DeepSeek 显式关闭 thinking | `[实测·任务书原始输出]` §0.1；`LlmClient.ets:214-239` — toggle 只在 `request.enableThinking === true` 开启，DeepSeek 否则写 `type: 'disabled'` | 无独立落盘档位 |
| P50/P95 样本 | 当前 `n=0`，不能从 checkout 推出 P50/P95 | `[未核实]` 设备 hilog 读取命令 `hilog -x | grep -i "MindTraceA2A\|LLM 返回"` 当前无输出；仅存在日志格式 | 无 |

`maxTokens` 的赋值链是：A2A `ReplyService` 固定传 12000 → `LlmGuard.toCallRequest` 原样转发 `options.maxTokens` → `LlmClient` 的 request 值优先于 `LlmConfig.getMaxTokens()` → JSON body 写入 `max_tokens`。对应原文分别是 `ReplyService.ets:71-78`、`LlmGuard.ets:236-247`、`LlmClient.ets:93-109`。设置页保存时把当前 `getMaxTokens()` 和 `getTimeoutMs()` 再传给 `saveAll`，没有新的输入控件覆盖这两个值，见 `AiSettingsViewModel.ets:159-165`。

65536 不是 DeepSeek 的当前上下文能力：它是 MindTrace 缺少每模型覆盖时的本地预算默认值。它实际参与笔记上下文预算，`AgentMemoryService.ets:154-164` 把 `safeContextWindowTokens()` 送入 `NoteGenerationContextBuilder`，而 `NoteGenerationContextBuilder.ets:927-934` 再扣除输出、保护和协议预留；A2A `ReplyService.complete` 本身没有把 context window 作为请求字段发送。

## 2. 模型适配分层（L1 提供商 / L2 清单 / L3 能力）

### 2.1 现状与问题（硬编码、白名单、别名）

#### 9 个必核实细节的源码结论

| # | 结论 | 证据（文件:行号；原文不超过两行） | 处理 |
|---:|---|---|---|
| 1 | `deepseek-v4-pro` 的默认值在 `LlmConfig.ets:35` 和 `providers.ets:33`；白名单在 `LlmConfig.ets:642`；UI 预设在 `VendorPicker.ets:24` 和 `ModelSelector.ets:23`；测试断言在 `real-llm-agent-chain.test.mjs:21-28` 与 `llm-config-allow-default-model.test.mjs:70-76`。旧/活动文档还有 ADR、draft spec、研究稿和 legacy handoff 中的历史引用。 | `LlmConfig.ets:35` — `const DEFAULT_MODEL = 'deepseek-v4-pro'`；`VendorPicker.ets:24` — `DeepSeek · deepseek-v4-pro` | 代码默认、UI、测试改为读取 catalog；`docs/legacy/` 冻结历史不改；活动 ADR/research/spec 在实现后改成“规范 ID/别名”术语，避免把历史陈述当现状。 |
| 2 | 白名单是 `isAllowedDeepSeekModel` 的 3 个字符串相等判断；不命中时只要含 `v3`、`flash` 或 `r1` 就抛 `NORMALIZE_KEYWORD_REJECTED`。 | `LlmConfig.ets:619-634` — `lower.indexOf('flash') >= 0` 与 `throw new LlmError(..., 'NORMALIZE_KEYWORD_REJECTED')`；`LlmConfig.ets:640-644` — 三个 `model === ...` | 改为“清单存在即允许 + alias resolver”；`deepseek-flash` 现在不在 3 个相等项中而含 `flash`，所以当前会被拒绝。 |
| 3 | `maxTokens=12000` 直接进入 A2A `ReplyService`；设置页只把已有值回写；LlmConfig 还提供 1–16000 clamp。 | `ReplyService.ets:71-75` — `maxTokens: CHAT_REPLY_MAX_TOKENS`；`AiSettingsViewModel.ets:159-165` — `llm.getMaxTokens()`；`LlmConfig.ets:345-350` — clamp | 用模型清单能力计算 `min(task_need, listing.max_output_tokens)`；`context_window` 独立用于输入预算。 |
| 4 | `DEFAULT_MAX_RETRIES=2` 不是“总共 2 次”，而是 attempt 0、1、2 共 3 次。 | `LlmGuard.ets:62-83` — `while (attempt <= maxRetries)`，成功或 `attempt >= maxRetries` 才退出 | A2A 使用专用一次尝试策略；其他 App 路径先保持现状，避免把 A2A 性能修复扩大成全局可靠性变更。 |
| 5 | 外层 60 秒包住“配置 ready 之后的配置判定 + `ReplyService.complete`”，不包住前置 4 秒等待；没有取消 token。 | `AgentExtAbility.ets:199-224` — `ready.then(... answerWithinTimeout)`；`AgentExtAbility.ets:215-223` — `Promise.race` | 改为从 `onData` 开始的单一 deadline，并把 token 传入 LlmGuard/LlmClient；超时只发一个带 code 的快照。 |
| 6 | `llm_config` 使用 preferences key，没有 `schemaVersion`；当前 key 常量是 endpoint/model/temperature/max_tokens/timeout_ms/enable_thinking/vendor_id/custom_vendor(s)/vendor_models/vendor_api_keys/active_vendor_models/model_context_windows。provider/model registry 现状是 `ProviderConfig` 保存 route 元数据，API key 由 `LlmConfig.getApiKey` 另行读取。 | `LlmConfig.ets:12-28` — key 常量；`LlmConfig.ets:86-158` — `loadAll()` 逐项读取；`providers.ets:18-26` — `ProviderConfig`；`LlmConfig.ets:163-170` — key lookup | 增加版本和显式设置元数据；旧数据按保守规则迁移，不能把非空用户模型覆盖成 catalog 默认；目标 L1 再把 credential resolver 收口到 provider 注册行。 |
| 7 | 小艺扩展和 App 入口分别调用同一 `LlmConfig` preferences store；模型请求层再从该 singleton 读取 vendor/model。 | `AgentExtAbility.ets:77-89` — 扩展进程 `init(this.context)`；`EntryAbility.ets:55-58` — UI 进程 `init(this.context)`；`LlmClient.ets:87-97` — `getApiKey/getModel/getMaxTokens` | 模型清单迁移会同时影响小艺和 App 内聊天；A2A timeout policy 只通过调用选项隔离。 |
| 8 | 当前能力判断不是清单能力：`ModelCapabilities.ets` 按模型名子串把 `deepseek` 判为 toggle、`qwen` 判为 toggle、`o1/o3/reasoner` 判为 always-on。 | `ModelCapabilities.ets:32-70` — `modelLower.indexOf('deepseek')` 等分支；`LlmClient.ets:102-104` 调用 `resolveModelCapability` | 清单字段成为唯一能力来源；保留 vendor/model 仅作查找键，不再作能力判据。 |
| 9 | 当前 A2A 耗时日志只在模型完整返回后打印一次，格式为“字数 + 毫秒”；样本是一次 `ReplyService.complete` 逻辑调用，包含其中可能发生的 JSON 重试/校验，不是单 HTTP attempt，也不是 `onData → sendData` 整链。 | `AgentExtAbility.ets:236-242` — `start=Date.now()`、`complete`、`LLM 返回 ... 耗时 ... ms`；`LlmGuard.ets:69-83` — 重试循环；`AgentExtAbility.ets:250-260` — 发送日志没有耗时 | 先用该格式算现有 complete-chain P50/P95；实现时新增 `a2a_total_ms`、`config_wait_ms`、`llm_attempt_ms`、`send_ms`，按 request ID 关联。 |

全仓 ID 位置的分类结果如下，范围是 `.ets/.json5/.xml/docs/scripts` 的 tracked 文件；`git grep` 没有找到规范 ID `deepseek-flash`。

| 位置 | 分类 | 是否改 | 理由 |
|---|---|---|---|
| `common/src/main/ets/llm/LlmConfig.ets:35` | 默认值 | 改为 catalog fallback lookup | 默认模型不应同时承担白名单和能力定义；保留当前 pro 作为 catalog 默认数据。 |
| `common/src/main/ets/llm/providers.ets:7,33` | 提供商注释/默认值 | 改表结构；模型默认移入 catalog | L1 只负责 vendor 路由，L2 负责模型清单。 |
| `common/src/main/ets/llm/LlmConfig.ets:641-643` | 白名单 | 删除字符串白名单，改 resolver | 允许提供商新规范 ID；当前 canonical `deepseek-flash` 会被旧 keyword guard 拒绝。 |
| `entry/src/main/ets/pages/AiSettings/VendorPicker.ets:23-28` | UI 预设 | 改为 provider/catalog 渲染 | UI 不再复制模型 ID。 |
| `entry/src/main/ets/services/ModelSelector.ets:22-29` | UI label map/default label | 改为清单 `name`，未知 ID 保留原文 | 显示名称跟随 discovery，不能用静态 map 猜型号。 |
| `scripts/arkts-lint/tests/real-llm-agent-chain.test.mjs:20-29` | 旧默认/白名单测试 | 改为 catalog + alias 断言 | 现有测试会把旧字符串继续锁死。 |
| `scripts/arkts-lint/tests/llm-config-allow-default-model.test.mjs:57-81` | keyword guard 测试 | 改为 canonical/alias resolver 测试 | 不再测试 `flash` 子串白名单。 |
| `docs/specs/016-llm-settings-redesign.md:14,86`、`docs/adr/0015-structured-stream-events.md:3`、`docs/research/agent-float-window-component-research-2026-09-11.md:11,141`、`docs/research/agent-reasoning-process-display-research-2026-09-11.md:11,55-56,288,339` | 活动/草稿/研究陈述 | 实现后修正措辞 | 这些文档描述旧模型或历史行为；例如 draft spec 明写“pro 不存在”，与本任务书官方响应和当前 API 实测冲突。 |
| `docs/legacy/mindtrace/**` 中的 handoff/competition 文档 | 冻结历史证据 | 不改 | AGENTS.md 将 `docs/legacy/` 定义为冻结历史；在本计划中标注其历史性质即可。 |

为避免把“全部位置”压缩成一个 glob，下面是本次 `git grep` 对三个非规范/规范 ID 的逐文件行号清单；同一文件同一命中行只列一次。`.json5` 和 `.xml` 没有命中。

| ID | 全部 tracked 命中（文件:行） | 类型与处理 |
|---|---|---|
| `deepseek-v4-pro` | `common/src/main/ets/llm/LlmConfig.ets:35,642`；`common/src/main/ets/llm/providers.ets:7,33`；`entry/src/main/ets/pages/AiSettings/VendorPicker.ets:24`；`entry/src/main/ets/services/ModelSelector.ets:23`；`scripts/arkts-lint/tests/real-llm-agent-chain.test.mjs:21,22,27`；`docs/adr/0015-structured-stream-events.md:3`；`docs/specs/016-llm-settings-redesign.md:14,86`；`docs/research/agent-float-window-component-research-2026-09-11.md:141`；`docs/research/agent-reasoning-process-display-research-2026-09-11.md:11,55,56,288,339`；`docs/legacy/mindtrace/competition/references-2026-07-26.md:35`；`docs/legacy/mindtrace/handoffs/llm-settings-scope-2026-09-06.md:119,121,172,198,199,200,230`；`docs/legacy/mindtrace/handoffs/llm-settings/pr0-fix-pro-model.md:49,50,51`；`docs/legacy/mindtrace/handoffs/llm-settings/pr2-t1-llm-config-data.md:25` | 代码默认/提供商默认/白名单/UI/测试：改为 catalog/resolver；ADR、研究和 draft：实现后修订；legacy：不改。代表原文：`LlmConfig.ets:35` — `const DEFAULT_MODEL = 'deepseek-v4-pro'`。 |
| `deepseek-v4-flash` | `common/src/main/ets/llm/LlmConfig.ets:641`；`scripts/arkts-lint/tests/llm-config-allow-default-model.test.mjs:70`；`scripts/arkts-lint/tests/real-llm-agent-chain.test.mjs:26`；`docs/legacy/mindtrace/handoffs/llm-settings-scope-2026-09-06.md:118`；`docs/legacy/mindtrace/handoffs/note-generation-fix-handoff-2026-09-20.md:54` | 旧 alias 白名单/测试：改 resolver 与测试；legacy：不改。代表原文：`LlmConfig.ets:641` — `model === 'deepseek-v4-flash'`。 |
| `deepseek-v4-flash-vision-exp` | `common/src/main/ets/llm/LlmConfig.ets:643`；`scripts/arkts-lint/tests/llm-config-allow-default-model.test.mjs:75`；`scripts/arkts-lint/tests/real-llm-agent-chain.test.mjs:28`；`docs/legacy/mindtrace/handoffs/llm-settings-scope-2026-09-06.md:120` | 旧 alias 白名单/测试：改 resolver 与测试；legacy：不改。代表原文：`LlmConfig.ets:643` — `model === 'deepseek-v4-flash-vision-exp'`。 |
| `deepseek-flash` | 无命中 | 当前 canonical ID 尚未进入 catalog、UI、配置或测试；新增到 catalog/alias 验收，而不是新增 keyword 白名单。 |

### 2.2 目标分层

目标链路如下；括号内是实现落点，新增文件名是计划名，当前不存在的文件均标为 `[新增]`：

```text
vendor route (providers.ets, L1)
  -> catalog defaults + user overrides (model-catalog.ets [新增] + LlmConfig.ets)
  -> discovery candidates (model-discovery.ets [新增], only unknown route)
  -> alias resolver (model-resolver.ets [新增])
  -> capability policy (ModelCapabilities.ets)
  -> request builder (LlmClient.ets)
  -> AgentExtAbility single task snapshot
```

#### L1 提供商

`common/src/main/ets/llm/providers.ets` 是唯一 vendor 入口：每行声明 `id`、`baseUrl`、`protocolKind` 和凭据解析方式；现有接口已经有 `id/baseUrl/protocolKind` 字段，见 `providers.ets:18-26` 的 `ProviderConfig`。请求层只按 protocol adapter 调用，不写 `if (vendorId === ...)` 分支。新增提供商只新增一条 provider registry 记录；它的模型和能力进入 L2 catalog。这是目标设计 `[推导]`，由现有 provider 表的集中结构支撑。

#### L2 模型清单

优先级和落盘策略固定为：

1. **内置 catalog**：每个 provider 的默认模型条目携带规范 ID、显示名、`context_window`、`max_output_tokens`、`input_modalities`、`effort.supported_levels` 和 `default_effort`。它是离线可用的默认能力。
2. **运行时 discovery**：只有 catalog 不认识的 route 才请求 `{baseURL}/models`；解析 `data[]` 和网关的 `models{}`，结果只作为设置页候选，不覆盖当前选择，也不写入 preferences。网络失败时返回诊断并继续使用内置 catalog，不能因为 discovery 失败禁用模型。
3. **用户覆盖**：用户确认候选后才写 `vendor_models` 和 `active_vendor_models`；这两个 key 已由 `LlmConfig.ets:22-28` 定义，读取优先级见 `LlmConfig.ets:293-304` 的 active → userModels → provider default。

DSH 样板把同一边界写得很清楚：catalog route 不发网络、discovery 结果不落库，见 `DSH_ROOT/packages/llm/llm-pi-ai/src/discovery.ts:5-14`（“catalog is authoritative”“Nothing here is stored”）；catalog route 直接返回带容量和输入模态的候选，见 `discovery.ts:273-285`。MindTrace 应照这个形状实现，但协议仍是当前 provider 表声明的 OpenAI-compatible，不能照搬只接受 Anthropic Messages 的谓词。

#### L3 能力推导

请求参数必须由已解析条目计算：

```text
maxTokens = min(task_need, listing.max_output_tokens)
inputBudget = min(context_window * 0.7,
                  context_window - output_reserve - safety_reserve)
effort = requested_effort if it is in effort.supported_levels
         else listing.default_effort
image request is allowed only when input_modalities contains image
```

其中 `task_need` 是任务策略的预算，不是提供商能力；本方案 A2A 初始值为 4096 `[推导]`。官方清单给出的 `max_output_tokens=393216`，所以当前两条规范 ID 的初始 A2A 值都为 `[推导]` `min(4096,393216)=4096`；若 discovery 返回更小上限，自动取更小值。`context_window`、`input_modalities` 和 effort 不再从模型名子串推断。

DSH catalog 的字段覆盖顺序可直接作为实现形状：`catalog.ts:926-940` 先取 entry override，再取 built-in，再取 route default；其中 `contextWindow` 和 `maxTokens` 都是逐字段合并。DSH 的 model 集合再从 catalog 拼 provider/model，见 `models.ts:32-52`。

### 2.3 别名与规范化

解析表初始内容：

| 输入 | 类型 | 解析结果 | 发送值 |
|---|---|---|---|
| `deepseek-flash` | 规范 ID | `deepseek-flash` | `deepseek-flash` |
| `deepseek-v4-flash` | 别名 | `deepseek-flash` | `deepseek-flash` |
| `deepseek-v4-flash-vision-exp` | 别名 | `deepseek-flash` | `deepseek-flash` |
| `deepseek-v4-pro` | 规范 ID | `deepseek-v4-pro` | `deepseek-v4-pro` |

解析步骤必须先查“当前清单 ID”，再查 alias map；清单中直接存在的 ID 不做二次猜测。未知 ID 进入 discovery/strict 校验，不能凭 `flash`、`v3`、`r1` 等子串决定合法性。旧配置迁移时，两个 flash 别名归一化到 `deepseek-flash`，但用户显式选择的意图和降级原因要记录。

DSH 的 `listing.ts:29-44` 保留 `{usable:false, reason}` 的 ID/name；`resolve-catalog.ts:113-124` 对不可用条目记录 `problems` 和 `refusals`，不会静默换型号。MindTrace 的 DeepSeek 解码器应保留这个语义，但可用性谓词要按 OpenAI-compatible `input_modalities`、容量和 effort 字段判断；DSH 现有 `listing.ts:88-99` 要求 `api_capabilities.anthropic_messages`，与 `providers.ets:15` 的 OpenAI-compatible 现状不相符，不能原样复制。

### 2.4 漂移闸与降级

能力枚举和模态枚举分别用 `Record<Union, true>` 全量列出。DSH 的 `MODALITY_GATE` 在 `catalog.ts:43-54`，`THINKING_LEVEL_GATE` 在 `catalog.ts:69-85`；其原文明确说上游增删 key 会编译失败而不是静默收窄。MindTrace 的目标是 `const MODALITY_GATE: Record<ModelModality, true>` 和 `const EFFORT_GATE: Record<ModelEffort, true>`，上游增加 `audio` 或新的 effort 时必须先更新 decoder、catalog 和请求层。

降级有三种可观察结果：

- discovery 拉不到：保留 catalog，日志 `MODEL_DISCOVERY_FALLBACK`，不改变用户选择；
- 用户选择的条目存在但能力 `usable:false`：返回该 ID 和原因，记录 `MODEL_UNUSABLE`，再使用同 provider catalog 默认，并在 A2A 回复中追加“已降级：<id> / <reason>”；
- alias 未知或严格写入不可服务：返回 `MODEL_ID_UNRESOLVED`，不把它静默改成另一个 ID。

strict/deferred 两级解析照 DSH：写配置前 strict 直接拒绝，存量读取 deferred 保留 diagnostics。证据是 `catalog.ts:849-860` 的 validation 参数、`catalog.ts:869-886` 的 strict 抛错/deferred `modelErrors`，以及 `config.ts:402-413` 的“stored reads retain catalog diagnostics”。

## 3. 改动清单

| 文件:行 | 现值原文 | 目标值 | 理由 | 影响面 |
|---|---|---|---|---|
| `common/src/main/ets/llm/providers.ets:18-26,28-37` | `defaultModel: string`；DeepSeek 行为 `defaultModel: 'deepseek-v4-pro'` | provider 行只保留 route/baseURL/protocol/key resolver；默认模型移入 catalog | L1/L2 分离；增加 provider 只加 registry 行 | `LlmConfig.getModel`、设置页、所有模型请求 |
| `common/src/main/ets/llm/LlmConfig.ets:12-37,86-158` | key 常量和默认值没有 `schemaVersion` | 加 `schemaVersion`、`model_source`/显式设置标记、迁移函数；保留未知旧 key | 能区分缺省和用户选择，迁移可幂等 | 两个进程的 preferences 读取 |
| `common/src/main/ets/llm/LlmConfig.ets:605-644` | `isAllowedDeepSeekModel` + `indexOf('flash')` keyword reject | alias resolver + catalog ID lookup；未知 ID 进入 strict/deferred | 允许提供商改规范 ID，修复 canonical `deepseek-flash` 被拒 | 设置保存、启动加载、A2A/App 共用配置 |
| `common/src/main/ets/llm/model-catalog.ets` `[新增]` | 文件当前不存在 `[未核实]` | 内置 provider/model/能力条目、默认 effort、模型显示名 | L2 离线真源；不把能力藏在请求层 | LlmConfig、设置页、LlmClient |
| `common/src/main/ets/llm/model-discovery.ets` `[新增]` | 文件当前不存在 `[未核实]` | 只对 catalog 不认识的 route GET `/models`；4 MiB 超限拒绝；不落盘 | 对齐 DSH discovery 边界 | 设置页候选、诊断日志 |
| `common/src/main/ets/llm/model-resolver.ets` `[新增]` | 文件当前不存在 `[未核实]` | 先清单 ID、后 alias；返回 `{id, canonicalId, usable, reason}` | 规范 ID/别名不混用，保留不可用原因 | 所有请求和迁移 |
| `common/src/main/ets/llm/ModelCapabilities.ets:25-70` | 按 `modelLower.indexOf('deepseek')`、`qwen`、`reasoner` 推导 | 按 resolved listing 读取 modalities/context/max output/efforts | 能力随清单更新，不依赖名称 | LlmClient JSON/SSE、图像输入门控 |
| `common/src/main/ets/llm/LlmClient.ets:93-109,325-349` | request 值或 LlmConfig 值直接写 `max_tokens`; thinking 用模型名辅助判断 | 接收 `ResolvedModel`; `maxTokens=min(taskNeed,maxOutput)`；effort 只取 supported levels；取消时销毁 request | 参数与能力一致，避免 12000/65536 猜测 | JSON 与 SSE 两条 transport |
| `common/src/main/ets/llm/LlmGuard.ets:42-85` | `DEFAULT_MAX_RETRIES=2`，默认 3 次 | A2A policy 显式传 `maxRetries: 0`；App 内聊天暂保留 2 | A2A 受 deadline 约束，避免 3×120 秒尾部工作 | 小艺链路；App 聊天不立即改变 |
| `entry/src/main/ets/services/ReplyService.ets:33-80,104-125` | `CHAT_REPLY_MAX_TOKENS=12000`、`timeoutMs=120000`，stream 也固定 120000 | 接受 `LlmCallPolicy`；A2A complete 使用 task budget/25s/0 retry；普通聊天显式保留现策略直到另一次基线 | 把性能修复限定在 A2A | A2A 与 App 内聊天的行为差异可观测 |
| `entry/src/main/ets/agentextability/AgentExtAbility.ets:32-35,184-242` | 4 秒配置等待、60 秒 `Promise.race`、无 token 的 `complete` | 单一 35 秒 deadline 覆盖配置等待；创建 token；deadline 时取消 HTTP；日志 code 化 | 消除外层/内层矛盾和过期请求 | 小艺扩展进程；单帧 task 形状不变 |
| `entry/src/main/ets/viewmodels/AiSettingsViewModel.ets:116-165` | 保存循环写 `vendor_models`/`active_vendor_models`，最后回写旧 max/timeout | 发现候选供用户确认；只有确认才写覆盖；迁移保留显式选择 | discovery 不覆盖用户选择 | 设置页、preferences |
| `entry/src/main/ets/pages/AiSettings/VendorPicker.ets:23-28` | 注释内复制 5 个硬编码模型 ID | 由 provider/catalog 渲染名称、规范 ID、不可用原因 | UI 不再制造第二份清单 | 设置页显示 |
| `entry/src/main/ets/services/ModelSelector.ets:22-29` | `LABEL_MAP` 只认识旧 pro ID | 使用 listing `name`；未知保留原 ID | 提供商清单可演进 | UI Chip |
| `scripts/arkts-lint/tests/real-llm-agent-chain.test.mjs:20-29`、`llm-config-allow-default-model.test.mjs:57-81` | 断言旧 pro/两个旧 flash 别名和 keyword guard | 测试 catalog 默认、alias→canonical、canonical flash 不被拒、strict/deferred 和 fallback | 防止旧测试把错误前提锁回去 | lint 测试 |
| 活动文档 `docs/specs/016...`、`docs/adr/0015...`、两份 `docs/research/...` | 文档仍出现旧模型假设 | 实现后逐条标注规范 ID/别名；legacy 保持冻结 | 文档不再把历史响应当当前事实 | 文档追溯 |

## 4. 超时与重试的层级对齐

### 4.1 现在为什么矛盾

现有关系是 `[推导]`：

```text
config wait <= 4s
outer visible timeout = 60s (starts after config race)
inner request timeout = 120s per attempt
attempts = 2 retries + 1 first call = 3
worst in-flight model time = 3 * 120s = 360s
```

因此外层 60 秒不能保护网络资源，只能提前发超时快照。它还没有覆盖配置 race 的 4 秒，所以从 `onData` 到用户看到 timeout 的理论上限是 `[推导]` 64 秒；真正的内层 HTTP 仍可能继续约 296 秒以上。相关原文见 `AgentExtAbility.ets:192-224`、`ReplyService.ets:69-76` 和 `LlmGuard.ets:69-83`。

当前超时路径没有把 `CancellationToken` 传到 `ReplyService.complete`；虽然 `LlmClient` 已经支持取消监听并在取消时 `destroy()`，证据是 `LlmClient.ets:135-157` 和 `CancellationToken.ets:24-45`，A2A 没有使用这个 seam。

### 4.2 目标数字 + 算式

以下是第一版可执行的 A2A policy，所有数字为 `[推导]`，需要 §6 真机样本校准：

| 量 | 目标 |
|---|---:|
| `T_config` | 4000 ms，沿用当前配置等待上限 |
| `N_attempts` | 1（`maxRetries=0`） |
| `T_inner` | 25000 ms，传给 `connectTimeout` 和 `readTimeout` |
| `T_backoff` | 0 ms（无第二次尝试） |
| `T_parse+send_margin` | 6000 ms |
| `T_a2a_deadline` | 35000 ms，从 `onData` 收到有效 query 开始计时 |
| A2A `task_need` | 4096 output tokens |

自洽关系是 `[推导]`：

```text
T_a2a_deadline
  >= T_config + N_attempts * (T_inner + T_backoff) + T_parse+send_margin
  = 4000 + 1 * (25000 + 0) + 6000
  = 35000 ms
```

请求预算则是 `[推导]` `maxTokens = min(4096, listing.max_output_tokens)`；任务书官方响应的两条模型都给出 393216，所以目录初始值为 4096，而不是继续固定 12000。上下文预算用 `listing.context_window`；官方值为 1048576，输入预算仍需扣除输出和协议预留，不能把 `max_tokens` 当作输入窗口。

A2A deadline 必须通过同一个 token 取消 `LlmGuard` 和 `LlmClient`。如果 `input_modalities` 不含 image，图像请求在能力层拒绝并返回 ID/原因；如果模型是 toggle 且任务策略关闭 thinking，则写关闭字段；如果模型是 always-on，则不写 disabled。supported effort 不包含请求档位时使用 listing 的 `default_effort`，官方响应给出的默认是 `high`。这些分支来自目标清单字段，不再来自 `ModelCapabilities.ets` 的名称子串。

普通 App 内聊天仍保留当前 120000/2-retry 策略，直到它有独立基线；这是为了避免 A2A 的时间预算调整改变 UI 流式和笔记生成路径 `[推导]`。两侧仍共享同一 vendor/model preferences，因此模型选择和 catalog 迁移的影响面相同。

### 4.3 失败语义与日志 code

目标日志采用稳定 code（`[推导]`，当前代码只有中文日志，见 `AgentExtAbility.ets:195-220`）：

| code | 触发 | 用户/小艺行为 |
|---|---|---|
| `A2A_CONFIG_READ_TIMEOUT` | 配置读取达到 4 秒 | 返回配置不可用的 task；不把它当模型超时 |
| `A2A_MODEL_UNUSABLE` | 清单有 ID 但能力 `usable:false` | 返回 ID + 原因；按 catalog 默认显式降级并标注 |
| `A2A_MODEL_ID_UNRESOLVED` | alias/ID 不在清单，strict 写入失败 | 不静默替换，返回 ID + 解析原因 |
| `A2A_LLM_TIMEOUT` | 单次 25 秒连接/读取超时 | 发送 timeout task；不启动隐藏第二次调用 |
| `A2A_DEADLINE_EXCEEDED` | 35 秒总 deadline 触发 | 取消 token、销毁 HTTP、只发送一次 timeout task |
| `A2A_REPLY_SENT` | 单帧 task 成功发送 | 记录 `requestId/taskId/model/canonicalId/elapsedMs` |

每条错误都要保留 `requestedModel`、`canonicalModel`、`reason` 和 `attempts`；不得用另一个型号替换后只记录“成功”。

## 5. 旧配置迁移

### 5.1 现状（含读取命令与真机输出）

源码只声明 `STORE_NAME='llm_config'` 和字段 key，没有版本字段，见 `LlmConfig.ets:12-28`。`loadAll()` 在 `LlmConfig.ets:86-158` 逐项从 preferences 取值；缺省值通过 `get(key, default)` 或 cached defaults 提供。`model` 会立刻进入 `normalizeModel`，所以存入 canonical `deepseek-flash` 的旧设备在当前版本初始化时也会走旧 keyword guard。

读取命令（设备路径按用户给定 bundle）：

```powershell
$HDC = "$env:DEVECO_SDK_HOME\openharmony\toolchains\hdc.exe"
& $HDC shell "ls -l /data/app/el2/100/base/com.example.mindtrace/haps/entry/preferences/llm_config.xml /data/app/el2/100/base/com.example.mindtrace/haps/entry/preferences/llm_config"
& $HDC shell "cat /data/app/el2/100/base/com.example.mindtrace/haps/entry/preferences/llm_config"
```

`[实测]` 当前连接设备的输出是：

```text
ls: .../preferences/llm_config.xml: No such file or directory
-rw-rw---- ... 914 ... .../preferences/llm_config
```

因此任务书中的 `.xml` 是逻辑命名，实际文件没有 `.xml` 后缀。脱敏后的内容关键项为 `[实测]`：

```xml
<string key="endpoint">https://api.deepseek.com</string>
<string key="model_context_windows">{"deepseek::deepseek-v4-pro":65536}</string>
<string key="vendor_id">deepseek</string>
<string key="vendor_models">{"deepseek":["deepseek-v4-pro"], ...}</string>
<string key="vendor_api_keys">[REDACTED]</string>
<string key="active_vendor_models">{"deepseek":"deepseek-v4-pro"}</string>
<string key="model">deepseek-v4-pro</string>
<double key="timeout_ms" value="120000.000000"/>
<double key="max_tokens" value="12000.000000"/>
```

读取输出包含 API key；本文只保留 `[REDACTED]`，不把原始凭据写入仓库、日志或验收附件。

### 5.2 机制与幂等

新增 `schemaVersion`（整数）和 `model_source`/`explicit_model` 元数据 `[推导]`。启动顺序：读取 raw preferences → 先做版本迁移 → alias 解析 → strict/deferred catalog 校验 → 写回一次完整迁移结果。`schemaVersion` 已是新版本时不重复写；迁移成功后 `flush()`，重启结果不变。

旧数据规则 `[推导]`：

1. `active_vendor_models[vendor]` 非空，或 `vendor_models[vendor]` 含该 ID：判为用户显式选择，保留选择并只做别名到规范 ID 的可逆记录。
2. `model` 非空但没有显式元数据：不覆盖；如果它是已知 alias，写入 canonical ID 并保留 `requested_alias`；如果是未知 ID，保留原值并产生 deferred diagnostic。
3. `model` 缺失或空字符串：使用 provider catalog 默认；当前 DeepSeek catalog 默认数据为 `deepseek-v4-pro`，不是把它从旧文档中的“默认值”复制到白名单。
4. `model_context_windows` 的 65536 只当旧用户覆盖；没有该 key 时从 listing/catalog 的 `context_window` 初始化，不能把 65536 宣称为提供商能力。

### 5.3 用户显式设置保护

当前设置页会读取 vendor models、active model 和 context windows，见 `AiSettingsViewModel.ets:77-88`；保存时逐项写回，见 `AiSettingsViewModel.ets:121-165`。因此迁移不能用“等于旧默认字符串”作为唯一显式判据：用户也可能显式选择过旧默认。保护规则是“非空 active/vendor 列表优先；无法判定时保留原值并报告诊断”，而不是静默改成 flash 或 catalog 的另一个型号 `[推导]`。

### 5.4 失败回退

迁移 JSON 解析、alias 解析或 catalog strict 校验失败时，保留 raw key、回退到内置 catalog 的可服务默认，并记录 `LLM_CONFIG_MIGRATION_FAILED` 和原始 ID/原因；不得删除 API key、不得把用户模型替换成另一个型号后伪装成功 `[推导]`。这与 DSH deferred 读取保留 diagnostics 的形状一致，证据见 `DSH_ROOT/packages/llm/llm-pi-ai/src/config.ts:402-413` 和 `index.ts:164-174`。

## 6. 验收协议

### 6.1 方法

每个模型/配置组合在同一设备、同一网络、同一账号和同一输入下做冷启动 10 次 + 热启动 10 次，合计 `n≥20`；先采集现状版本，再采集修复版本。`[推导]` 20 是最低样本量，低于此值只记录观察值，不判 P50/P95 通过。

组合至少包括：

- `deepseek-v4-pro`（规范 ID）；
- `deepseek-flash`（规范 ID）；
- `deepseek-v4-flash`、`deepseek-v4-flash-vision-exp`（别名，确认请求和回显 canonical ID）；
- 用户自定义 provider 的 catalog 命中与 discovery 命中各一组；
- 设置页已有显式模型和无模型的迁移前后各一组。

输入固定为 `整理数学题`，每次请求前清除小艺旧会话或使用脚本默认重启；脚本默认等待回复 45 秒，见 `scripts/a2a-smoke/a2a_smoke.py:250-260` 的 `wait_reply(..., timeout=45.0)`。不要把历史气泡作为回复样本。

### 6.2 命令

设备前置检查：

```powershell
$HDC = "D:\HarmoNova\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
& $HDC list targets
```

端 A2A 链路命令（每轮保存 JSON；本方案未运行）：

```powershell
$env:HDC = $HDC
python scripts/a2a-smoke/a2a_smoke.py --text "整理数学题" | Tee-Object .tmp-xiaoyi-run.json
```

脚本会自动拉起小艺、进入智能体、输入文本、轮询布局并抓 `MindTraceA2A` 日志；其输出字段含 `ok`、`reply_text`、`foreground`、`hilog`，见 `scripts/a2a-smoke/README.md` 的用法和输出表。

采集当前耗时日志（当前格式）：

```bash
hdc shell 'hilog -x | grep -i "MindTraceA2A\|LLM 返回"' > hilog-xiaoyi.txt
```

从当前 `LLM 返回 ... 耗时 ... ms` 日志计算 P50/P95（POSIX awk/sort）：

```bash
grep 'LLM 返回' hilog-xiaoyi.txt \
  | sed -n 's/.*耗时 \([0-9][0-9]*\) ms.*/\1/p' \
  | sort -n > llm-ms.sorted
awk '{ v[NR]=$1 } END {
  n=NR; p50=int(0.50*n+0.999999); p95=int(0.95*n+0.999999);
  if (n==0) { print "n=0 P50=NA P95=NA"; exit }
  print "n=" n, "P50_ms=" v[p50], "P95_ms=" v[p95]
}' llm-ms.sorted
```

当前日志的样本是单次 `ReplyService.complete` 的模型段，不是整条 `onData → sendData`，证据见 `AgentExtAbility.ets:236-242`。修复实现必须再输出 `a2a_total_ms=... config_wait_ms=... llm_attempt_ms=... send_ms=...`，并用同一 awk 模板分别计算四列；`requestId` 和 canonical model 不能缺失。

### 6.3 checkbox

- [ ] `hdc list targets` 只有目标测试设备，设备已解锁；脚本前置条件见 `scripts/a2a-smoke/README.md`。
- [ ] 每个组合 `n≥20`，JSON 中每轮 `ok:true`，`reply_text` 非空，未把 timeout 文案当成功回答。
- [ ] 每轮的 requested ID、canonical ID、provider、effort、maxTokens、attempts 和四段耗时均可从 JSON/hilog 对齐。
- [ ] `deepseek-flash` 不再触发 `NORMALIZE_KEYWORD_REJECTED`；两个旧 flash 别名回显为 canonical `deepseek-flash`。
- [ ] discovery 网络失败时仍能用内置 catalog；用户没有确认候选前，`vendor_models` 和 `active_vendor_models` 不改变。
- [ ] 不可用条目展示“ID + 原因”；降级到 catalog 默认时回复/日志含 `degraded` 和原因，没有静默换型号。
- [ ] A2A policy 的 `maxTokens = min(task_need, listing.max_output_tokens)`；官方两条清单的初始 task budget 为 4096 `[推导]`。
- [ ] 35 秒 deadline 到达时 HTTP 被取消，之后没有同一 request 的晚到 `LLM 返回` 或第二个 task snapshot。
- [ ] P50/P95 在每个组合都由排序样本计算；初始建议门槛 `[推导]`：`P50(T_a2a_total) ≤ 8s`、`P95(T_a2a_total) ≤ 25s`、超时率 0、P99 不超过 35s deadline。
- [ ] 配置迁移重复执行不改变 canonical ID、显式用户模型、API key 和 context override；无 schemaVersion 的旧设备能回到 catalog 默认。
- [ ] 端到端命令最终输出 `ok:true` 后，才可以在交付记录写端 A2A 可用；本方案当前没有运行该命令，不能宣称已通。

### 6.4 本方案不改善什么

- 提供商排队、模型服务端首 token、蜂窝/Wi-Fi RTT：这些不由仓库代码决定，必须从 `llm_attempt_ms` 与服务端响应时间另行测量 `[未核实]`。
- App 内流式 UI 的逐 token 渲染：A2A 当前走 `ReplyService.complete` 而非 `ReplyService.stream`，证据见 `AgentExtAbility.ets:236-242` 和 `ReplyService.ets:84-125`。
- OCR、图片识别和笔记生成质量：A2A 当前 `ReplyContext` 的 memory/evidence 为空，且直接构造 `IntentClassifier`，见 `AgentExtAbility.ets:184-191,230-242`。
- 模型回答的正确性和知识内容：本方案只约束 ID、能力、预算、超时和回执，不改变提示词或事实校验。

## 7. 风险与回滚

1. **提供商字段漂移**：`/models` 可能使用 `context_window`、`context_length` 或网关嵌套字段。按 DSH 的多别名容量解析形状（`discovery.ts:207-220`）实现；未知字段只保留 ID，不猜能力。回滚是关闭 discovery 开关并使用已发布 catalog。
2. **规范 ID 再次变化**：alias 表和 catalog 版本化；旧配置保留 requested ID/原因，重新 discovery 后再由用户确认。回滚只恢复旧 resolver，不删除 preferences。
3. **25 秒过短**：以配置开关恢复 A2A policy 的 60 秒 deadline 和当前 `maxRetries=2`，但必须同时记录超时尾部工作；不得只调大外层数字而继续留下无取消请求。
4. **取消不及时**：若设备证明 `httpRequest.destroy()` 后仍有晚到回调，先保留单帧 response guard，再增加 request generation；不允许旧请求写 UI/发送第二个 task。现有 HTTP 取消接线见 `LlmClient.ets:420-429`。
5. **迁移覆盖显式选择**：迁移前复制脱敏 key 列表、model、active/vendor maps 和 schemaVersion；失败时保留 raw preferences，按 §5.4 回退。测试中必须验证“显式选旧默认”与“未配置默认”两个不同样本。
6. **凭据暴露**：设备偏好读取结果必须脱敏；本次只读输出已发现 `vendor_api_keys` 字段，本文不保存其值。任何真实 key 进入日志后都应由凭据持有人轮换，不能把轮换动作伪装成代码回滚。

## 8. 待核实清单

| 待核实项 | 为什么要紧 | 用哪条命令或读哪个文件能定 | 结论相反时方案怎么变 |
|---|---|---|---|
| 官方 `/models` 在当前网络重新返回的完整 payload | 任务书清单可能随提供商改版；本机 curl 受代理失败 | `curl -s https://api.deepseek.com/models -H "Authorization: Bearer $DEEPSEEK_API_KEY"`；保存脱敏 JSON | 更新 catalog decoder、能力枚举和 alias map；不恢复字符串白名单 |
| `deepseek-v4-flash` / `vision-exp` 在当前账号的 chat 回显 | 别名是否仍规范化到 `deepseek-flash` 决定迁移和回执断言 | 用安全短 prompt POST `/chat/completions`，记录 HTTP 和响应 `model`，不记录 key | 若别名失效，迁移保留 ID+原因并要求用户重新选择；不静默换 pro |
| 真机 A2A P50/P95 和样本量 | 当前 checkout 没有 hilog 样本，不能证明 8/25 秒门槛 | `python scripts/a2a-smoke/a2a_smoke.py --text "整理数学题"` ×20；按 §6.2 awk/sort | 用实测 P95 重新求 `T_inner`，保持 `T_deadline ≥ T_config + N*T_inner + margin` |
| 配置读取、模型 HTTP、task send 的分段耗时 | 当前只记录模型段，无法定位 60 秒外的空洞 | 修复后读取 `config_wait_ms/llm_attempt_ms/send_ms/a2a_total_ms`；当前代码起点 `AgentExtAbility.ets:236-260` | 若 config 或 send 占比高于模型，独立优化该段，不调模型字符串 |
| 取消是否真的阻断 late HTTP 回调 | `Promise.race` 当前不取消，设备网络栈行为不能静态证明 | deadline 触发后抓 `hilog -x`，核对同 request 是否还有 `LLM 返回`/`task snapshot sent` | 若仍有 late callback，增加 generation guard 和连接销毁确认，再开放 35 秒门槛 |
| 旧设备的 `active_vendor_models` 是否代表用户显式选择 | 没有 schemaVersion 时不能从一个 `model` 字符串区分默认/显式 | 读取脱敏 `llm_config`，比较 `vendor_models`、`active_vendor_models`、`model` 的组合；看 `AiSettingsViewModel.ets:77-88` | 结论不确定时保留非空 ID，并记录 deferred diagnostic，禁止覆盖 |
| 平台重新导入 AgentCard、重启小艺后是否读取新配置 | A2A 配置变更有平台缓存；本方案未运行平台链路 | 按 `docs/agents/phase-tracker.md` 的 P0 流程重新导入、重启、再跑脚本 | 若仍报旧能力，先处理平台缓存/AgentCard，不修改模型 policy 猜测 |

## 9. 无法静态确认（需真机验证）

- 任何 P50/P95、首字节时间、服务端排队时间和网络 RTT；当前只有源码上限，没有样本。
- `deepseek-flash` 的真实 OpenAI-compatible 请求是否接受 `thinking`、effort 和图片模态字段组合；清单声明能力不等于本设备请求已验收。
- `CancellationToken.cancel()` 到 HarmonyOS `httpRequest.destroy()` 的实际终止延迟；代码只证明调用链存在，不能证明设备网络栈已经停止。
- 小艺在收到单帧 task 后的最终渲染时间和 `reply_text` 去噪结果；脚本的 `wait_reply` 只证明可观察文本差集，不证明服务端任务耗时。
- 迁移后两个独立进程是否在重启边界都看到相同 canonical ID；需要扩展进程和 UI 进程分别打印配置快照。

## 10. 自检

- [x] 已按任务书结构覆盖 §0–§10；§3 每行现值来自仓库原文或明确标 `[新增]/[未核实]`。
- [x] 已核实 9 个必查细节，包含模型位置、白名单/异常、maxTokens/context、重试、外层取消、llm_config、双进程读取、能力判断和 P50 日志。
- [x] 全文模型名区分规范 ID 与别名；`deepseek-flash` 的当前缺失和旧 alias 的旧白名单位置均已写明。
- [x] DSH catalog/discovery/listing/resolve/models 样板已实际读取并按文件:行号引用；Anthropic-only listing 谓词未直接移植到 MindTrace。
- [x] 目标参数给出算式：`4000 + 1×(25000+0) + 6000 = 35000 ms`；§1.1 同时给出现有 `4000 + 60000` 和 `3×120000` 上限。
- [x] §8 有 7 条可执行待核实项；§9 单列静态无法确认项。
- [x] 本次只写计划文档和计划索引；未改源码、未提交、未运行 hvigor 构建；端 A2A 冒烟结果为空，不能宣称已通。

`RESULT: PASS`（文档取证与结构自检；实机性能验收仍 pending，端 A2A smoke 未运行）。
