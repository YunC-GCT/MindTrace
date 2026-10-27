# 真机三缺陷交接说明（2026-10-27）

给接手的新会话：这份文档是全部上下文。按顺序读 `AGENTS.md` → `docs/agents/phase-tracker.md` → 本文，然后直接开工，不需要回去翻历史对话。

## 1. 你的任务

处理 10-27 真机验证暴露的三条缺陷，已开 issue：

| Issue | 标题 | 状态 |
|---|---|---|
| [#233](https://github.com/YunC-GCT/MindTrace/issues/233) | 详情页把 `$$` 公式块按行拆碎，步骤区出现裸 `$$` | 根因已定位，可直接改 |
| [#234](https://github.com/YunC-GCT/MindTrace/issues/234) | 小艺 A2A 回复里数学表达式被吞成零宽占位 | 需先做 A/B/C 对照实验，再定策略 |
| [#235](https://github.com/YunC-GCT/MindTrace/issues/235) | 批量抓取单张 85.5s/31.6s：先补阶段耗时再谈优化 | 先测量，别先优化 |

建议顺序：**#235（先测量，产出数据）→ #233（纯端侧逻辑，风险低）→ #234（涉及输出策略，要拍板）**。
#233 与 #235 可并行；#234 依赖 #235 的日志打点能力（同一个 `Logger`/tag 体系）。

## 2. 当前基线

- 仓库：`D:\HMgent\MindTrace`，分支 `bugfix/galaxy-web-temporary`
- HEAD：`978585d merge feat/xiaoyi-latency-tuning`（10-27）
- 这次合并把「模型适配分层 + A2A 35s 预算 + 768 项单测」并入 v1 收尾线；合并后 **构建 5/5 成功、gate PASS、单测 768/0**
- 工作区干净；两个 galaxy 背景图（`entry/src/main/resources/base/media/galaxy_*_bg.png`）已由用户确认删除（`8b6be9f`），当前代码已无引用，不要恢复。
- 相关旧分支：`feat/231-capture-receipt`、`feat/232-ai-compliance` 已合并并删除；`feat/xiaoyi-latency-tuning` 已合并但分支与 worktree `D:/HMgent/MindTrace-latency` 还在，真机回归通过后可清理。

## 3. 环境与命令（都已验证）

唯一 IDE：`C:\Program Files\Huawei\DevEco Studio`（DevEco Studio 26 / SDK API 26）。旧 6.1.1.300 已删除，不要引用。

```bash
# 构建（五步：common HSP -> 新鲜度 -> agents HSP -> entry HAP -> cardservice HAP）
export DEVECO_SDK_HOME="C:/Program Files/Huawei/DevEco Studio/sdk"
node scripts/build-hsp-hap.mjs            # rc=0 且五段 BUILD SUCCESSFUL

# 门禁（含 768 项 node 单测、arkts-lint、process-boundary、doc-trace）
node scripts/agent-gate/index.mjs --all < /dev/null

# 装机 + 批量链路自检（自动装四件套：common -> agents -> entry -> cardservice）
node scripts/e2e-capture/run.mjs --with-card --timeout 220

# 小艺 A2A 冒烟
python scripts/a2a-smoke/a2a_smoke.py --text "本次整理了几条" --no-restart --wait-seconds 45
```

构建注意：

- **不要重定向 stdin** 到 hvigor（`< /dev/null` 只给 gate/检查脚本用，给构建会让它直接 `stdin is not a tty` 退出）。
- `hdc install` 失败也会打印 `AppMod finish`，成功判据只认 `successfully`；`run.mjs` 已按此判定。
- worktree 里**不能判断编译**（缺 `oh_modules`，会冒出几百条假 ArkTS 错误）：先合回主库再构建。
- 装 HSP 顺序错了或漏 `agents`，会报 `9568305 dependent module: agents does not exist`。

设备：

```bash
HDC="C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe"
"$HDC" kill -r && "$HDC" list targets -v      # IDE 更新后常出现 Offline，重启 server 即恢复
"$HDC" shell "power-shell wakeup; power-shell timeout -o 1800000"
"$HDC" shell "aa start -a EntryAbility -b com.example.mindtrace -m entry"
"$HDC" shell "snapshot_display -f /data/local/tmp/x.jpeg"
"$HDC" shell "uitest dumpLayout -p /data/local/tmp/l.json"   # 取 bounds 再 uitest uiInput click
"$HDC" shell "hilog -x | grep -E 'MindTrace|A0C5D0|NoteExport'"
```

坑：

- 屏幕锁定会让 `aa start` 返回 `10106102`，脚本会立刻失败——先 wakeup。
- `hdc file recv` 的目标路径要用 MSYS 相对写法（`cd` 到目录再传文件名），传 `C:/...` 绝对路径会被 hdc 拼成相对路径而报 `no such file`。
- 用户空间 `/mnt/user/100/currentUser/other` 对 shell 是 `Permission denied`，**导出的 md 无法从 hdc 直接读**；验证内容只能靠单测或应用内打点。

密钥：模型 API Key 在应用 preferences 里，用户自己填（当前 `keys=1`，`deepseek-flash` 可用）。助手不读、不代填、不在日志/文档里复述。

## 4. 已经验过的事实（不要重复做）

10-27 真机，合并后构建：

| 项 | 结果 |
|---|---|
| 批量抓取 | 2/2 成功，`stage=done ok=2 failed=0`，但单张 85.5s / 31.6s（见 #235） |
| 文搜图 | `一元二次方程 hits=2`、`平方根 hits=2`（worker 路径） |
| 卡片 | `units=13 due=8 new=2`，`stage=card refresh=1` |
| A2A 回执 | 「本次整理 2 条：成功 2 条，失败 0 条（13:58）。」`[Receipt] hit=true`，未调模型 |
| A2A 模型 | 「用一句话解释什么是平方根」697ms，61 字，快照 350 字节，`reason=OK attempts=1` |
| #232 导出 | 「AI 生成」标签正常；保存面板默认名 `mindtrace-KB-...-20261027.md`；取消无报错；保存 `export ok bytes=1952` |

还没验的：hypium 单测真机结果（`entry/src/test` 的 16 条），导出文件的**实际 front-matter 内容**（受权限限制），`model: unknown` 触发路径。

## 5. 三条缺陷的落点

### #233 公式块被拆碎

- 根因：`splitReadableLines`（`entry/src/main/ets/overlays/NoteDetailOverlay/model/DetailRenderModel.ets:165`）按 `\n` 无条件切行，`$$` 围栏被切成三条独立步骤。
- 调用方：`ComputationDetailView.ets:109`、`ProofDetailView.ets:28`。
- 改法：切行前按围栏成块（含未闭合兜底），补 5 组单测；用 `GalaxyPreviewData.ets:75` 的多段 `$$` 做回归样本。
- 不要动 `DetailStepList` 的排版，只修切分。

### #234 A2A 数学被吞

- 日志显示模型调用成功、快照 350 字节、无异常，**怀疑丢在小艺渲染层**，但未证实。
- 第一步：在 `AgentExtAbility.sendAnswer` / `TaskSnapshot` 打 `chars=`、`bytes=`，确认快照正文完整。
- 第二步：A/B/C 三组对照（原样 LaTeX / 纯文本数学 / 中文描述），用 `scripts/a2a-smoke/a2a_smoke.py` 各跑一次，把 `reply_text` 长度对比写进 issue。
- 若确认是小艺渲染层：A2A 通道统一要求纯文本数学（`√a`、`a≥0`、`2.646`），在 `ReplyService` 的 A2A 策略里加约束；**App 内聊天气泡保持公式渲染，不要一刀切**。
- 这条改的是「输出策略」，动之前先在 issue 评论里给出结论，让用户拍板。

### #235 抓取变慢

- `[AiService] capture start` → `done` 之间只有一行日志，OCR/分类/草稿/落库各占多久不可见。
- 先在 `AiService.processAndPersist` 与 agents 侧 `Dispatcher` 打 5 段 `ms=`（resolve / ocr / classify / draft / persist），把新 tag 加进 `scripts/e2e-capture/run.mjs` 的 `hilog -T` 过滤。
- 拿到数据再决定优化点；**不要为了压数字关掉清洗或纠错步骤**。目标：热态单张 < 15s（先给基线）。

## 6. 约束（红线）

1. 不改 UI 结构、不改数据库 schema、不改 `agent_config.json` 内容；确需改动，先在 issue 里写清理由。
2. 日志禁止落笔记正文；只打长度、耗时、布尔、ID。
3. 密钥不读、不写、不复述。
4. 只做 local commit，用户明确说 push 才 push。
5. 文件头注释与命名遵守 `docs/style/naming-conventions.md`；提交前 `node scripts/agent-gate/index.mjs --all < /dev/null` 必须 PASS。
6. 每条 issue 一个分支/worktree，完成后 `git merge --no-ff` 回主库再构建验证；worktree 只写代码。
7. 已记录的待修小项（不急）：`CaptureReceipt` 写入非原子（`TRUNC` 后直接 `writeSync`），计划改 `.tmp` + `fileIo.renameSync`。

## 7. 交付标准

每条 issue 完成时：

- 代码 + 单测（node 侧优先，hypium 视需要）+ 真机证据（日志行或截图）；
- `build-hsp-hap.mjs` rc=0、`agent-gate --all` PASS；
- commit message 用 `fix(<scope>): <一句话>`，body 里写「现象 / 根因 / 改法 / 验证」四段，末尾 `Refs: #<issue>`；
- 在 issue 下回评论贴证据并关单（关闭前确认用户没有新指令）。

## 8. 未决事项（不要擅自决定）

- 卡片上「掌握 0%」「连续复习 0 天」两行是否隐藏（v1 恒为 0，用户未拍板）。
- galaxy 两个背景图的删除是否保留（见 §2）。
- v2 `KnowledgeModel` 拆分（#209–#215）尚未开始，等这三条缺陷处理完再排。
- `feat/xiaoyi-latency-tuning` 分支与 `D:/HMgent/MindTrace-latency` worktree 的清理时机。

## 9. 命令速查

```bash
cd "D:/HMgent/MindTrace"
export DEVECO_SDK_HOME="C:/Program Files/Huawei/DevEco Studio/sdk"

node scripts/build-hsp-hap.mjs                                  # 构建五步
node scripts/agent-gate/index.mjs --all < /dev/null             # 门禁 + 768 单测
node scripts/e2e-capture/run.mjs --with-card --timeout 220      # 装机 + 抓取 + 检索 + 卡片
node scripts/e2e-capture/run.mjs --no-install --mode search     # 只跑检索
python scripts/a2a-smoke/a2a_smoke.py --text "<问题>" --no-restart --wait-seconds 45

git worktree add -b fix/233-latex-split D:/HMgent/MindTrace-233 HEAD
```

## 10. 完成情况（2026-10-27 下午）

三条缺陷均已实现、合并、真机验证（分支 `bugfix/galaxy-web-temporary`）：

| Issue | commit | 改法 | 证据 |
|---|---|---|---|
| #233 | `ca3db40`（合并 `b0b08b9`） | `DetailRenderModel.splitReadableLines` 改为围栏感知切分：`$$` 整块保留、块内不 `cleanListPrefix`、不参与步骤编号、未闭合兜底、行内 `$…$` 不切断 | 新增 `note-detail-latex-split.test.mjs` 8/8；真机详情页步骤区 1–8 连续、公式块整块渲染、无裸 `$$` |
| #235 | `ec1a06e`（合并 `cd350cf`） | `CaptureGraph.addNode` 统一计时 → `DispatchOptions.onNodeTiming` → `AiService` 汇总一条 `CAPTURE_TIMING`；`run.mjs` 打印逐图表格并分 cold/warm | 17 单测；真机 `seq=1` 冷启 21892ms、`seq=2` 热态 22807ms |
| #234 | `39ac90b`（合并 `8d72a3d`） | A2A 通道 `ReplyStyle='plain_text_math'`（`ReplyStyleRules.ets`），UI 默认 `'markdown'` 逐字不变；`TaskSnapshot` 增 `utf8ByteLength` / `unicodeCharCount`，`A2A_REPLY_SENT` 打计数 | 13 单测；真机同一问句 `ok:true`、56 字、`dollar=0`、`sqrt=1 ge=1`，气泡正常显示 |

补充：`66eeab7` 把 `scripts/a2a-smoke/tests` 与 `scripts/e2e-capture` 纳入 gate 的 `testFiles`，全量单测 776 → 806。

阶段耗时基线（真机，`CAPTURE_TIMING`，单位 ms）：

| seq | sample | resolve | ocr | classify | draft | truthCheck | persist | other | total |
|---|---|---|---|---|---|---|---|---|---|
| 1 | cold | 4 | 681 | 2599 | 17937 | 0 | 157 | 514 | 21892 |
| 2 | warm | 1 | 342 | 4993 | 17016 | 0 | 189 | 266 | 22807 |

遗留：
- #235 目标热态 < 15s **未达成**，瓶颈是 `structure`（draft）16–18s；`truth_check` 恒为 0ms、`visits=1`，需确认该节点是否真的执行。
- 三条 issue 尚未在 GitHub 回评论 / 关单（等用户确认后执行）。

