# 020 — Reply Body 契约:流式直出正文 + ReplyService 解码 seam + 持久化门 + 渲染单入口

> **Status**: proposed (2026-09-12, grill session)
> **Source**: [research](../research/llm-json-answer-parsing-2026-09-12.md) · [ADR-0016](../adr/0016-reply-contract-by-transport.md) · grill 决议 (Q1-Q5) · 渲染入口 parity 核查 (2026-09-12, 结论录入 §5)
> **Related**: ADR-0004 (call 层收敛) · ADR-0015 (StreamEvent 通道) · [spec 018](./018-agent-workflow-architecture.md) §7 (单后端 — transport 契约分流≠双轨, 见 ADR-0016) · **[spec 019](./019-reasoning-process-display-p0.md) (前置依赖, §0)**

## 0. 前置依赖 (红线 #7: 多 session 并行隔离)

本 spec 的代码改动面 (ReplyService / IntentClassifier / ChatModels / ConversationWorkflow / ChatBubble) 与 spec 019 P0 (feature/spec-019-p0, 实施中) 高度重叠。**020 的代码实施必须排在 019 P0 合入之后**, 避免同文件并行冲突。本文档 (ADR + spec + 术语) 不触碰 019 改动面, 可先行。行号引用以 2026-09-12 working tree 为准, 仅供导航。

## Problem Statement

浮窗 AI 对话:流式回答直显 raw JSON envelope (`{"answer": "正态分布...`);complete 路径因模型 envelope 违约 (单反斜杠 LaTeX、JSON 后附带 prose) 触发 `Bad escaped character` / `additional input` 解析失败;流式正文完全绕过校验, 坏正文直入会话历史与跨轮记忆;渲染双入口能力不对称 (流式 raw Text / 完成态 FormulaSplitRenderer naive `split('$$')` — code fence 内 `$$` 会切坏);`$$` 切分全链有 3 份实现 (FSR naive split / MarkdownParser 状态机 / MathTextRenderer 高度估算)。

根因: 同一 prompt 契约 (JSON envelope) 与流式 UI 消费契约 (Markdown 正文) 在 seam 处结构性错位, 且 stream/complete 解码不对称 — 同一模块三个方法两种输出语义。13 条病根映射见 Further Notes。

## Solution

stream transport 的 prompt 直接产出 Reply Body (MM-MD-v1 Markdown, 自然单反斜杠 LaTeX), 不再要求 JSON envelope;complete transport 保留 envelope + LlmGuard 门。ReplyService 独占 envelope→body 转换, 确立不变式「`ChatMsg.content` 恒为 Reply Body」。流末 one-shot envelope 剥离兜底模型惯性;持久化前过 ContentProtocol 归一化门 (只归一化不拦截, `ok` 分级, 带 issue 必打标 `contentIssues`);ChatBubble 完成态收敛到 MarkdownRenderer 单入口, FSR 的 WebView 数量优化移植进 MDR 后降级;流式态 P0 保持轻量 Text (契约 A 后显示的即正文纯文本)。

## User Stories

1. 作为学生用户, 浮窗 AI 流式回答直接显示 Markdown 正文, 不再看到 `{"answer":...` 原始 JSON。
2. 作为学生用户, 公式按 `$$` 块渲染, 单反斜杠 LaTeX 不再触发解析错误。
3. 作为学生用户, 重新打开历史会话, 回复内容干净、无 envelope 残留。
4. 作为学生用户, 含 code block 的回复中 `$$` 不会被误切分。
5. 作为开发者, `ChatMsg.content` 恒为 Reply Body 的不变式有测试锁定。
6. 作为开发者, stream / complete 两种 transport 的 prompt 契约分流由纯函数测试锁定。
7. 作为开发者, 模型惯性仍输出 envelope 时, 流式显示被前缀早检抑制, 流末 one-shot 剥离后终态干净。
8. 作为开发者, 带 issue 持久化的回复携带 `contentIssues` 标记, AgentMemoryService 不把它纳入高质量记忆。
9. 作为维护者, 完成态正文渲染只有 MarkdownRenderer 一个入口, `$$` 切分只有 MarkdownParser 一份实现。
10. 作为维护者, complete 路径 LlmGuard 容错提取覆盖 prose 包裹 / 双 JSON 场景。
11. 作为维护者, 旧版本会话 (无 `contentIssues` 字段) 升级后正常打开。

## Implementation Decisions

### 1. 不变式与 seam 归属 (Q1 / ADR-0016)

ReplyService 独占 envelope→body 转换;三个出口 (complete / stream / fallback) 输出语义一致 — fallback 自产 mock, 直接产 body。LlmGuard (JSON gate) 与 ContentProtocol (MM-MD-v1 gate) 是 ReplyService 内部 adapter, 不外溢。UI (ChatBubble / ChatModels)、持久化 (sessionStore)、记忆 (AgentMemoryService) 三个 consumer 只见 body。

### 2. stream 契约分流 (Q2 = A)

IntentClassifier.buildReplyMessages 按 transport 分流:

- **stream prompt**: 去 JSON_ONLY_RULES 与双反斜杠规则 (LlmOutputRules #10 — 那是 JSON 转义要求;raw Markdown 里 `\\frac` 反而渲染错误);保留 `$$` 块纪律;自然单反斜杠 LaTeX。
- **complete prompt**: 保留 JSON envelope + responseFormat `json_object` + LlmGuard 重试 (现状不动)。
- stream 请求不设置 responseFormat (现状已如此, 保持)。

### 3. envelope 剥离兜底 (one-shot, 有界)

模型可能惯性仍输出 envelope。两道防线, 均非增量解析:

- **前缀早检 (显示侧)**: 累积正文若以 `{"answer"` 或 \`\`\`json fence 开头, ChatModels 流式显示保持占位、不渲染 envelope 片段 (纯 startsWith 前缀判断)。
- **流末剥离 (数据侧)**: ReplyService 在 stream 收尾时 one-shot 检测 — envelope 形状 → 复用 LlmGuard 提取逻辑单次解码 → 提取 answer 作为 body;解码失败 → 原文作为 body + 打 issue `envelope_strip_failed`。

### 4. 持久化门与 ok 分级 (Q5b)

stream 成功后、持久化前过 ContentProtocol: **只归一化不拦截**。`ok` 语义分级 — 可修复 issue (未闭合 `$$` 等) → 归一化后通过;不可修复 → 按原文持久化 + 打标 (不重试;Q5(c) 非流式重试已否决, 复审条款在 ADR-0016 Risks)。

- **issue 记录位置**: ChatMsg 新增可选字段 `contentIssues: string[]` (issue id), 随 ChatSession JSON 持久化;旧会话缺字段 → 视为无标记。(019 的「ChatMsg P0 零新增字段」是其自身约束;本字段是 020 的显式决策, 兼容姿态同 019 US10。)
- **消费方**: ① AgentMemoryService — 读标记, 带 issue 回复不进入高质量记忆通道;② 会话历史 (可追溯);③ 真机验收 hilog。
- **打标硬规则**: 带 issue 持久化必须携带标记, 禁止静默存。

### 5. 渲染单入口 (Q4; parity 核查裁决 → 方向 1 + 优化移植)

核查结论 (2026-09-12, 完整摘录见 Further Notes): **两入口不对等, 且强弱势与 Q4 预设分支相反** — MarkdownRenderer (经 MarkdownParser 状态机) 在正确性上占优 (code-fence 保护 / 未闭合 `$$` flush / `\[…\]` / 解析缓存 / 原生 Markdown 结构), FormulaSplitRenderer 仅在 WebView 数量上占优 (LazyForEach / 相邻文本合并 / block cap / 长文 re-split), 其 `split('$$')` 无 code-fence 保护。**反向收敛 (MDR 委托 FSR splitter) 是正确性倒退, 否决**;正向收敛:

- **P0**: ChatBubble AI 完成态公式路径 (FSR 调用点 :105) 切到 MarkdownRenderer;:111 非公式路径已在 MDR, 保持。:29 用户消息路径暂留 FSR (用户输入无 envelope 风险), P1 随 chat 样式包装一并收敛。NoteDetailOverlay 家族已全走 MDR, 不动。
- **P1**: FSR 加性优化 (LazyForEach+IDataSource / 相邻合并 / block cap / 长文 re-split) 移植进 MDR;FSR 降级为 chat 样式包装或删除 (届时拍板)。
- **流式态 P0 保持轻量 Text**: parity 核查确认两个入口都不具备流式安全增量渲染 (per-token 全量重解析);契约 A 后流式 Text 显示的即正文纯文本, 症状消除。progressive Markdown 流式渲染为 P2 (与 019「思考区流式纯 Text 平移」同一立场)。

### 6. P2 — LlmGuard 容错提取

greedy `/\{[\s\S]*\}/` (LlmGuard.extractJsonObject) → 平衡花括号扫描 + fence/prose 容忍 (前后 prose / 双 JSON / 字符串内花括号)。只此一项, 不重构 LlmGuard。

## Testing Decisions (TDD)

- **Seam A — prompt 契约分流** (`entry/src/test`): stream messages 不含 JSON_ONLY_RULES、含 `$$` 块纪律;complete 保留 envelope 规则与双反斜杠;同出口纯函数断言。
- **Seam B — envelope 剥离纯函数** (`entry/src/test`): envelope 形状 → 提取;fence 包裹 → 提取;prose 前缀 → 提取;纯 Markdown → 原样;坏 JSON → 原样 + `envelope_strip_failed`。
- **Seam C — content 不变量** (`entry/src/test`, 经 AgentChatService adapter 注入事件): 累积后 content 不含 envelope 前缀 `{"answer"`;早检命中时流中不渲染、流末干净。
- **Seam D — ContentProtocol ok 分级** (`common/src/test`, 扩展现有 ContentProtocol.test.ets): 可修复 issue → 归一化 + ok;不可修复 → fail;现有 :94 (json escape 控制字符 fallback) / :101 (正态分布可渲染) 回归保持绿。
- **Seam E — MarkdownParser 公式块** (P1, `entry/src/test`): code-fence 内 `$$` 不切分 / 未闭合 `$$` flush 为段落 / `\[…\]`;若 MarkdownRendererProtocol.test.ets 已覆盖则只补缺口。
- **真机验收**: 浮窗 SSE 对话全程无 envelope 字样;正态分布样例 (`\frac{1}{\sigma\sqrt{2\pi}}`) `$$` 块渲染;历史重开干净;hilog 验证 `contentIssues` 打标与 AgentMemoryService 跳过高质量通道。

## Phasing (Q3)

| 阶段 | 内容 | 病根 |
|---|---|---|
| **P0** (demo 关键) | 契约分流 + 剥离兜底 + 持久化门/打标 + 完成态单入口 | #1 #3 #5 #6 #7 #8 (+#2 流式侧整类消失) |
| **P1** (独立 ticket, 与 P0 正交可并行) | FSR 优化移植 + 降级删除;hasFormulaSyntax 删除;MTR 缓存重试一致性;块上限截断标记 + KaTeX 坏公式降级 | #9 #10 #11 #12 |
| **P2** | LlmGuard 容错提取 | #2 complete 侧 |
| **P3** | 随各 ticket 测试就位;stale lint tests (reasoning-fallback / stream-timeout) 属 019 blast radius, 不在本 spec | #13 |

## Sequence

1. `docs(adr): ADR-0016 + CONTEXT.md 术语 (Reply Envelope / Reply Body) + spec 020 + indexes` ← 本 commit
2. `feat(entry): prompt 契约分流 + envelope 剥离纯函数` (Seam A/B 红→绿)
3. `feat(entry): 持久化门 + ok 分级 + contentIssues` (Seam C/D)
4. `feat(entry): ChatBubble 完成态单入口 + 前缀早检`
5. `refactor(entry): FSR 优化移植 + 降级拍板` (P1)
6. `refactor(entry): 渲染加固 (hasFormulaSyntax / 截断标记 / MTR 重试)` (P1)
7. `feat(common): LlmGuard 容错提取` (P2)

## Acceptance Criteria

- [ ] 浮窗流式回答全程无 `{"answer"` 字样 (真机)
- [ ] `ChatMsg.content` 恒为 Reply Body — Seam C 绿
- [ ] stream prompt 无 JSON_ONLY_RULES / complete 保留 — Seam A 绿
- [ ] envelope 惯性输出被早检抑制 + 流末剥离 — Seam B 绿 + 真机
- [ ] 持久化前归一化;带 issue 必有 `contentIssues` — Seam D 绿
- [ ] AgentMemoryService 不消费打标回复的高质量通道 (真机 hilog)
- [ ] ChatBubble AI 完成态不再经 FSR;FSR 剩余调用方仅用户消息 (P1 收敛)
- [ ] 旧会话 (无 `contentIssues`) 正常打开
- [ ] 13 病根每条有归属 (P0/P1/P2/随 019/不做)

## Out of Scope

- Option B 增量 envelope 解码器 — ADR-0016 记录的演进路径, 触发条件: 流式需要结构化字段 (citations / confidence)
- Q5(c) 校验失败非流式重试 — 已否决;ADR-0016 Risks 记录复审条款 (记忆污染放大效应出现时重评)
- LlmGuard 整体重构
- 流式 progressive Markdown 渲染 — P2 (触发: 契约 A 下 transient 症状仍常见或体验升级)
- stale lint tests (reasoning-fallback / stream-timeout) — 019 领地
- NoteDetailOverlay 家族 — 已走 MDR, 无需动

## Further Notes

### 病根映射 (13 条, 2026-09-12 诊断)

| # | 病根 | 归属 |
|---|---|---|
| 1 | prompt 契约 (JSON envelope) 与流式消费契约 (Markdown 正文) 结构性冲突 | P0 (契约分流) |
| 2 | 模型违约: 单反斜杠 / JSON 后附带 prose → 解析失败 | P0 流式侧 (整类消失) / P2 complete 侧 (容错提取) |
| 3 | stream/complete 解码不对称 | P0 |
| 4 | 流式正文无增量解码器 (全链不存在) | 随契约 A 不再需要;Option B 为演进路径 |
| 5 | 校验门不对称 (complete 有, stream 绕过) | P0 (持久化门) |
| 6 | applyStreamEventToChatMsg 把 envelope 片段拼进 content | P0 (契约 A + 早检) |
| 7 | ChatBubble 流式 raw Text / 完成态 FSR 双入口 | P0 完成态单入口;流式 Text 显示 body (症状消除);progressive 为 P2 |
| 8 | 持久化污染 (历史 + 跨轮记忆) | P0 (归一化门 + 打标) |
| 9 | FSR naive `split('$$')` (无 code-fence 保护, fallback 仍 naive) | P1 (随 FSR 降级消亡) |
| 10 | hasFormulaSyntax 命令表窄, 双向误判 | P1 (单入口后删除该路由谓词) |
| 11 | FSR 30-block cap 静默截断 + KaTeX throwOnError 红错 | P1 (截断标记 + 降级策略;区别于 Token Budget 的截断降级) |
| 12 | MathTextRenderer 缓存重试用 raw text, 与主路径不一致 | P1 |
| 13 | 测试债 (stream 红灯 / content 不变量 / split 纯函数 / stale lint) | P3 (stale lint 归 019) |

### parity 核查摘要 (2026-09-12)

三份 `$$` 切分实现: ① FSR `split('$$')` (fence-blind);② MarkdownParser 行状态机 (code-fence 保护 P:219-228 / 未闭合 `$$` flush P:321-325 / `\[…\]` P:176-182 / 解析缓存);③ MathTextRenderer 高度估算 (只计数)。FSR 优势全部是性能类 (LazyForEach FSR:235-272 / 相邻合并 FSR:64-72 / cap FSR:92-94 / 1500-char re-split FSR:103-144), 唯一消费方是 ChatBubble 两处;MDR 消费方含 NoteDetailOverlay 全家族 + MarkdownRendererProtocol.test.ets。两入口均无流式安全增量渲染 (MDR 较近: 16ms defer + renderSeq, 但仍是 per-token 全量重解析) → 流式态保持 Text。

### 已知风险 (ADR-0016 Risks, 复审条款)

1. complete 路径保留 envelope 的必要性定期复审 — 若 LlmGuard 提取+重试证明低价值, complete 也可直出正文换验证门。
2. 带 issue 持久化可能污染跨轮记忆 — 若出现放大效应, 重评 Q5(c) 非流式重试或加重试门。
