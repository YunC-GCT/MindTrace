# Research index

> **Scope**: 调研产物索引(一手底料 + 项目定位 + 架构体检)。
> **Convention**: `<topic-slug>-YYYY-MM-DD.md` (kebab-case),HTML 镜像同 slug。
> **Source-of-truth**: 本目录文件均为 research 一次性产物,落定后不再修改;新版本开新文件并把旧的挪 `docs/legacy/`。

## Active

| File | Date | Topic | Status |
|---|---|---|---|
| [`project-positioning-2026-09-04.md`](./project-positioning-2026-09-04.md) | 2026-09-04 | 项目定位(摘要 + 详细双节),团队对齐与评委 pitch 用 | active |
| [`harmonyos-kits-survey-2026-09-05.md`](./harmonyos-kits-survey-2026-09-05.md) | 2026-09-05 | 12 个官方 kit 家族能力 + MindTrace 适配点 + 成本档位;P0 = FormKit/Reminder/BackgroundTasks,P1 = AIEngine/NLP | active (D4 依据) |
| [`agent-toolkit-and-skill-dispatch-2026-09-06.md`](./agent-toolkit-and-skill-dispatch-2026-09-06.md) | 2026-09-06 | 工具层 / 小艺 skill 调度设计;ToolRegistry 落位 common/agents;ADR-0008 复核;**与 CaptureGraph 处理链无关** | active (正交) |
| [`langgraph-mapping-verification-2026-09-06.md`](./langgraph-mapping-verification-2026-09-06.md) | 2026-09-06 | LangGraph 概念 ↔ 鸿蒙 Kit API 逐行核查,API 24 vs 26 边界 (AgentExtensionAbility/A2A/agentConstant = API 26 roadmap);**不涉及 CaptureGraph 处理链** | active (正交) |
| [`chat-markdown-latex-render-jank-2026-09-13.md`](./chat-markdown-latex-render-jank-2026-09-13.md) | 2026-09-13 | 聊天流式结束一次性渲染卡顿因果链 + 预缓存缺口 (MATH_RENDER_CACHE 只省 KaTeX 不省 WebView) + 官方离线Web组件池/保活/KaTeX output 裁剪 + 修复排序;发现 EntryAbility 引擎预热回归丢失 (P0 恢复) | active |
| [`capturegraph-architecture-evolution-2026-09-16.md`](./capturegraph-architecture-evolution-2026-09-16.md) | 2026-09-16 | **CaptureGraph Agent workflow 唯一权威研究**: 合并 7 旧份 (基线/否决提案/实施日志/全链/工具+模式/包装路径双调研),含当前取向与趋向 (§3) + 当前架构 (4 workflow, §4) + **笔记生成完整调度链 (§5, Plan-and-Execute + Reflexion + 入库乐观锁)** + **Tool 层架构 (§7)** + **10 agent 设计模式判定 (§8)** + **MCP vs Direct Tool 包装决策 (§10.6, Direct 全 4 项)** + 16 决策一致性 + drift/开放项;接后端新人 30 分钟入口 | active (权威) |
| [`harmonyos-3d-rendering-kits-survey-2026-09-23.md`](./harmonyos-3d-rendering-kits-survey-2026-09-23.md) | 2026-09-23 | **HarmonyOS 3D 渲染套件调研**: ArkGraphics 3D (`Component3D` + `@kit.ArkGraphics3D`) / WebView + Three.js / WebView + Babylon / WebGPU / XComponent + NDK / OffscreenCanvas 6 路径横向对比 + Camera.raycast API 20+ / Mat4x4 API 23+ / MSAA API 22+ / Effect API 21+ / ImageStream API 26+ / ShadowAlgorithmType API 26+;含 .shader JSON + SPIR-V 资源格式 + 三阶段 POC/P1/P2 路线图 + 5 个 P0 micro-benchmark;KnowledgeGalaxy 决策依据 | active |

临时原料 [`_positioning-facts-2026-09-04.md`](./_positioning-facts-2026-09-04.md)(下划线前缀)按约定不入正式索引。

## Cross-reference

- 关联审计: [`../legacy/mindtrace/architecture/audit-full-2026-09-01.md`](../legacy/mindtrace/architecture/audit-full-2026-09-01.md)
- ADR / Spec: [`../adr/`](../adr/) / [`../specs/`](../specs/)

## Naming convention

| 类别 | 规则 |
|---|---|
| 调研文档 | `<topic-slug>-YYYY-MM-DD.md` |
| 临时原料 | `_<topic-slug>-YYYY-MM-DD.md`(下划线前缀,不入正式索引) |
| HTML 镜像 | 同 slug `.html`,与 md 并列 |
| 归档 | 移入 `docs/legacy/mindtrace/research/` 后保留日期与 slug |

## Maintenance

- 新增调研:复制 `docs/template/research-*.md` 模板,文件名按 `<topic-slug>-YYYY-MM-DD.md` 命名
- 索引追加:在本表 Active 段加一行,标注日期 / 主题 / 状态
- 归档:旧调研从 Active 移到 Legacy 段,文件本身保留

## Last updated

2026-09-16 (第四次合稿: 2 个后台 agent 完成 MCP vs Direct Tool 包装方式调研,合并到 §10.6 — Direct 全 4 项;§10.5 11-item 决策矩阵 + §10.6 包装决策表 + D1-D5 新 drift;挪 2 份调研到 legacy)

## Superseded (已归档, 留作决策历史)

- [`docs/legacy/mindtrace/research/agent-framework-comparison-2026-09-02.md`](https://github.com/YunC-GCT/MindTrace/blob/develop/docs/legacy/mindtrace/research/agent-framework-comparison-2026-09-02.md) — pre-D2 基线 (159 LOC Dispatcher + 929 LOC god class)
- [`docs/legacy/mindtrace/research/langgraph-migration-2026-09-02.md`](https://github.com/YunC-GCT/MindTrace/blob/develop/docs/legacy/mindtrace/research/langgraph-migration-2026-09-02.md) — Python sidecar 迁移提案 (3 条具体原因未采纳, 详见 §3.2)
- [`docs/legacy/mindtrace/research/capturegraph-processing-chain-2026-09-16.md`](https://github.com/YunC-GCT/MindTrace/blob/develop/docs/legacy/mindtrace/research/capturegraph-processing-chain-2026-09-16.md) — 当日 earlier 全链 map (第一版合并后被取代)
- [`docs/legacy/mindtrace/research/capturegraph-tool-layer-and-patterns-2026-09-16.md`](https://github.com/YunC-GCT/MindTrace/blob/develop/docs/legacy/mindtrace/research/capturegraph-tool-layer-and-patterns-2026-09-16.md) — 当日 Tool 层 + 设计模式研究 (第二版合并进 §7+§8)
- [`docs/legacy/mindtrace/research/tool-packaging-mcp-path-2026-09-16.md`](https://github.com/YunC-GCT/MindTrace/blob/develop/docs/legacy/mindtrace/research/tool-packaging-mcp-path-2026-09-16.md) — MCP 路径调研 (第四版合并进 §10.6)
- [`docs/legacy/mindtrace/research/tool-packaging-direct-kit-path-2026-09-16.md`](https://github.com/YunC-GCT/MindTrace/blob/develop/docs/legacy/mindtrace/research/tool-packaging-direct-kit-path-2026-09-16.md) — Direct Tool 路径调研 (第四版合并进 §10.6)
