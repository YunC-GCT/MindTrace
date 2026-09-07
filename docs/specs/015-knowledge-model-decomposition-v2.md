# 015 — KnowledgeModel 实质拆分 v2(TruthCheck 先行;工具化预留位)

Supersedes [spec 003](./003-knowledge-model-decomposition.md)。Derived from [ADR-0006](../adr/0006-knowledge-model-decomposition-plan.md)(2026-09-06 修订:叠加工具化预留位)与 [ADR-0012](../adr/0012-tool-calling-protocol.md)。
**排期**:PR1 于复赛窗口内完成(2026-09-06);PR2/PR3 原定赛后,用户裁决变更后同日完成(2026-09-06)。**全部 PR 已落地;KnowledgeModel 依用户裁决保留其名,重构为轻量编排 agent(提示词/真值检查/常量已拆为协作服务)。**

## Why this ticket(为什么重立)

- spec 003 的前提全面漂移:三 façade 已存在(转发壳,各自 `new KnowledgeModel()` — 3 实例问题)、Dispatcher 已单入口(D2)、Node 测试已 94 个、工具调用协议已由 ADR-0012/spec 014 定盘。
- 用户裁决(2026-09-06):①常量与校验保留(= PromptBuilder + validateAiJson 维持代码形态);②agent 具备基本读写工具(由 ADR-0012 ToolRegistry 承载:读 P1、写赛后);③三拆方向维持。

## 现状基线(2026-09-06)

`agents/src/main/ets/agents/KnowledgeModel.ets` 878 行:

| 段 | 行(约) | 内容 |
|---|---|---|
| 编排 | L98–185 | `structure` / `structureWithClassification` |
| AI 调用 | L241–302 | `callAi`(LlmGuard.callJsonWithRetry) |
| JSON 校验 | L303–390 | `validateAiJson` + `isScoreValue` |
| 提示词 | L390–430 | `buildPrompt` |
| 归一化 | L431–568 | `buildTags` + 7 个 `normalize*` + content/summary 构建 |
| 分类 hint | L569–636 | `resolveClassificationHint`(调 TypeClassifier)/`buildExternalHint`/`mergeClassificationHint` |
| 真值检查 | L637–878 | `truthCheck` + 4 项检查(括号/除零/方程/LaTeX)+ `patchIntegralDx` |

## 目标 (Definition of Done)

1. `KnowledgeModel` 重构为纯编排 agent(保留其名);提示词/真值检查/常量拆入三个协作服务
2. **行为零变化**:响应形状 / DB 写入 / 错误语义不变;既有 94 Node 测试 + Hypium 全绿
3. 3 实例问题消除:Dispatcher 编排 3 服务,单实例组装
4. **工具化就绪**:StructureService 的 LLM 交互收敛到单一私有 seam(今天走 LlmGuard;spec 014 ToolLoop 落地后仅替换该方法体,接口不变),不耦合工具实现
5. 测试增量:TruthCheck 4 + PromptBuilder 2 + Structure 4(Hypium,按 ADR-0007 分布);每步配 Node AST 守门

## 计划(3 个原子 PR)

### PR1(复赛窗口内):TruthCheckService 实体化
- 把 L637–878 整段搬进**已存在的** `TruthCheckService.ets`(现为转发壳);`KnowledgeModel.truthCheck` 留一行转发
- 该段零 LLM / 零 DAO 依赖,纯函数 → 回归风险最低,复赛窗口可接受
- 测试:4 个 Hypium(括号配对 / 除零 / 方程一致 / LaTeX)+ Node 守门(搬运行为等价)
- 验收:`assembleHap` SUCCESSFUL;全测试绿;naming-lint / link-check 过

### PR2(赛后):PromptBuilder 实体化
- `buildPrompt` + 提示词常量(JSON 输出指令、字段说明、NoteType 5 类枚举约束)进 `PromptBuilder.ets`;2 测试

### PR3(同日完成):编排实体化 + KnowledgeModel 更名回归
- 编排 / `callAi` / `validateAiJson` / `normalize*` / hint 合并 / KM→KnowledgeUnit 转换 / `KNOWLEDGE_*` 常量 先搬入 StructureService
- 依用户裁决,实体**更名为 KnowledgeModel**(结构化逻辑本质是一个 agent,名字保留);`StructureService` 不复存在
- KnowledgeModel.test.ets 随旧类删除(其 buildPrompt/truthCheck 用例已由 PromptBuilder/TruthCheckService 服务级测试等价覆盖);agents/Index 改导出三服务 + KnowledgeModel

## Out of scope

- 读写工具的注册与实现(spec 014:P1 只读工具赛后落地;写工具与 F2 绑定)
- TruthCheck 检查规则本身的任何修改(纯搬运,不改逻辑)
- AgentChatService 拆分(spec 007,独立)
- OcrTool 注册为 AgentTool(ADR-0010/0012 留作单独决策)

## Acceptance criteria

- [x] PR1 后:`TruthCheckService.ets` 含 4 检查实现;KnowledgeModel 不再含真值检查段(878 → 617 行,2026-09-06);全测试绿
- [x] PR2 后:`PromptBuilder.ets` 实体化(提示词主体 33 行字节级 diff 一致);KnowledgeModel 617→586 行
- [x] PR3 后:`KnowledgeModel.ets` 为轻量编排 agent(554 行,保留其名);常量/提示词/真值检查在协作服务;类体 diff 仅 18 行机械差异(类名/2 处调用直连/2 个转发移除);Dispatcher 经 StructureNode 直连该 agent
- [x] 每步 `hvigor assembleHap` + naming-lint + link-check 通过
- [x] Hypium:TruthCheckService 7 例 + PromptBuilder 2 例(用户 GUI 验证 TruthCheckService 通过);KnowledgeModel.test.ets 随类删除,覆盖已迁移(结构化主路径需 LLM 配置,Hypium 与原 KM.test 同样不覆盖)
