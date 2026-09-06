# Agent 工具/技能派发链总览 — 2026-09-06

> 汇总视图。规范细节以被引用文档为准,本文不复制内容——读完这页知道"谁连谁、缺口在哪",要细节点引用。

## 链路图

```text
调用方 A: 应用内 LLM 工具循环            调用方 B: skill/ (小艺, 未来)
ToolLoop (spec 014; common/tools/)      IntentRouter (ADR-0011 实装路径)
  | LlmCaller seam → LlmClient            | Intents Kit (@InsightIntent*, API 11+)
  | 云端 OpenAI 兼容 function-calling     | want.action → 只读 intent 先行
  v                                       v
           ToolRegistry (common, ADR-0012)
           register / listDefinitions / execute
                          |
                          v
        AgentTool 只读 3 件 (P1, 赛后实现): note_query / note_get / review_due_query
                          |
                          v
        DatabaseHelper RDB store (schema SoT: entry NoteDao, spec 014 §4 警示)

旁路: OcrTool (mcp/, ADR-0010) — TypeClassifier 直调, 独立于 ToolRegistry
赛后: 写类工具 — 与 F2 写库路径统一绑定后另立 spec (ADR-0012)
```

## 逐段要点(引用,不复制)

| 链路段 | 状态 | 权威文档 |
|---|---|---|
| ToolLoop / 协议字段 / extractToolCalls | spec-only(复赛冲刺序 3,零实现) | [spec 014](../specs/014-tool-calling-protocol.md) / [ADR-0012](../adr/0012-tool-calling-protocol.md) |
| ToolRegistry 契约(AgentTool/ToolResult) | 同上,随 spec 014 落地 | 同上 |
| skill/ IntentRouter | 预留位,实装另立 spec(前置:7 个 intent 语义队员确认) | [ADR-0011](../adr/0011-skill-xiaoyi-reservation.md) / 调研 §5 |
| 只读 AgentTool 3 件(P1) | 接口形状已定,实现赛后 | spec 014 §4 |
| 写类工具 | 赛后,F2 写库路径统一的前置 | ADR-0012 Consequences / [inventory](agent-tools-inventory-2026-09-06.md) F2 |
| OcrTool | 现役,`mcp/` 语义(非 Registry 成员);注册为 AgentTool 属后续单独决策 | ADR-0010 |
| Kit 三 facade(Reminder/BackgroundTask/FormCard) | 契约已立,接线 = 复赛冲刺序 2(ReminderFacade 优先) | ADR-0009 / spec 013 |

## 与结构化 sub-agent 的关系

[KnowledgeModel 拆分 v2](../specs/015-knowledge-model-decomposition-v2.md)(PR1 复赛窗口内 / PR2-3 赛后)完成后,`StructureService` 的 LLM 交互收敛于单一私有 seam——它是 ToolLoop 的**第一个候选接入点**(只读工具就绪后,可用于结构化前的查重/前备检查)。是否接入属后续裁决,本文只记录候选关系。

## Last updated

2026-09-06(由 KnowledgeModel 拆分 goal 的"skill 链路规范"裁决产出)
