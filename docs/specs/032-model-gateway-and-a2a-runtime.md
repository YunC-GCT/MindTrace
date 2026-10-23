# 032 — 模型网关与端A2A 运行时契约

> **Status**: proposed（2026-10-24）
> **依据**: [`a2a-module-loading-2026-10-24.md`](../research/a2a-module-loading-2026-10-24.md)、[`on-device-llm-2026-10-24.md`](../research/on-device-llm-2026-10-24.md)
> **前置**: [`031-xiaoyi-batch-capture-entry.md`](./031-xiaoyi-batch-capture-entry.md)（端A2A 接入本体）

## Problem Statement

用户在小艺里说一句话，期望得到一段完整的答案；实际遇到三种失败，且都发生在「看起来已经做完」之后：

1. **回复只剩开头一两个字**（「已」「好」「当前」），报文里其实带着 200+ 字。
2. **回复根本不出现**，进程在 `onCreate` 之前就死了，日志一片空白，只留下 `exit 254 / Reason:SyntaxError`。
3. **模型能力的承诺落空**：架构文档写「默认走端侧大模型」，而 `common` 里的 `OnDeviceLlm` 从未真正可用；把模型路由接进会话层后，App 主进程也起不来。

三次失败都不是业务逻辑写错，而是**契约没钉死**：构建产物新鲜度没人管、A2A 响应形态跟着 SDK 走、端侧能力被写成了默认路径却没有任何系统 API 支撑。

## Solution

把三件事分别钉成契约，并在代码与文档里同时生效：

- **构建**：HSP 必须先于 HAP 重建。HAP 引用 HSP 里不存在的符号会在链接期 `SyntaxError`，且报错发生在任何业务代码之前——只能靠构建顺序防，不能靠运行时兜底。
- **A2A 响应**：只发单帧 `result.task` 快照（`artifacts` + `TASK_STATE_COMPLETED` 一次给全）。SDK 的流式帧序列（`SUBMITTED` → `artifactUpdate`）在小艺客户端上只渲染开头几个词，禁用。
- **模型网关**：端侧是**可插拔能力位**，不是默认路径。v1 默认走用户配置的云端模型；只有「端侧就绪 + 用户显式开启」才走端侧；回退必须让用户看见。

## User Stories

1. 作为用户，我在小艺里问一个问题，希望看到完整的一段回答，而不是一个字。
2. 作为用户，当模型很慢时，我希望在合理时间内得到明确提示，而不是界面一直空转。
3. 作为用户，当回答来自降级路径时，我希望在答案末尾看到「已降级」和原因，而不是被静默换模型。
4. 作为用户，我在设置页能看见「端侧模型：未就绪」，而不是以为它已经在用。
5. 作为用户，我开启「优先端侧」但设备没有模型时，应立刻被告知不可用，而不是等一次失败。
6. 作为开发者，我改完 `common` 的代码后构建，产物必须是新的，不能因为 `up-to-date` 拿到旧 HSP。
7. 作为开发者，我接一个新依赖进扩展进程时，崩溃要能在构建期暴露，而不是等到真机上「没有回复」。
8. 作为开发者，我要能单独验证 A2A 响应形态（纯函数级），不必每次上真机。
9. 作为评审者，我能从 spec 直接看出「端侧」在 v1 是什么定位，不再被文档误导。
10. 作为用户，小艺回答里的 Markdown（项目符号、编号）应正常渲染，不被截断。

## Implementation Decisions

### 1. 构建顺序（P0）

- `common`（HSP）与 `entry`（HAP）分两次构建，HSP 先。任何「改了 common 却只 build entry」的流程视为无效。
- 一键命令写入 `AGENTS.md` 命令表，并在脚本里做**产物新鲜度断言**：HSP 的 `modules.abc` 修改时间必须晚于 `common/src` 下最新源文件，否则直接失败并提示重建。
- 判定符号是否真的进了产物：反汇编 HSP 的 `modules.abc`，`grep -c <符号名>` 必须 > 0。

### 2. A2A 响应契约（P1）

响应固定为单帧、单一 `result.task`，形状如下（来自真机验证，非草案）：

```json
{"jsonrpc":"2.0","id":"<请求 id>","result":{"task":{
  "id":"<taskId>","contextId":"mindtrace-context",
  "status":{"state":"TASK_STATE_COMPLETED"},
  "artifacts":[{"artifactId":"<taskId>-artifact",
                "parts":[{"text":"<完整回答>","mediaType":"text/plain"}]}]}}}
```

- `parts` 只放 `text` + `mediaType`，不引入客户端不认识的 part（未知 part 会导致整条响应被丢弃）。
- 不使用 `createA2AServer` 的 `addArtifact` / `updateStatus`：它会先发 `SUBMITTED` 再发增量帧，触发客户端截断渲染。
- 请求侧仍按实测解析：`params.message.parts[]` 只有 `mediaType` + `text`，无 `kind`/`type`。

### 3. 模型策略（P1）

优先级唯一，且必须可观测：

| 顺序 | 条件 | 结果 | 标注 |
|---|---|---|---|
| 1 | 用户开启「优先端侧」且端侧就绪 | 端侧 | 无 |
| 2 | 用户配置了云端模型 | 云端 | 无（这是显式选择，不算降级） |
| 3 | 请求了端侧但端侧不可用、且配置了云端 | 云端 | **必须**追加「已降级：<原因>」 |
| 4 | 都没有 | 明确错误文案 | 无答案，不伪造 |

- 「端侧就绪」= `localChatModel.init()` 返回 true（系统端侧问答模型就绪）。**2026-10-24 修订**：不再是「模型文件存在」，也不再恒为 false——API 20 起系统自带该模型，`@hms.data.localChatModel` 同时支持 `isStream` 增量返回。
- 端侧不可用时按上表降级；降级原因必须来自真实错误码（1021900001/0002/0003/0004）。
- 降级文案与端 A2A、应用内聊天保持一致，避免两处观感不同。

### 4. 会话端口（P1）

- 现有 `IConversationReplyPort.complete()` 的签名不动（调用方多）。
- 新增结构化返回：`completeRouted(context): Promise<RoutedReply>`，`RoutedReply = { text, source, degraded, reason }`；`complete()` 保持返回字符串，内部委托 `completeRouted`。
- `stream()` 在 v1 **不参与路由**（端侧无流式能力），行为保持现状并在 spec 里写明——不假装它已统一。

### 5. 观测（P1）

每次 A2A 回复固定打一行：`source`、`degraded`、字数、耗时。缺这行等于无法判断走的是哪条路径。

## Testing Decisions

**缝的选择：尽量少，且都在已有的接缝上。**

1. **`IConversationReplyPort`（现有端口，最高缝）** — 用两个假 provider 驱动策略优先级与降级标注，纯逻辑、不碰 UI、不碰网络。这是本 spec 的主测试面。
2. **A2A 响应构造（纯函数）** — 把「拼单帧快照」抽成 `buildTaskSnapshot(requestId, taskId, text): string`，单测 JSON 形状与转义（引号、换行、emoji）。真机端到端仍由 `scripts/a2a-smoke/a2a_smoke.py` 承担。
3. **构建新鲜度（脚本级）** — 断言 HSP 产物时间戳与符号存在，作为 gate 的一步；这是唯一能防住 `SyntaxError` 的位置。

**好测试的标准**：只断言外部可观察行为（返回文本、标注、JSON 形状、构建退出码），不断言内部类结构。

**先例**：`scripts/arkts-lint/tests/*.test.mjs` 与 `scripts/agent-gate/` 已有的断言式检查。

## Out of Scope

- **自研端侧推理**（自带 `.ms` 权重 + tokenizer / KV-Cache / 采样循环）：MindSpore Lite 不支持动态 Shape，工程量大。列 v2；**端侧问答本身不再属于范围外**——用系统提供的 `@hms.data.localChatModel`（见 §3 修订）。
- **SDK 流式回复**：本 spec 明确禁用，不尝试修复其渲染。
- **小艺 agentUI 卡片拉起相册**：Want 组装在闭源客户端，记为平台阻塞。
- **文搜图**：独立能力，单独排期。
- **应用内流式路径的路由改造**：`stream()` 维持云端。

## Further Notes

- 两份调研报告里标注为「未找到 / 待确认」的条目（例如社区传闻的 `@hms.ai.largeLanguageModel`）不得作为决策依据；若属实，另开 spec 重新评估端侧路线。
- 崩溃排查的教训已写入 `skills/harmonyos-xiaoyi-a2a`：**先看产物，再看源码**；`up-to-date` 是危险信号。
