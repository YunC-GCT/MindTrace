# Bot 派活单索引

> 五个 Bot 的分工与本轮派活。**派活单是一次性工作指令**，做完归档到 `docs/legacy/mindtrace/handoffs/`；团队规则不在这里维护，仍在 `AGENTS.md`。
> 建立：2026-10-30 · 基线 `feature/a2a-text-ingest` @ `dac64c3`

## 分工表

| Bot | 模型 | 领域（可改） | 能做 | 不能做 |
|---|---|---|---|---|
| **architect** | gpt-5.6-sol | `docs/`、`CONTEXT.md`、跨模块 | as-built 与目标架构两张图对照、写 ADR（背景/决策/代价/被否方案）、划模块边界与分层、评审 StateGraph 改动、维护术语表 | 任何 `.ets`/`.ts` 源码、构建、部署、`hdc`、对外材料 |
| **ui** | deepseek-flash | `pages/` `overlays/` `viewmodels/` `shared/`、`tools/galaxy3d-preview` | ArkUI 页面与组件、状态管理与刷新链路、AI 浮窗交互（流式/进度/打断）、3D 知识星系渲染、空态/加载态/深色模式/三档断点 | `workflows/` `services/`、数据库 schema、`cardservice/`、`hvigorw`/签名/装机 |
| **flow** | deepseek-flash | `workflows/` `services/` `models/` `database/` | StateGraph 节点与边/状态/中断点、材料理解与笔记生成、检索与关系扩展、来源解析、对话隔离与记忆投影、`LlmClient` 模型调用层、RDB 读写与迁移 | UI 布局动效、卡片与小艺入口、签名；schema 变更必须先过 architect |
| **harmony** | deepseek-flash | `cardservice/` `skill/` `entry/.../agentextability/`、构建配置 | 元服务卡片（刷新链路/跳转/空态/生命周期）、小艺 A2A 单帧 `result.task`、`hvigorw` 构建与签名、`hdc` 真机验收、`.hap` 产物与 `build-profile.json5` | 业务逻辑、UI 组件、ADR；**唯一能跑 `hvigorw` 的 Bot** |
| **ship** | deepseek-flash | 指标、合规、验收、对外材料 | 指标定义（定义/口径/采集点/当前值/是否已测）、数据契约、上架合规（权限逐条对应代码、隐私政策、卡片审核）、验收清单、答辩稿/BP/简历段落 | 代码、架构、ADR；没测过的数字一律标「未测」 |

## 本轮派活（2026-10-30）

| Bot | 本单焦点 | 状态 | 派活单 |
|---|---|---|---|
| architect | 模块拓扑与 `AGENTS.md` 不符（实际 2 HSP + 3 HAP）、写「端A2A 入口分层」ADR、两张架构图、统一 `phase-tracker` 口径 | 待接手 | [`handoff-architect-2026-10-30.md`](./handoff-architect-2026-10-30.md) |
| harmony | 真机验收「我要拍题 → 卡片 → 选图」，三种结局都要落证据；1011 就关 `UI_CARD_ENABLED` 回退 | 等真机 | [`handoff-harmony-2026-10-30.md`](./handoff-harmony-2026-10-30.md) |
| flow | spec 036 阶段 2/3：`segmentProblems`/`mergeProblems` 接进 `CaptureGraph`，`AgentState` 加 `problemSegments`/`sourceImageIds`，一题一条 note | 待接手 | [`handoff-flow-2026-10-30.md`](./handoff-flow-2026-10-30.md) |
| ui | 卡片页三档断点 / 深色 / 错误态；与应用内「+」入口视觉一致；浮窗失败态补重试 | 待接手 | [`handoff-ui-2026-10-30.md`](./handoff-ui-2026-10-30.md) |
| ship | 端A2A 图片通道与卡片触达的指标定义（多为「未测」）、验收清单更新、上架合规权限对应、对外统一表述 | 待接手 | [`handoff-ship-2026-10-30.md`](./handoff-ship-2026-10-30.md) |

## 使用规则

1. 接手前先读自己的派活单 + `docs/agents/phase-tracker.md`，别在别人的领域里顺手改。
2. 派活单里写的「已完成」都带 commit 或命令输出，不接受转述。
3. 做完把自己那一行状态改成「已完成 + 日期」，并把证据路径填进 `phase-tracker.md`（harmony / flow 各自对应阶段）。
4. 冲突裁决：拓扑与分层归 architect，构建与真机归 harmony，业务编排归 flow，界面归 ui，口径与外发归 ship。
