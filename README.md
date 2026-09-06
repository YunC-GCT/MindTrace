# MindTrace · 数学学习助手

> 工程: [YunC-GCT/MindTrace](https://github.com/YunC-GCT/MindTrace) · HarmonyOS 数学学习助手
> 作者: YunC-GCT <2549237929@qq.com> · 当前主笔: Z
> 当前版本: **v1.0**(2026-09-04 release) · 阶段: **复赛冲刺**(2026-09-05 ~ 09-08)
> 最近更新: 2026-09-06

MindTrace 通过 **拍照 → OCR → AI 分类 → 知识结构化 → 持久化 → 复习** 的整链,把"看到的数学题"变成"可复习的知识"。5 module: `entry`(HAP) + `common` / `agents` / `skill` / `cardservice`(HSP)。

---

## 一、初赛成果精华 (2026-07 ~ 09-01, 详情见 docs/legacy/)

| 成果 | 说明 | 存档 |
|---|---|---|
| **整链闭环** | 拍照 → OCR(自研 FastAPI 双路径: 端侧 CoreVisionKit 兜底 + PC 公式服务) → AI 五分类 → KnowledgeUnit 结构化 → RDB 入库 | 架构总览见 [AGENTS.md](./AGENTS.md)「关键架构」 |
| **渲染协议 MM-MD-v1** | AI/OCR/历史三源统一归一化; LlmGuard 多通道输出守卫; 摘要按公式边界安全截断 | [渲染协议方案](./docs/legacy/mindtrace/plans/w3/render-protocol-optimization-route-2026-07-22.md) |
| **多 WebView 分块渲染** | 解决 ArkUI WebView 1800vp 上限: FormulaSplitRenderer + LazyForEach 按需挂载, 公式块直渲 KaTeX 快 30-50% | [分块渲染方案](./docs/legacy/mindtrace/plans/w4/formula-split-render-plan-2026-07-24.md) |
| **全库架构审计** | 21 项 finding + 7 大文件深读, 催生后续全部 ADR/spec | [audit-full-2026-09-01](./docs/legacy/mindtrace/architecture/audit-full-2026-09-01.md) |
| **arkts-lint + CI** | 自研 AST lint 引擎(34 规则) + GitHub Actions 三 job 守门, 规则手册 [arkts-1.1.md](./docs/style/arkts-1.1.md) | 引擎与测试在 `scripts/` |

初赛期的逐日开发日志、旧目录结构树、commit 索引已整体移入 `docs/legacy/` 与 git 历史, 本文件不再引用。

---

## 二、复赛冲刺日志 (2026-09-05 起)

> **更新策略**(沿初赛冲刺惯例): 冲刺期间本节按日期追加日志, 每条 ≤ 1 屏; 更早的条目压缩进"初赛成果精华"或移入 `docs/legacy/`。架构决策一律落 `docs/adr/`, 实施计划落 `docs/specs/`。

### 2026-09-05 ~ 09-06 · Day 1-2

- **D1-D4 决策全部落 ADR**: OCR 保留自研、其余主链路 Kit 化走"契约在 common / 实现注入 entry"接缝([ADR-0009](./docs/adr/0009-kit-facade-injection-boundary.md)); 自研 CaptureGraph 承载 LangGraph 设计模型([ADR-0008](./docs/adr/0008-capturegraph-self-built-runtime.md)); LLM 工具调用协议([ADR-0012](./docs/adr/0012-tool-calling-protocol.md)); `skill/` 保留为小艺预留位([ADR-0011](./docs/adr/0011-skill-xiaoyi-reservation.md))。累计 **10 ADR + 15 spec**。
- **后端 CaptureGraph 落地**(spec 011): Dispatcher 单入口, 图节点 capture→classify→structure→truth_check→persist(条件边), AI 失败抛结构化错误、不生成 fallback 假笔记。
- **结构化拆分收口**(spec 015): KnowledgeModel 重构为 554 行轻量编排 agent, 拆出 PromptBuilder(提示词)/TruthCheckService(真值检查)协作服务; 全程纯提取, 类体字节级 diff 证据存 PR #40/#41。
- **LLM 工具化**: `call(request)` 单一调用入口(真 SSE 流式); 工具调用协议 + ToolRegistry + ToolLoop 落地 `common/src/main/ets/tools/`(spec 014, 只读工具先行)。
- **Kit 接线**: ReminderFacadeImpl 实现并组合根注入(`entry/src/main/ets/kit/`, spec 013); UI 入口按裁决暂不挂。
- **分层修正**: StudyPlan AI 生成抽到 Service 层; StudyPlan/笔记入库链路经双轴审查确认无损。
- **复赛就绪**: [演示脚本与赛前检查清单](./docs/agents/demo-script-2026-09-06.md)、[交接报告](./docs/agents/handoff-2026-09-06.md)、[全仓工具清点](./docs/architecture/agent-tools-inventory-2026-09-06.md)。

---

## 三、工程化与质量

| 项 | 现状 |
|---|---|
| 编译 | 5/5 module BUILD SUCCESSFUL(DevEco GUI 或 hvigor CLI 均可) |
| ArkTS 守门 | 自研 AST lint(34 规则, CI 三 job)+ naming-lint + link-check |
| 测试 | Node 测试套件(数量以 `npm --prefix scripts/arkts-lint test` 输出为准)+ Hypium(TruthCheck 7 / PromptBuilder 2 / CaptureGraph 3, DevEco GUI 执行) |
| 文档守门 | link-check 全库死链清零; ADR/spec 状态列随实现 PR 同步(团队手册 PR 检查单) |

---

## 四、构建与运行

```bash
# 1. OCR 服务 (Windows PC)
tools/ocr_service/start.bat          # 端口 8000; 真机需在 App 内把 endpoint 改为 PC 局域网 IP

# 2. 构建/运行
DevEco Studio: Build → Build Hap(s)/APP(s), Run → Run 'entry'
# 或 hvigor CLI (AI 可主动调用; 环境变量见 docs/agents/d2-capturegraph-teaching-2026-09-05.md §6.11)

# 3. LLM 配置
App 内 我的 → AI 设置: DeepSeek API Key + 连接测试
```

完整演示流程(5 分钟 8 步)、失败降级口径、赛前检查清单见 [docs/agents/demo-script-2026-09-06.md](./docs/agents/demo-script-2026-09-06.md)。

---

## 五、资料定位 (文档地图)

| 要找什么 | 去哪 |
|---|---|
| Agent 工作入口(红线 + 必读指针) | [AGENTS.md](./AGENTS.md) — **第一个必读** |
| 项目词汇表(术语消歧) | [CONTEXT.md](./CONTEXT.md) |
| 全部文档导航 | [docs/index.md](./docs/index.md) |
| 架构决策(why) / 实施计划(how) | `docs/adr/`(10 篇, [索引](./docs/adr/index.md)) · `docs/specs/`(15 篇, [索引](./docs/specs/index.md)) |
| 调研 / 架构体检 / 演示与交接 | `docs/research/` · `docs/architecture/`([工具清点](./docs/architecture/agent-tools-inventory-2026-09-06.md)) · `docs/agents/`(含 [演示脚本](./docs/agents/demo-script-2026-09-06.md)) |
| 编码规范 / 文件头模板 | `docs/style/arkts-1.1.md` · `docs/agents/file-header-template.md` |
| 初赛存档(冻结, 勿新增) | `docs/legacy/`([说明](./docs/legacy/index.md)) |

已舍弃的方案文档(初赛期旧结构树、archived MVP 清单、被 supersede 的 ADR 原文等)不再于本文件引用; 需要考古走 `docs/legacy/` 与 git 历史。
