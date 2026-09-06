# MindTrace · 数学学习助手

> 工程: [YunC-GCT/MindTrace](https://github.com/YunC-GCT/MindTrace) · HarmonyOS 数学学习助手
> 作者: YunC-GCT <2549237929@qq.com> · 当前主笔: Z
> 当前版本: **v1.0**(2026-09-04 release) · 阶段: **复赛冲刺**(2026-09-05 ~ 09-08)
> 最近更新: 2026-09-06

MindTrace 通过 **拍照 → OCR → AI 分类 → 知识结构化 → 持久化 → 复习** 的整链,把"看到的数学题"变成"可复习的知识"。5 module: `entry`(HAP) + `common` / `agents` / `skill` / `cardservice`(HSP)。

---

## 一、初赛阶段 (2026-07 ~ 09-01) · 谁做了什么

> 逐日完整日志已收敛至 `docs/legacy/` 与 git 历史; 本节按时间线保留分工与关键交付。

| 时间 | 谁做了什么 |
|---|---|
| W0 (07-12) | **团队**: 5 module 工程脚手架(`bfaa8e5`), 5/5 编译通过 |
| W1 (07-13~14) | **Z**: CommonTypes/logger/uuid/timeWindow/confidenceSort 公共层; 5 Tab + 浮层 UI(Hero/进度环/相机浮层/AI 浮窗/笔记详情); **center 合并**: AI 设置页 + DeepSeek V4 接入(LlmConfig 持久化) |
| D1 拍照链 (07-13~15) | **D/L**: 精简拍照链骨架; CameraOverlay 接真实 cameraPicker; OcrTool 接本地 FastAPI HTTP(公式识别); TypeClassifier 调 DeepSeek 五分类 |
| MVP 合并 (07-17) | **Z**: pages 按目录重组(每页一文件夹); KnowledgeModel/NoteDao 等 MVP 合并进正式类; **整链接入**(`5b6f155`)——拍照→OCR→AI→入库端到端闭环 ✨ |
| W3 (07-19~22) | **Z**: 渲染协议 **MM-MD-v1**(ContentProtocol/LlmGuard/LatexRiskNormalizer 三源归一化 + 公式边界安全摘要); 长正文按需加载与缓存(LRU/二阶段虚拟化); subject 与 category 字段独立; 笔记页结构重设计 |
| W4 (07-23~24) | **Z**: **多 WebView 分块渲染**(FormulaSplitRenderer + LazyForEach), 解决 ArkUI WebView 1800vp 上限; 公式直渲 KaTeX 快 30-50%; UTF-8 乱码修复 |
| 09-01 | **Z**: 全库架构审计(21 finding + 7 大文件深读); 自研 **arkts-lint v0.3 AST 引擎**(34 规则)+ GitHub Actions 三 job CI |
| 09-04 | **YunC-GCT**: **v1.0 release**; 3 人 Git Flow 团队手册 + CODEOWNERS + 分支保护 |

初赛完整方案与逐日记录: [`docs/legacy/mindtrace/plans/`](./docs/legacy/mindtrace/plans/w4/formula-split-render-plan-2026-07-24.md) · 架构审计: [`docs/legacy/mindtrace/architecture/audit-full-2026-09-01.md`](./docs/legacy/mindtrace/architecture/audit-full-2026-09-01.md)。

---

## 二、初赛期结构快照 (2026-07-20 · 供对比)

> 复赛 D3(2026-09-06)已将组件层规范为 `shared/{atoms,molecules,organisms}`, `components/` / `prototypes/` / `archive/` 相继退役。以下为初赛期快照, 保留供对比; 现行结构以 [AGENTS.md](./AGENTS.md)「关键架构」为准。

```
entry/src/main/ets/
├── pages/                     # 每个 page 一个子文件夹
│   ├── Index.ets              # 主容器: 5 Tab + 全局浮层 + 整链触发
│   ├── Home/  Notes/  Profile/  Review/  StudyPlan/  AiSettings/
├── overlays/                  # AgentFloatWindow / CameraOverlay / NoteDetailOverlay
├── prototypes/                # 页面级 UI 原型(后退役)
├── components/ atoms/ molecules/   # 组件层(D3 后统一为 shared/*)
├── database/                  # DatabaseHelper / NoteDao / StudyPlanDao
├── viewmodels/  services/  utils/
common/src/main/ets/
├── models/  constants/  tools/  data/  llm/
agents/src/main/ets/
├── agents/  (TypeClassifier / KnowledgeModel)
├── core/    (Dispatcher)
└── mcp/tools/  (OcrTool)
```

---

## 三、复赛冲刺 (2026-09-05 起) · 谁做了什么

> **更新策略**(沿初赛冲刺惯例): 冲刺期间本节按日期追加, 每条 ≤ 1 屏; 更早条目压缩进初赛节或 `docs/legacy/`。架构决策落 [`docs/adr/`](./docs/adr/index.md), 实施计划落 [`docs/specs/`](./docs/specs/index.md)。复赛期由 YunC-GCT 主导方向与裁决, **AI 结对多会话并行**实施。

### 2026-09-05 · Day 1

- **YunC-GCT**: v1.0 release; Git Flow 团队手册 + 分支保护 rulesets。
- **AI 结对**: D2 spec 011 落地——Dispatcher 单入口 + **CaptureGraph**(LangGraph 设计模型的 ArkTS 原生承载, ADR-0008): 节点 capture→classify→structure→truth_check→persist(条件边), AI 失败显式报错不造假笔记; Node 守门测试体系建立。

### 2026-09-06 · Day 2 (多会话并行)

- **YunC-GCT**: 全部方向裁决(Kit 延后→F3 最小闭环、命名裁决、UI 暂不动); 全量 Hypium 真机验证。
- **治理与文档 (主会话)**: 治理刷新(specs/ADR 状态全量同步); **README 维护本页**; 全仓工具清点 + 演示脚本 + 交接报告; 双轴审查(笔记入库链路确认无损)与硬伤清理。累计 **12 ADR + 11 spec**。
- **拆分收口 (主会话, spec 015)**: KnowledgeModel 878 行 god class → **554 行轻量编排 agent**(名字经裁决保留), 拆出 PromptBuilder(提示词 49 行)与 TruthCheckService(真值检查 283 行); 全程纯提取, 字节级 diff 证据存 PR #40/#41。
- **LLM 工具化 (并行会话, spec 014)**: `call(request)` 单一调用入口(真 SSE); 工具调用协议 + ToolRegistry + ToolLoop 落地 `common/src/main/ets/tools/`; **F1 P1 只读工具**(note_query 等)实现。
- **其他 (并行会话)**: spec 007 PR1 IntentClassifier 自 AgentChatService 抽出; 全仓 agent 工具清点报告。

### 2026-09-06 · entry 层 (主会话)

- **F2 小步先修**: StudyPlan AI 生成抽到 `services/StudyPlanService`(ViewModel 回归 UI 状态层)。
- **F3 Kit 接线**: `kit/ReminderFacadeImpl`(reminderAgentManager 日历提醒)实现并组合根注入; UI 入口按裁决暂不挂, 守门反向锁定。
- 双轴审查结论: **笔记入库链路无损**(持久化关键文件零触碰)。

---

## 四、工程化与质量

| 项 | 现状 |
|---|---|
| 编译 | 5/5 module BUILD SUCCESSFUL(DevEco GUI 或 hvigor CLI 均可) |
| ArkTS 守门 | 自研 AST lint(34 规则, CI 三 job)+ naming-lint + link-check |
| 测试 | Node 测试套件(数量以 `npm --prefix scripts/arkts-lint test` 输出为准)+ Hypium(TruthCheck 7 / PromptBuilder 2 / CaptureGraph 3, DevEco GUI 执行) |
| 文档守门 | link-check 全库死链清零; ADR/spec 状态列随实现 PR 同步(团队手册 PR 检查单) |

---

## 五、构建与运行

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

## 六、资料定位 (文档地图)

| 要找什么 | 去哪 |
|---|---|
| Agent 工作入口(红线 + 必读指针) | [AGENTS.md](./AGENTS.md) — **第一个必读** |
| 项目词汇表(术语消歧) | [CONTEXT.md](./CONTEXT.md) |
| 全部文档导航 | [docs/index.md](./docs/index.md) |
| 架构决策(why) / 实施计划(how) | `docs/adr/`(12 篇, [索引](./docs/adr/index.md)) · `docs/specs/`(11 篇, [索引](./docs/specs/index.md)) |
| 调研 / 架构体检 / 演示与交接 | `docs/research/` · `docs/architecture/`([工具清点](./docs/architecture/agent-tools-inventory-2026-09-06.md)) · `docs/agents/`(含 [演示脚本](./docs/agents/demo-script-2026-09-06.md) · [交接报告](./docs/agents/handoff-2026-09-06.md)) |
| 编码规范 / 文件头模板 | `docs/style/arkts-1.1.md` · `docs/agents/file-header-template.md` |
| 初赛存档(冻结, 勿新增) | `docs/legacy/`([说明](./docs/legacy/index.md)) |

已舍弃的方案文档(初赛期旧方案原文、archived MVP 清单等)不再于本文件引用; 需要考古走 `docs/legacy/` 与 git 历史。
