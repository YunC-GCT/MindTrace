# Research index

> **Scope**: 调研产物索引（一手底料 + 项目定位 + 架构体检 + 专项研究）。
> **Convention**: `<topic-slug>-YYYY-MM-DD.md`（kebab-case）；一次性原料用 `_<topic-slug>-YYYY-MM-DD.md`，不入正式索引。
> **Source-of-truth**: 本目录文件均为 research 一次性产物，落定后不再修改；新版本开新文件并把旧的挪 `docs/legacy/`。

## Active

| File | Date | Topic | Status |
|---|---|---|---|
| [`project-positioning-2026-09-04.md`](./project-positioning-2026-09-04.md) | 2026-09-04 | 项目定位（摘要 + 详细双节），团队对齐与评委 pitch 用 | active |
| [`harmonyos-kits-survey-2026-09-05.md`](./harmonyos-kits-survey-2026-09-05.md) | 2026-09-05 | 12 个官方 kit 家族能力 + MindTrace 适配点 + 成本档位；P0 = FormKit/Reminder/BackgroundTasks，P1 = AIEngine/NLP | active (D4 依据) |
| [`agent-toolkit-and-skill-dispatch-2026-09-06.md`](./agent-toolkit-and-skill-dispatch-2026-09-06.md) | 2026-09-06 | 工具层 / 小艺 skill 调度设计；ToolRegistry 落位 common/agents；ADR-0008 复核 | active |
| [`langgraph-mapping-verification-2026-09-06.md`](./langgraph-mapping-verification-2026-09-06.md) | 2026-09-06 | LangGraph 概念 ↔ 鸿蒙 Kit API 逐行核查，API 24 vs 26 边界 | active |
| [`frontend-a11y-audit-2026-09-06.md`](./frontend-a11y-audit-2026-09-06.md) | 2026-09-06 | 前端可访问性摸底 | active |
| [`frontend-component-audit-2026-09-06.md`](./frontend-component-audit-2026-09-06.md) | 2026-09-06 | 前端 UI 组件设计审查（分层裁决 + C1-C6 候选） | active |
| [`frontend-error-handling-2026-09-06.md`](./frontend-error-handling-2026-09-06.md) | 2026-09-06 | 前端错误降级与边界摸底 | active |
| [`frontend-flow-walkthrough-2026-09-06.md`](./frontend-flow-walkthrough-2026-09-06.md) | 2026-09-06 | 前端用户路径走查 | active |
| [`frontend-healthcheck-plan-2026-09-06.md`](./frontend-healthcheck-plan-2026-09-06.md) | 2026-09-06 | 前端体检后续待办合同 | active |
| [`frontend-i18n-audit-2026-09-06.md`](./frontend-i18n-audit-2026-09-06.md) | 2026-09-06 | 前端国际化与文案一致性摸底 | active |
| [`frontend-interaction-states-2026-09-06.md`](./frontend-interaction-states-2026-09-06.md) | 2026-09-06 | 前端交互五态完整性摸底 | active |
| [`frontend-performance-audit-2026-09-06.md`](./frontend-performance-audit-2026-09-06.md) | 2026-09-06 | 前端性能与资源摸底 | active |
| [`frontend-persistence-2026-09-06.md`](./frontend-persistence-2026-09-06.md) | 2026-09-06 | 前端状态序列化与持久化摸底 | active |
| [`frontend-ui-design-inventory-2026-09-06.md`](./frontend-ui-design-inventory-2026-09-06.md) | 2026-09-06 | 前端 UI 设计/布局/动效三维档案（96 件） | active |
| [`harmonyos-multi-device-ui-adaptation-2026-09-08.md`](./harmonyos-multi-device-ui-adaptation-2026-09-08.md) | 2026-09-08 | API 24 一次开发多端部署：手机 / 平板 / 折叠屏 / 2-in-1 | active (spec 022 输入) |
| [`agent-float-window-component-research-2026-09-11.md`](./agent-float-window-component-research-2026-09-11.md) | 2026-09-11 | AgentFloatWindow 组件清点与替换候选 | active |
| [`agent-reasoning-process-display-research-2026-09-11.md`](./agent-reasoning-process-display-research-2026-09-11.md) | 2026-09-11 | 分层可折叠思考与执行过程展示调研 | active (spec 019 依据) |
| [`arkweb-render-pipeline-stability-2026-09-11.md`](./arkweb-render-pipeline-stability-2026-09-11.md) | 2026-09-11 | ArkWeb 渲染链路稳定性与预加载姿势 | active |
| [`llm-json-answer-parsing-2026-09-12.md`](./llm-json-answer-parsing-2026-09-12.md) | 2026-09-12 | LLM JSON answer 解析与转义 | active |
| [`chat-markdown-latex-render-jank-2026-09-13.md`](./chat-markdown-latex-render-jank-2026-09-13.md) | 2026-09-13 | 聊天流式结束一次性渲染卡顿因果链 + 预缓存缺口 + 修复排序 | active (spec 021 依据) |
| [`capturegraph-architecture-evolution-2026-09-16.md`](./capturegraph-architecture-evolution-2026-09-16.md) | 2026-09-16 | **CaptureGraph Agent workflow 唯一权威研究**（合并 7 旧份：架构 / 生成链 / Tool 层 / 包装决策） | active (权威) |
| [`data-presentation-flow-2026-09-16.md`](./data-presentation-flow-2026-09-16.md) | 2026-09-16 | 数据呈现链路调研 | active |
| [`fixture-isolation-result-2026-09-16.md`](./fixture-isolation-result-2026-09-16.md) | 2026-09-16 | 呈现层隔离研究最终报告 | active |
| [`presentation-deep-dive-2026-09-16.md`](./presentation-deep-dive-2026-09-16.md) | 2026-09-16 | 呈现段深度调研 | active |
| [`harmonyos-3d-rendering-kits-survey-2026-09-23.md`](./harmonyos-3d-rendering-kits-survey-2026-09-23.md) | 2026-09-23 | HarmonyOS 3D 渲染套件调研（ArkGraphics 3D / WebView + Three.js / Babylon / WebGPU / XComponent / OffscreenCanvas 6 路径） | active (KnowledgeGalaxy 决策依据) |
| [`note-detail-overlay-state-2026-09-23.md`](./note-detail-overlay-state-2026-09-23.md) | 2026-09-23 | NoteDetailOverlay 现状综合调研 v1.1（22 文件 / 6 挂载点 / 17 已知问题） | active |
| [`note-detail-emulator-acceptance-2026-09-28.md`](./note-detail-emulator-acceptance-2026-09-28.md) | 2026-09-28 | #189 WebKeepAlive off/on 与 #188 公式密集模拟器验收 | active (simulator evidence) |
| [`ocr-llm-preprocessing-2026-09-29.md`](./ocr-llm-preprocessing-2026-09-29.md) | 2026-09-29 | OCR 后的 LLM 预处理链路核查（相机 → OCR → 分类 → 生成 → 持久化） | active |
| [`knowledge-galaxy-mapping-2026-10-18.md`](./knowledge-galaxy-mapping-2026-10-18.md) | 2026-10-18 | 知识星系映射规范表：知识结构 → 三维星系，产品确认与实现对齐 | active (映射契约) |
| [`github-issue-pr-audit-2026-10-18.md`](./github-issue-pr-audit-2026-10-18.md) | 2026-10-18 | GitHub issue / PR 状态对账：已完成未关闭、失效 spec 引用、PR #216 review 阻塞 | active (运维对账) |
| [`docs-traceability-audit-2026-10-18.md`](./docs-traceability-audit-2026-10-18.md) | 2026-10-18 | 文档规范 / 设计冲突 / 可追溯性 / ArkTS-AI coding 可用性审计（9 处冲突修正 + doc-trace 守门） | active (审计结论) |

临时原料 [`_positioning-facts-2026-09-04.md`](./_positioning-facts-2026-09-04.md)（下划线前缀）按约定不入正式索引，供 `project-positioning-2026-09-04.md` 溯源。

## Cross-reference

- 关联审计: [`../legacy/mindtrace/architecture/audit-full-2026-09-01.md`](../legacy/mindtrace/architecture/audit-full-2026-09-01.md)
- ADR / Spec: [`../adr/`](../adr/) / [`../specs/`](../specs/)
- 执行记录: [`../specs/execution/`](../specs/execution/)

## Naming convention

| 类别 | 规则 |
|---|---|
| 调研文档 | `<topic-slug>-YYYY-MM-DD.md` |
| 临时原料 | `_<topic-slug>-YYYY-MM-DD.md`（下划线前缀，不入正式索引） |
| HTML 镜像 | 同 slug `.html`，与 md 并列（不入 git，见 `docs/style/html-in-docs.md`） |
| 归档 | 已被取代的调研在内容并入当前文档后删除（git 历史可查），不再保留 `docs/legacy/mindtrace/research/` |

## Maintenance

- 新增调研：复制 `docs/template/research-template.md`，文件名按 `<topic-slug>-YYYY-MM-DD.md` 命名
- 索引追加：在本表 Active 段加一行，标注日期 / 主题 / 状态
- 归档：旧调研从 Active 移到 Legacy 段，文件本身保留

## Last updated

2026-10-18（目录规范化：补全 20 篇未登记研究；临时原料链接修正；旧研究大清洗——已被取代或描述被否决架构的文档删除，映射见下）

## Superseded / removed

Older research that was fully merged into the authoritative documents above, or that described rejected architectures, was deleted in the 2026-10-18 corpus purge (it remains in git history). The mapping:

| Removed | Now lives in |
|---|---|
| `agent-framework-comparison-2026-09-02`, `langgraph-migration-2026-09-02` | [ADR-0008](../adr/0008-capturegraph-self-built-runtime.md) (decision) + `capturegraph-architecture-evolution-2026-09-16` (current state) |
| `capturegraph-processing-chain-2026-09-16`, `capturegraph-tool-layer-and-patterns-2026-09-16` | [`capturegraph-architecture-evolution-2026-09-16.md`](./capturegraph-architecture-evolution-2026-09-16.md) §5 / §7 / §8 |
| `tool-packaging-mcp-path-2026-09-16`, `tool-packaging-direct-kit-path-2026-09-16` | same file §10.6 (Direct Tool decision) |
| `formula-render-strategies`, `multi-webview-performance`, `harmonyos-http-streaming` (2026-07-24) | [spec 021](../specs/021-chat-streaming-incremental-rendering.md) + `chat-markdown-latex-render-jank-2026-09-13` |
| `huawei-arkui-agent-20260901` | [`docs/style/arkts-1.1.md`](../style/arkts-1.1.md) (rules extracted) |
