# 019 — 分层思考过程展示 P0:StreamEvent 协议 + enableThinking 供给 + 双区块

> **Status**: proposed (2026-09-11, grill session)
> **Source**: [research](../research/agent-reasoning-process-display-research-2026-09-11.md) · [ADR-0015](../adr/0015-structured-stream-events.md) · grill 决议 (Q1-Q9 + seam 确认)
> **Related**: ADR-0004 (call 层收敛) · ADR-0012 / [spec 014](./014-tool-calling-protocol.md) (tool-calling, SSE 工具循环排除声明) · [spec 018](./018-agent-workflow-architecture.md) (Conversation workflow)

## Problem Statement

学生用户在浮窗向 AI 提问时,回答"直接蹦出来":思考过程不可见,或时有时无(展示供给全靠服务端在 `enableThinking:false` 下的"漏回");思考文本可能被复制进最终回答(fallback 伪装双发);纯思考阶段面板文本冻结(列表 key 不含 reasoning 长度,行不更新);展开/收起是硬切换(key 含展开态,行销毁重建,无动画)。

## Solution

每条 AI 回答稳定携带一个可折叠的思考区块:默认折叠为一行摘要,流式过程中实时滚动思考文本,折叠头以两态文案区分"思考中…"与"已深度思考";点击展开/收起有平滑折叠动画;用户手动展开后流式继续写入不会收起面板。最终回答区块只含真正的回答,无思考副本。思考供给由配置默认开启,历史会话的思考区块保留,旧版本会话升级后正常显示。

## User Stories

1. 作为学生用户,我希望每条 AI 回答都带一个可折叠的思考区块,以便了解 AI 的推理过程。
2. 作为学生用户,我希望思考区块默认折叠只占一行摘要,以便长思考链不淹没聊天界面。
3. 作为学生用户,我希望流式过程中思考区块实时显示思考文本,以便感知 AI 正在思考什么。
4. 作为学生用户,我希望折叠头在流式中和完成后显示不同状态文案,以便一眼区分"思考中"与"已深度思考"。
5. 作为学生用户,我希望展开/收起有平滑折叠动画,以便交互有质感。
6. 作为学生用户,我希望手动展开后流式继续写入不会把面板收起,以便我的展开操作被尊重。
7. 作为学生用户,我希望最终回答区不含思考文本副本,以便阅读不被重复内容干扰。
8. 作为学生用户,我希望思考模式始终开启,以便思考区块不会时有时无。
9. 作为学生用户,我希望重新打开历史会话时思考区块仍在,以便回顾当时的推理。
10. 作为学生用户,我希望旧版本保存的会话升级后正常显示,以便历史不丢。
11. 作为学生用户,我希望纯思考阶段面板文本持续滚动更新,以便不误以为 AI 卡死。
12. 作为开发者,我希望流式回调是结构化事件对象且 type 四值全定义,以便 P1 工具事件不再改回调签名。
13. 作为开发者,我希望 enableThinking 由 LlmConfig 统一供给且默认开启,以便行为可预测且异常时有配置退路。
14. 作为开发者,我希望 reasoning→content 伪装 fallback 的删除与协议改造落在同一实施切片,以免中间态复现 UI 空白 bug。
15. 作为开发者,我希望列表 key 由纯函数生成且含 reasoning 长度、不含展开态,以便冻结与动画问题被测试锁定。
16. 作为维护者,我希望 SSE 行→事件的解析是可单测的纯函数,以便双发/null/空 choices 回归永久锁定。
17. 作为维护者,我希望事件→消息字段分发有测试覆盖,以便 thinking/text 通道不串。
18. 作为维护者,我希望 ChatMsg 模型 P0 零新增字段,以便旧会话 JSON 兼容零风险。

## Implementation Decisions

### 1. StreamEvent 协议 (ADR-0015)

- 流式回调从 `(delta: string, kind)` 改为结构化事件对象 `{type, ...payload}`,type 联合**四值全定义**:`thinking | text | tool_call | tool_result`。
- P0 仅 emit `thinking`/`text`;消费端 switch 对未实现分支 default 兜底。四值是为 P1 工具事件预留的座位 — P1 只加 emit,不改类型。
- 全链同步改:LlmTypes / LlmClient / ReplyService / ConversationWorkflow / AgentChatService / AgentFloatWindow。
- 术语(CONTEXT.md **StreamEvent** 词条):事件 type 用 `thinking`/`text`;wire 字段保持 `reasoning_content`;UI 文案用"思考"。

### 2. fallback 治理 (same-PR 硬条款)

- LlmClient SSE 解析中"content 为空时把 reasoning_content 伪装成 content 重发"的分支**删除**。
- 安全前提:新消费端接受 thinking 事件,thinking-only 响应落入思考区块而非空白 UI。
- **删除与协议改造必须同一实施切片**:先删后改 → 复现 2026-09-07 UI 空白 bug;先改后删 → 双发继续。该 fallback 是 2026-09-07 的真实 bug 修复(旧协议下上层只消费 content),不是防御性设计。

### 3. 双通道分发

AgentChatService 回调从"仅放行 content"的过滤改为双通道:`thinking` → ChatMsg.reasoning 累积,`text` → ChatMsg.content 累积。

### 4. enableThinking 供给 (两步落地)

- ReplyService 删除三处显式 `enableThinking: false` 覆盖 — LlmClient 已有 `request 未定义则回退 config` 的链路,删覆盖即接线。
- LlmConfig 的 enableThinking 默认值 false→true。该键从未有 UI 写入(`setEnableThinking` 零调用方),改默认即全局生效,无存量兼容包袱。
- 不建 UI 开关(装饰性开关已删除,不复燃)。

### 5. 分区展示(附件式单折叠)

ChatBubble ai 分支双区块化:过程区块在上,最终回答区块在下,采用**附件式单折叠**形态(2026-09-12 细化拍板):

- 思考区裸露在回答气泡外(Claude 产品形态),折叠头升级(两态文案 + animateTo);回答气泡本体**零改动**(现有长文浅底/短文底色与 maxWidth 逻辑保持)。
- P1 工具调用列表将作为**过程区块内部的二级折叠**(不新增独立一级折叠头);一级折叠头届时追加工具摘要计数。
- P0 零空占位:条件渲染,数据未到不渲染对应子块。

不做时序混排(P0 单轮思考下分区无信息损失;混排是 P1+ 多轮形态);不做三明治三区并列与大气泡一体化(已评估落选)。

### 6. keyGen 纯函数

AgentMessageList 的内联 keyGen lambda 提取为 ChatModels 导出纯函数 `chatItemKey(msg)`:**增** `reasoning.length`(纯思考阶段防冻结),**删** `reasoningExpanded`(animateTo 动画前提 — 展开不再销毁行);`content.length`/`streaming` 保持。

### 7. 折叠头两态文案

流式中"思考中…",流结束"已深度思考"。ChatStatusMachine busy 行保留为独立状态通道,与思考折叠头并存。不做"思考 X 次"(单轮恒 1)与用时计量(P1 工具循环落地后再升)。

### 8. 展开态保护与动画

- `reasoningExpanded` 沿用现有"append 不触碰"纪律 — 流式写入不夺回用户展开态。
- 折叠动画走 `animateTo` + if(官方路线);展开态变化通过 @Prop 数据更新驱动,行不重建。

### 9. 事实裁决(非拍板,事实推导)

- **ChatMsg P0 零新增字段**:现有字段已覆盖 P0 全部需求 → 旧会话 JSON 兼容零风险,map+spread 漏字段风险不存在。
- **思考区流式渲染纯 Text 现状平移**(progressive Markdown 是 P2)。
- **reasoning 持久化不动**(照旧随 ChatSession JSON 持久化;膨胀风险记账,真机验收顺带观察会话体积)。
- **EventSource 三方库不采纳**,维持 requestInStream 自研解析(已评估,open question 关闭)。

## Testing Decisions

好测试只测外部行为(给定输入断言输出),不测内部实现细节。三个 seam:

- **Seam A — SSE delta→StreamEvent 解析器**(`common/src/test`):把 LlmClient 的 SSE delta 转换逻辑提取为可测纯函数(先例:LlmToolCalling.test.ets 测 extractToolCalls 的同模式)。回归锁:①双发+伪装(content 空 + reasoning 非空 → 仅 1 个 thinking 事件,无 text)②null delta 容错(2026-09-07 修复)③空 choices → 无事件 ④双通道顺序(thinking 先于 text)。
- **Seam B — 事件→ChatMsg 字段分发**(`entry/src/test`):复用现有 service 测试模式,经 AgentChatService adapter 注入事件,断言 reasoning/content 累积不串;若结构不适配单测则降级并入真机验收。
- **Seam C — keyGen 纯函数**(`entry/src/test`):①reasoning 增长 → key 变(防冻结回归锁)②reasoningExpanded 翻转 → key 不变(动画前提)③content.length/streaming 行为保持。

**真机验收(非自动化,含 Open Q1 收尾)**:build + 浮窗对话 + hilog 验证 `enableThinking:true` 态 reasoning 事件稳定供给 + 手动 UI 检查:双区块渲染 / 两态文案 / 折叠动画 / 展开态不被流式收起 / 纯思考阶段不冻结 / 历史会话(旧版本数据)兼容 / 会话体积观察。

## Out of Scope

**P1(工具过程展示,届时单独立 spec)**:
- ToolCallingWorkflow 事件出口(B7)
- SSE + 工具循环(spec 014 明确排除,需新 spec)(B2)
- 工具列表二级折叠 + SymbolGlyph 图标 + 摘要计数升级(F7 / B6 / F4 计量版)
- `tool_call`/`tool_result` 的 emit 侧
- 多轮 thinking 区块合并(step 分隔)
- ChatMsg `toolCalls` 字段与旧会话兼容 checklist(F8)

**P2(打磨)**:
- reasoning_effort 可配置化(B5)
- ChatBubble @Reusable(F6)
- 思考步骤 progressive Markdown(F5)
- 工具调用入会话记忆(B8)
- reasoning 持久化膨胀治理(待实测数据)

**明确不做**:UI 思考开关(已删,不复燃)· EventSource 三方库迁移(已评估不采纳)· "思考 X 次"计数(单轮恒 1)· 时序混排(P0 无信息损失,多轮再议)

## Further Notes

- 本 spec 是 P1 工具过程展示的前置;type 四值联合即 P1 的预留位。
- `enableThinking:false` 态服务端漏回 reasoning_content **已实证**(2026-09-07 修复记录:38KB 流含 reasoning_content + 空 content);true 态验证并入真机验收。
- 验收基线:v1.0 (2026-09-05 release) 分支 `feature/kit-skill-integrations`。
