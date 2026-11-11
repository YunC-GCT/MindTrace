# Bot 交接单 · harmony（2026-10-30）

> 交接人：Hermes 主线 session · 接收：harmony（deepseek-flash）· 状态：等真机验收
> 基线：worktree `D:/HMgent/MindTrace-chat`，`feature/a2a-text-ingest` @ `dac64c3`（未 push）；设备 `3XTYD24C16203663`
> 你是唯一能跑 `hvigorw` 的 Bot，本轮所有构建/装机记录都归你维护。

## 一、已经做完的（不用重做）

| 项 | 结果 |
|---|---|
| 代码 | `bc77167` `e63449e` `4c7e2e3` `7a8b566` + 文档 `dac64c3` |
| 单测 | `node --test scripts/arkts-lint/tests/v7-a2a-ui-card.test.mjs` → 6 pass / 0 fail |
| 全量门禁 | `node scripts/agent-gate/index.mjs --all` → `RESULT: PASS`，`pass=953 fail=0`，425 个 `.ets`，`arkts-lint errors=0`，`process-boundary 6 入口 / 333 文件` |
| 构建 | `node scripts/build-hsp-hap.mjs`（pty）→ `hvigor BUILD SUCCESSFUL, 49 tasks` |
| 产物 | `common.hsp` 1,083,314 B · `agents.hsp` 666,326 B · `entry.hap` 7,520,240 B · `cardservice.hap` 183,240 B |
| 装机 | 4 个包全部 `install bundle successfully`，随后 `aa force-stop com.example.mindtrace` + `hilog -r` |

**装机顺序必须是 HSP → HAP**：`common` / `agents` 是 HSP（`type: shared`），`entry` / `skill` / `cardservice` 是 HAP（`type: feature`）。`skill` 本轮未改也没重装，属正常。

## 二、本轮唯一待办：真机验收「我要拍题 → 卡片 → 选图」

小艺 → MindTrace 智能体 → 发 **「我要拍题」**。三条日志锚点（`hdc shell "hilog -x" | grep -E "A2A_UI_CARD|AGENT_UI|CARD_ACTION"`）：

| 日志 | 含义 |
|---|---|
| `A2A_UI_CARD sent cardId=mindtrace-pick chars=…` | 我们确实把卡片 part 拼进了回执 |
| `AGENT_UI onCreate query=…` | 客户端真的渲染了 `agentUI` 并带上了 payload |
| `CARD_ACTION received action=pick_from_card` | 用户点了按钮、Want 回到 `EntryAbility` |

三种结局都要如实写进 `docs/agents/phase-tracker.md` 的「已知阻塞 / 证据」：

1. **三条日志齐** → 卡片通道可用，P1 图片通道改「小艺侧引导可用，图片仍由应用内选」，并把前面那次 1011 标为「缺必填字段导致，已修复」。
2. **只有第一条** → 客户端收到了卡片但不渲染（`agentUI` 被拒）。抓 `hilog` 里的 `start_ability_fail` / 1011 码，立刻把 `entry/src/main/ets/agentextability/AgentExtAbility.ets` 的 `UI_CARD_ENABLED` 改成 `false` 重建装机，回退纯文本，并在阻塞项里写「API 26 客户端不渲染 uiExtensionCard」。
3. **连第一条都没有** → 说明命中判定没触发：检查发的话是否含「拍题/选图/图片」等词（`A2AUiCard.wantsPickCard`），或查 `MindTraceA2A: raw=` 看报文是不是走空 part 分支。

**出现约 12 次/秒的重试就是回退信号**，不要试图调参硬扛——上一轮（spec 031 §4.9）就是这样把会话拖死的。

## 三、顺带要修的（都在你职责内）

- `docs/agents/phase-tracker.md` 第 47 行验收命令写的是 `python scripts/a2a_smoke.py`，**实际路径是 `python scripts/a2a-smoke/a2a_smoke.py --text "整理数学题"`**。口径统一由 architect 拍，你只提供正确命令。
- `scripts/a2a-smoke/a2a_smoke.py` 在部分机型上会 `RuntimeError("找不到输入框")`（输入框坐标是写死的）。真跑不通就退回 `hdc shell uinput` 手动发，别改坐标猜。
- 平台改 `agent_config.json` 的三件事仍然生效：**重新导入 AgentCard → 重发真机测试 → 重启小艺**，缺一条读旧卡。

## 四、边界

- 不改业务逻辑（`agents/`、`workflows/`、`services/`）、不改 UI 组件、不写 ADR。
- schema 变更先过 architect。
- 不 push、不合并 PR。构建/装机命令与产物校验你可以全权做。

## 五、交付格式

贴四样：①三条日志原文（或缺失说明）②构建产物字节数 ③`install bundle successfully` 回执 ④`phase-tracker.md` 的 diff。失败就贴原始输出，不要美化，也不要在没跑通时写「已通」。
