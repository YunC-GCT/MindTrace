# 笔记可追溯复习回答测试方案（2026-09-26）

对应规格：[024-note-review-answer.md](024-note-review-answer.md)。此文件不维护进度；所有结果由唯一主计划登记。

## 执行矩阵

| 需求 | 输入/场景 | 预期与证据 |
|---|---|---|
| AC-REVIEW-01 | 五类中文请求、普通聊天、整理笔记、图片草稿、模糊代词 | 正确只读路由或澄清；生成路线不回归；行为测试实际调用生产策略 |
| AC-REVIEW-02 | 自然语言主题、双主题只命中一个、重复来源、大上下文 | 有界调用/去重/预算；比较不把同一来源冒充两组 |
| AC-REVIEW-03 | 空库、查询抛错、store 未就绪、图谱故障 | 不调用答案模型；无命中与失败原因不同；独立直接来源可降级解释 |
| AC-REVIEW-04 | A→B、B→C、related、环、pending/rejected/derived、删除邻居 | B 的前置包含 A，不误报 C；只 accepted，深度/节点受限 |
| AC-REVIEW-05 | 正确引用、虚构 ID、错误版本、缺版本、流块逐字符拆分、未闭合标记、空引用集 | complete 与 stream 过滤一致；最终来源只包含允许引用；无引用不能 grounded |
| AC-REVIEW-06 | 请求 0/1/5/99 道题、摘录嵌入越权指令、模型失败 | 数量约束；数据边界提示；失败可见、不声称已基于笔记成功 |
| AC-REVIEW-07 | 当前版本、编辑后原版本、删除后打开、版本不存在、RDB 异常 | 调用真实 resolver 搭配 DAO 替身；展示对应状态；历史不能复活删除内容 |
| AC-REVIEW-08 | 拷贝、stream/replace/finish、序列化/重启、旧消息、坏元数据、反馈换选 | 引用/反馈保持，深拷贝隔离，重复选择幂等；UI 回调接入有结构检查 |
| AC-REVIEW-09/10 | 全量回归、lint、命名、diff、Hvigor | 逐命令退出码；不能只跑 npm 的较小套件当作全量 |

## 测试方式

- 独立测试 Agent 在基线 worktree 记录 git SHA/状态和现有全量结果，开发提交后移植已提交实现。
- Node 行为测试可用已有 TypeScript 转译器加载生产 .ets 中无 ArkUI 的逻辑；Kit/DAO 使用明确测试替身，不能复制生产算法后测试复制品。
- UI 连线可用结构断言检查，交互和真实布局另列为待设备验收；如写 Hypium 必须注册入口。
- source resolver、流式过滤、分类、上下文预算、消息快照分别覆盖正反例；记录测试变更原因。
- 固定命令：node --test "scripts/arkts-lint/tests/*.test.mjs"；node scripts/arkts-lint/index.mjs --quiet；node scripts/naming-lint/index.mjs；git diff --check <baseline>..HEAD；Hvigor assembleHap。
- 基线现有失败先记名、行号、命令和归因，不归咎环境而无复现，不改无关测试换绿。

## 交付证据

记录 baseline/final commit，测试总数、pass/fail/skip，失败完整名称/行号，所有断言变更原因，实现 SHA-256，原始日志、构建退出码和 warning，未执行层级及原因。日志放工作归档本期证据目录，只作附件，不维护平行状态表。

## 待设备场景

旧会话升级→五类问答→流式引用→点开原文→编辑来源后再打开旧引用→删除后打开→反馈→重启→切换会话。记录型号/API、网络、真实模型和 RDB 证据。未连接设备或无服务时不伪造通过；不覆盖 9 月 19 日旧计划仍未完成的设备验收结论。

## 2026-09-27 补充验收用例

- 执行真实 `KnowledgeRelationDao.expandAcceptedPrerequisites`，只替换 RDB 接口，验证 accepted 过滤、方向、环与节点/边上限；不能用 mock DAO 算法来声称 DAO 已通过。
- 验证 6000 字符预算临界点、最终引用与上下文一致、超过 6 个比较主题、任一主题被裁剪、预算完全耗尽、两个 hit 之间存在前置边。
- 逐字符拆分引用，验证非法版本后缀和重复 version 字段；题量覆盖 0/1/5/99。
- 在真实分类节点验证明确复习不调远程分类，且“整理为笔记”“创建笔记”与显式增量指令仍优先走原规则。
- 执行生产 `AgentInputViewModel.send()`，callback 拒绝时不清空文本/图片、不调用 service；允许时保留原 route 传递。反馈 token、跨会话与来源浮层连线可加结构检查，但不能冒充真机交互测试。
- 构建前在独立候选 worktree 执行 `ohpm install --all`；通过已安装 DevEco 的 Hvigor 绝对路径运行构建并记录工具/SDK版本。仅 PATH 找不到命令或本地模块未安装，不足以认定代码构建失败或历史基线错误。
