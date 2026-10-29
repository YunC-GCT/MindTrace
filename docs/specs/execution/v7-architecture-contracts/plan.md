# v7 契约层与 NoteAgent 迁移 · 执行计划（交接文档）

**Status:** ready-to-execute（2026-10-27，尚未开始写代码）
**基线：** `bugfix/galaxy-web-temporary` @ `dcc7892`；`develop` 停在 `028975e`，落后 3 个提交（都是文档），开工前先把 `develop` 快进到 `dcc7892`。
**范围：** `docs/system-architecture-layered.md` §17.6 的第 1–6 步，只做契约层 + capture 一条迁移；ReviewAgent / Video 由 #242 拍板后再开票。

## 0. 给接手会话

按顺序读：`AGENTS.md` → `docs/agents/phase-tracker.md` → 本文 → `docs/system-architecture-layered.md` §17（重点 17.5 / 17.6 / 17.7）→ `docs/architecture/review-v7-2026-10-27.md`。读完直接开工，不需要回翻历史对话。

## 1. 这一轮已经做完了什么（别重做）

| 提交 | 内容 |
|---|---|
| `028975e` | 架构文档收敛成一份：`docs/system-architecture-layered.md`（旧三份已 `git rm`，历史在 git 里） |
| `64aa14b` | §17 对齐现状：`KnowledgeModel` 已是 **102 行 facade**，`CaptureGraph` 五节点已存在 |
| `44969b8` | 外评审归档 `docs/architecture/review-v7-2026-10-27.md` + 两个 index 入口 |
| `dcc7892` | 按评审改五处：§17.5 六个必填项、§17.6 重排、§3.0 改「LangGraph 工作流模型 + 自建执行器」、§9 重写差距表、§16 更正 `study_plan` / `review_item` |

验证口径（`028975e` 实测，后续改动要维持）：build **5/5 BUILD SUCCESSFUL**、`agent-gate --all` **PASS**、单测 **806/0**、doc-trace **207 files**。

**已经明确不做的事**：`KnowledgeModel` 拆分（`CaptureStructurer` / `DraftComposer` / `DeepDraftComposer` / `IncrementalPatchComposer` / `TruthCheckService` / `PromptBuilder` 都在 10-13、10-14 提交完了，ADR 0006 里「870 行待拆」是当时的现状描述）；三张旧架构图（已作废，新图见 §7）。

## 2. 票单与顺序

| 票 | 标题 | 依赖 | 说明 |
|---|---|---|---|
| [#237](https://github.com/YunC-GCT/MindTrace/issues/237) | ADR：修订 0008 放开 Subgraph + 新增 `NoteCommand` / `NoteOutcome` | 无 | **先做**，错误码与终态定不下来后面全返工 |
| [#238](https://github.com/YunC-GCT/MindTrace/issues/238) | 六个 Port + entry adapter + 契约测试 | #237 | 契约必须先于子图（评审指出的依赖倒置） |
| [#239](https://github.com/YunC-GCT/MindTrace/issues/239) | 四条 dispatch 路径 golden 快照 | 无 | 可与 237/238 并行，是「迁完没变」的唯一判据 |
| [#240](https://github.com/YunC-GCT/MindTrace/issues/240) | spike：父子图共享 RunContext / deadline / cancel | 无 | 3–5 天，任一问题答 no 就停，不进 #241 |
| [#241](https://github.com/YunC-GCT/MindTrace/issues/241) | NoteAgent 薄包装 + 先迁 capture | #237 #238 #240 | 同切片删旧实现，不留 feature flag |
| [#242](https://github.com/YunC-GCT/MindTrace/issues/242) | 拍板：Video 范围、ReviewAgent 领域 | 无 | 产品问题，阻塞 ReviewAgent / Video 两个子图 |

推荐节奏：**#237 与 #239 并行 → #238 → #240（spike 可与 238 并行）→ #241**。

## 3. 硬约束（违反会返工）

- **不改 UI、不改 RDB schema、不改 `agent_config.json`**。加列/加表要单开票并写迁移与回滚。
- `common` 不反依赖 `agents` / `entry`；依赖方向 `entry / skill / cardservice → agents → common`。注意 `scripts/process-boundary/check.mjs` **只查进程可达的 Kit，不查模块依赖方向**，方向靠 review 守。
- 端侧模型是**可插拔能力位**，v1 默认云端；回退必须标「已降级：原因」，不能静默换模型，兜底文案不许冒充回答。
- 思考模式按能力分三类（`toggle` / `always_on` / `unsupported`），未知模型不猜。
- A2A 单一 35s deadline、0 重试、回执短路；**A2A 目前不经过 `Dispatcher`**，纳入主图是独立议题，不要顺手接。
- 只做 local commit；用户明确说 push 才 push。提交信息带 `Refs: #NNN`。
- 结论要有一手来源，查不到就说查不到，不要编。

## 4. 环境与命令

```bash
export DEVECO_SDK_HOME="C:/Program Files/Huawei/DevEco Studio/sdk"
node scripts/build-hsp-hap.mjs                                    # 5/5
node scripts/agent-gate/index.mjs --all < /dev/null                # gate + 单测
HDC="C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe"
"$HDC" kill -r && sleep 3 && "$HDC" list targets -v                # Offline 就杀 server 重连
python scripts/a2a-smoke/a2a_smoke.py --text "本次整理了几条" --wait-seconds 45
node scripts/e2e-capture/run.mjs --with-card --timeout 220
```

装机顺序固定 `common → agents → entry → cardservice`，`hdc install` 只认 `successfully`；`hdc uninstall` 会清掉 preferences 里的模型 API Key。

## 5. 已知坑

- **worktree 里不能判断 ArkTS 报错**（没有 `oh_modules`，全是假错）。先合并回主库再构建。
- `write_file` 不覆盖已存在文件；改文档用 `patch`。
- git-bash 里 `/tmp` 对原生程序（node / python）不可见，临时文件放 `$TMPDIR` 或 `C:/Users/YunCeH/AppData/Local/hermes/cache/scratch`。
- 后台 Codex 沙箱里 `spawnSync node` 会报 EPERM，它报的 gate FAIL 不可信，自己跑一遍为准。
- 回执写入目前是 `TRUNC` + `writeSync`（非原子），`.tmp` + `fileIo.renameSync` 是待修项，见 #236 C 组。

## 6. 并发会话

开工前先 `git worktree list` + `git branch -vv`。当前已知：`bugfix/topic-confirmation-state` 在 `C:/Users/YunCeH/.codex/worktrees/topic-confirmation-state/MindTrace`（另一会话在跑生成模块抽取）；`D:/HMgent/MindTrace-a2a` 与 `D:/HMgent/MindTrace-latency` 是旧 worktree（后者已合并可清）。**不要在没有协调的情况下改同一分支。**

## 7. 图表位置（gitignored，不在仓库里）

- 现状图：`.archify/architecture-mindtrace-asbuilt-20261027-1520/asbuilt.png`
- 目标图：`.archify/architecture-mindtrace-target-v7-20261027-1530/target-v7.png`
- 重画方法：改 `candidate.json` → `archify.mjs finalize architecture … --out-dir <dir> --json`（四 gate 要全 pass）→ Chrome headless 截图 → 人眼查压线/穿框。

## 8. 阻塞与未决

- **#242 两项产品决策**：Video 只产脚本还是上 mp4；`study_plan` 升级成复习计划还是新建 `review_item` / `review_log`（13 张表里都没有）。
- **#236 A/B 组**：真机复验 #233 / #234 / #235，导出 md 正文读不到（`/mnt/user/100/currentUser/other` Permission denied），`model: unknown` 分支。
- 小艺上架审核仍在 P6；平板端侧模型无系统 API。
- 卡片两行恒 0；`similar` 边与 `confidence` 恒 0；包名 `com.example.mindtrace` 仍是占位。

## 9. 完成判据

每票以票内验收为准，共同底线：build 5/5、`agent-gate --all` PASS、单测不低于 806、四件套真机装机后对应流程有截图或日志。#241 额外要求 capture 快照逐字段等价。
