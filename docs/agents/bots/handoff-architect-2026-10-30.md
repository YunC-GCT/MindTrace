# Bot 交接单 · architect（2026-10-30）

> 交接人：Hermes 主线 session · 接收：architect（gpt-5.6-sol）· 状态：**任务 1 已完成**（`ae80f04`：全仓「1 HAP + 4 HSP」改为 3 HAP + 2 HSP，含 AGENTS.md / onboarding / ADR-0011·0012 / arkts-ai-coding / specs）；任务 2（ADR-0020）待接手
> 基线：worktree `D:/HMgent/MindTrace-chat`，分支 `feature/a2a-text-ingest` @ `dac64c3`（**未 push**）
> 本轮前情：端A2A 图片通道查证完毕（协议支持、客户端不填 `parts`），随后加了「对话内 UI 卡片 + 跳转」这套官方引导通道。结论与证据在 [`docs/research/a2a-image-input-feasibility-2026-10-29.md`](../../research/a2a-image-input-feasibility-2026-10-29.md)。

## 一、必须知道的事实（已核实，别再查一遍）

1. **模块拓扑与 AGENTS.md 不符**：实际是 **2 个 HSP + 3 个 HAP**——`common` / `agents` 的 `hvigorfile.ts` 用 `hspTasks`、`module.json5` 里 `type: "shared"`；`skill` / `cardservice` 用 `hapTasks`、`type: "feature"`；`entry` 是 `type: "entry"`。而 `AGENTS.md` 写的是「1 HAP + 4 HSP」。
2. **入口层新增两件东西**：`entry/src/main/ets/agentextability/A2AUiCard.ets`（`uiExtensionCard` 指令构造 + 意图判定，纯字符串）与 `entry/src/main/ets/pages/AgentUiCard.ets`（半屏卡片页，走 `agentUI` 扩展）。它们和外来的 `AgentIngestService` / `OcrService` 一起，构成「小艺入口层」。
3. **图片通道定性**：`@hms.ai.A2A.d.ts` 的 `Part` 只有 `text/raw/url/data/mediaType/filename/metadata` 七字段，官方明确「在线文件通过 url、filename、mediaType 描述，支持双向传递」；`AgentCapabilities` 无图片字段；`AgentHostProxy` 只有 `sendData`/`authorize`。真机上小艺侧 `uploadToObs` 成功、待发送区有缩略图，但发出的报文 `parts` 只有 `[{"mediaType":"text/plain"}]`（475 B），整机 366 MB 日志里 `"mediaType":"image` **0 命中**。
4. **`phase-tracker.md` 内部口径已经打架**：第 7 / 23 行说「P1 的『小艺拉起应用选图』不在 v1 范围、`agentUI` 返回 1011 已移出」；第 32 行仍写「`handleTask` 只把文本交给 `ReplyService`，所以小艺只能对话」——这条已被 `64008c3`（就地入库）推翻。另外第 47 行命令路径 `scripts/a2a_smoke.py` 不存在，实际是 `scripts/a2a-smoke/a2a_smoke.py`。
5. **1011 的成因已有解释**：spec 031 §4.9 那次只发了 `{"uiExtensionCard":{"payload":{...}}}`，缺 `cardId`、`bundleName` 两个必填字段，`payload` 还写成了对象。官方字段要求见研究文档「补充」节。

## 二、任务（按优先级）

1. **裁模块拓扑并落文档**：确认 2 HSP + 3 HAP 才是 as-built，改 `AGENTS.md` 的拓扑段与 `docs/` 里所有「4 HSP」表述。`AGENTS.md` 属受保护文件，**改之前先向用户要一次明确批准**，批准后一次改干净，别留两套说法。
2. **写 ADR**：`docs/adr/` 取下一个空号，主题「端侧 A2A 入口分层：图片、引导卡片与跳转」。必须四段齐全（背景 / 决策 / 代价 / 被否方案）：
   - 背景：客户端不下发图片 part 的实测证据 + 协议本身支持。
   - 决策：图片只从应用内进；小艺侧用 `uiExtensionCard` 引导 + `jump` 兜底；卡片受 `UI_CARD_ENABLED` 开关约束。
   - 代价：卡片依赖客户端渲染能力，`agentUI` 与 `agent` 必须共进程；开关是临时手段，不是长期架构。
   - 被否方案：① 等客户端修（不可控）② 让用户从 OBS 链接自取（拿不到 url）③ 硬编码 fileId 反查（无 API）④ 云 A2A 中转（引入后端，超出 v1 冻结范围）。
3. **出两张图**：as-built 与目标架构并存对照（用户明确要求两张图同屏），标出入口层新增的 `A2AUiCard` / `AgentUiCard` / `AgentIngestService` / `OcrService`，以及「3D 渲染只属 App 进程、OCR 属共享能力」的 Kit 归属（spec 033 R5）。
4. **统一 `phase-tracker.md` 口径**：删掉或改写第 32 行的事实陈述；把「P1 = 应用内批量」与「小艺侧卡片引导」写成互不矛盾的两行；修 `a2a_smoke.py` 路径；卡片真机结果出来后由 harmony 填证据、你只管口径一致性。

## 三、边界（不要碰）

- 任何 `.ets` / `.ts` 源码、`hvigorw`、构建、装机、`hdc`、对外材料。
- 不自行合并 PR、不 push。
- `docs/legacy/` 只读。

## 四、完成与验收

- `node scripts/naming-lint/index.mjs` 与 `node scripts/link-check/index.mjs` 均 0 violation（新文件要登记进 [`docs/adr/index.md`](../../adr/index.md) 或对应目录索引，`doc-trace` 要求每个 md 可被 `docs/index.md` 链到）。
- ADR 编号唯一（`doc-trace` 会查）。
- 交付时贴：改动文件清单 + 两张图路径 + 新增 ADR 号 + 三处口径修正的 diff 摘要。
