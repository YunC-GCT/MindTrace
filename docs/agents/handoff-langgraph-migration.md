# LangGraph 迁移 — 交接报告

> **接手人:** 下一个 session 的 agent(任何模型)
> **何时读:** 你被分配到"MindTrace → LangGraph 迁移"任务时
> **目的:** 知道要做什么、什么时候做、停下来问什么、用什么 skill

> ⚠️ **SUPERSEDED (2026-09-06, 仅执行计划层面)** — 本文档推荐的"Python LangGraph 边车"实施方式已被替换。项目决策:**采纳 LangGraph 为主要设计根模型**(命名、概念、图结构均以 LangGraph 为准),在 ArkTS 内自建 CaptureGraph 原生实现,不引入 Python 运行时 / langgraphjs 依赖 — 见 [ADR-0008](../adr/0008-capturegraph-self-built-runtime.md) + [spec 011](../specs/011-capturegraph-arkts-refactor.md),D2 已于 2026-09-05 落地。**本文仅作历史记录,勿按其执行。**

---

## 现状(必读第一段)

- **状态:** 阻塞在用户回答 §6 中的 8 个问题
- **背景:** MindTrace 当前是自定义 Dispatcher(159 行 TS),不是 LangGraph;前任 agent 已完成 research(`docs/research/langgraph-migration-2026-09-02.md`)
- **目标:** 用 LangGraph 替代,4 阶段渐进,3-5 人周
- **推荐:** Python 边车服务(非 langgraphjs)

**不要做的事:** 任何代码改动前,先确认 §6 中的 8 个问题用户已答完。

---

## 启动前必做(3 步)

1. **读** [`docs/research/langgraph-migration-2026-09-02.md`](../research/langgraph-migration-2026-09-02.md) — 10 节完整研究,这是入口
2. **读** [`CONTEXT.md`](../../../CONTEXT.md) — 19 个 MindTrace 术语(项目专属)
3. **读** [`docs/agents/agent-glossary.md`](../agents/agent-glossary.md) — 通用 agent 术语(Node, Edge, State, Checkpoint 等)

---

## 阻塞:8 个待决问题

**没有这 8 个答案之前什么都别做**。把问题整理成单一 message 发给用户。

| # | 问题 | 影响 |
|---|---|---|
| 1 | Python vs langgraphjs? | 整个栈决策(影响所有阶段) |
| 2 | 服务部署? | 阶段 1 架构 |
| 3 | LLM 调用成本? | 阶段 2-3 选型 |
| 4 | 持久化(MemorySaver vs PostgresSaver)? | 阶段 3 checkpointer 实现 |
| 5 | HITL 阈值(< 0.8)? | 阶段 3 interrupt 设计 |
| 6 | 现有 ArkTS 代码怎么办? | 阶段 4 清理范围 |
| 7 | 多语言支持? | 阶段 1-3 prompt 模板 |
| 8 | state schema 版本化? | 阶段 3 checkpointer 兼容性 |

---

## 阶段 1:基础(1 周)— 阻塞

**前置**: 用户已答完 8 个问题

**目标**: Python 服务骨架 + stub graph 跑通 + FastAPI 端点可用

**主导 skill**: `writing-for-agents`(写 spec 和 state schema)
**辅助 skill**: `research`(查 LangGraph 当前 API)、`domain-modeling`(设计 `AgentState` TypedDict)

**步骤**:
1. 创建 `services/agent-runtime/` Python 项目
2. 添加 LangGraph + LangChain 依赖
3. 实现 `AgentState` TypedDict(用 `domain-modeling` 设计)
4. 实现 `build_graph()` stub(用 `writing-for-agents` 写 spec)
5. FastAPI 端点 `POST /dispatch`(返回 stub result)
6. 加单元测试(用 `tdd`)

**完成标准**(全 ✓ 才能进阶段 2):
- [ ] Python 服务本地启动
- [ ] `curl POST /dispatch` 返回 stub result
- [ ] 单元测试 100% 通过
- [ ] `state["current_step"]` 在每次节点后正确推进
- [ ] `docs/research/langgraph-migration-2026-09-02.md` §1 写明阶段 1 ✅

**Stop 条件**:
- 用户 Q1 答成 langgraphjs → 阶段 1 重做(用 JS 栈)
- LLM 端点不通 → 排查 LangGraph SDK 版本兼容性
- 测试覆盖率 < 60% → 补测试,不要进阶段 2

---

## 阶段 2:迁移 1 个 sub-agent(1 周)

**前置**: 阶段 1 跑通 + 真实图数据可发

**目标**: `TypeClassifier.classify` 完整移植到 Python,在 LangGraph 中可调用

**主导 skill**: `tdd`(test-first)
**辅助 skill**: `refactor-x` pattern(原子 commits)、`cooking-grill`(A/B 实验)

**步骤**:
1. 在 `tests/agent/test_classify_node.py` 写 characterization test(对比 TS 版输出)
2. 实现 `classify_node`(用 `tdd`:红→绿→重构)
3. 接入图(替换 stub 节点)
4. 加 feature flag `USE_LANGGRAPH_FOR_CLASSIFY=1`
5. A/B 测试 100 张真实图片(用 `cooking-grill` 跑实验)
6. 发布(commit per skill: `git mv` + conventional commit)

**完成标准**:
- [ ] `classify_node` 行为与原 `TypeClassifier.classify` 一致(100 张真实图片对比)
- [ ] feature flag 翻到 Python(TS 路径无调用)
- [ ] `docs/research/langgraph-migration-2026-09-02.md` §1 写明阶段 2 ✅

**Stop 条件**:
- A/B 测试显示不一致 > 5% → 回滚到 TS 路径,升级 LangGraph 版本后重试
- LLM 调用成本翻倍 → 触发用户 Q3 重新评估

---

## 阶段 3:剩余 sub-agents + 主流程(1-2 周)

**前置**: 阶段 2 跑通 + 真实数据(production 级别)

**目标**: `KnowledgeModel` 拆分为 `structure_node` + `validate_node`,主流程完全在 LangGraph

**主导 skill**: `tdd`(929 行 god class 拆分必须保持行为)
**辅助 skill**: `domain-modeling`(扩展 `AgentState`)、`prototyping`(HITL 先原型)、`code-review`(每 atomic commit 复查)

**步骤**:
1. 移植 `KnowledgeModel.structure` → `structure_node`(用 `tdd`)
2. 提取 `truthCheck` → `validate_node`(用 `refactor-x` pattern)
3. 加 `MemorySaver` checkpointer(用 `writing-for-agents`)
4. 加 HITL interrupt(< 0.8 置信度)(用 `prototyping` 先原型,后实现)
5. feature flag 翻到 100%

**完成标准**:
- [ ] 主流程 100% 在 Python(TS 路径不再被调用)
- [ ] `KnowledgeUnit` 输出 schema 与原 100% 兼容
- [ ] HITL 至少 pause 一次并恢复成功
- [ ] `docs/research/langgraph-migration-2026-09-02.md` §1 写明阶段 3 ✅

**Stop 条件**:
- `structure_node` 输出与原 `KnowledgeModel` 不一致 → 回滚再细化(不要硬上)
- 旧代码无引用,但用户尚未答 Q6(怎么处置旧代码)→ 暂停问用户

---

## 阶段 4:清理(1 周)

**前置**: 阶段 3 跑通 + 旧代码完全无引用

**目标**: 移除旧 TS 代码 + 更新 ADR/spec + 新 ADR 记录决策

**主导 skill**: `code-review`(全面复查)
**辅助 skill**: `resolve-merge-conflicts`(如有)、`writing-for-agents`(文档同步)

**步骤**:
1. 删除 `Dispatcher.ets`、`TypeClassifier.ets`、`KnowledgeModel.ets`、`LlmClient.ets`(用 `git rm`)
2. 标记 ADR-0003、ADR-0004 为 `superseded by ADR-0008`
3. 更新 ADR-0006 标注"已被 LangGraph 迁移方案取代"
4. 更新 spec 003 / 004 / 005 / 007 标记为 `superseded`
5. 创建新 ADR "Adopt LangGraph as agent runtime"(ADR-0008)
6. 创建新 spec "Agent state schema and graph definition"

**完成标准**:
- [ ] 旧 TS 文件已删除
- [ ] ADR / spec 索引已更新,显示新文档是权威源
- [ ] CI 通过(无 lint 错、无 link 错)
- [ ] `docs/research/langgraph-migration-2026-09-02.md` §1 写明阶段 4 ✅

**Stop 条件**:
- 发现文档引用残留旧路径(如 `Dispatcher.ets` 引用)→ 优先修 docs,再删代码
- `code-review` 找到 major issue → 修复后重新走阶段 4

---

## 各阶段 skill 一览

| 阶段 | 主导 skill | 辅助 skill |
|---|---|---|
| 阶段 1(基础) | `writing-for-agents` | `research`, `domain-modeling` |
| 阶段 2(1 sub-agent) | `tdd` | `refactor-x` pattern, `cooking-grill` |
| 阶段 3(全部) | `tdd` | `domain-modeling`, `prototyping`, `code-review` |
| 阶段 4(清理) | `code-review` | `resolve-merge-conflicts`, `writing-for-agents` |

---

## 关键文档导航

| 用途 | 文档 |
|---|---|
| 入口(必读) | `docs/research/langgraph-migration-2026-09-02.md` |
| 渲染版 | `docs/research/langgraph-migration-2026-09-02.html` |
| 前一阶段 | `docs/research/agent-framework-comparison-2026-09-02.md` |
| 项目术语 | `CONTEXT.md` |
| 通用术语 | `docs/agents/agent-glossary.md` |
| 命名规范(创建文件前查) | `docs/style/naming-conventions.md` |
| 任务模式 | `docs/agents/patterns/`(refactor-x, add-new-adr, investigate) |
| 现有 ADR(被取代) | `docs/adr/0001-0007/` |
| 现有 spec(被取代) | `docs/specs/003-010/` |

---

## 维护说明

**何时更新此文件**:

- 任一阶段完成:更新对应阶段的"完成标准"为 [x],并在 `docs/research/langgraph-migration-2026-09-02.md` §5.2 加 ✅
- 用户答完 §6 中的问题:删除对应行,更新"阻塞"段
- 创建新 ADR-0008:在"现有 ADRs"段加链接
- LangGraph API 重大变化:重核对所有"步骤"段

**与 .md 同步规则**: 本文档是执行入口。代码改动后,任何引用文件路径的步骤必须重核。

**Last updated**: 2026-09-02 · 等待用户回答 §6 启动阶段 1
