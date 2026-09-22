# 笔记生成链路修复 Session 交接文档（2026-09-20）

> **Session 范围**: 2026-09-19 ~ 2026-09-20 · P1「JSON 生命周期统一」+ 冒烟期 P0-1~P0-7 修复 + 失败根因终局取证
> **状态**: P0-7 已构建并部署到模拟器; 用户复测**仍失败** —— 两道 hard 闸门根因已实锤定位, 修复按用户指示冻结（"别修了, 告诉我原因"）
> **权威进度日志**: [docs/plans/knowledge-model-decomposition-plan.md](../plans/knowledge-model-decomposition-plan.md) §23.1-23.13（1733 行, UTF-8）。本文是索引与结论, 逐补丁细节以 §23 为准
> **用途**: 复盘 / 代码整合 / 对接

---

## 1. 一句话现状

「保存这条笔记」主链路在 09-19~09-20 连修 8 批（P1 主体 + P0-1~P0-7）后, **机械性契约违约已全部消除**（token 消耗 35k→2k 实证, schemaVersion/sourceIds/空壳全部由管线吸收）, 但 standard 路线仍被两道互相独立的 hard 闸门判死: ①模型不产出证据 → 空账本; ②truth 检查对换元积分 `du` 微元误报。两道均**未修复**, 修复方向已明确（见 §4.4）。

## 2. 时间线总览

| 时间 | 批次 | 问题一句话 | 状态 |
|---|---|---|---|
| 09-19 | P1 主体 (§23.1-23.5) | 六条生成路线无统一 JSON seam, 错误吞没 / 重试语义混乱 | 已部署 |
| 09-19 | P0-1 (§23.6) | LlmClient 成功分支误用 format() 截断 256 字符 → 非流式 JSON 必挂 parse error | 已部署 |
| 09-19 | P0-2 (§23.7) | thinking 挤占非流式 JSON 预算（reasoning 不回传纯烧 token） | 已部署 |
| 09-19 | P0-3 (§23.8) | standard 验证契约六处对 LLM 不可达成（偏移量数学/逐字包含/空 sourceIds…） | 已部署 |
| 09-19 | P0-4 (§23.9) | deep 路线 section 校验契约同类错位（校验 LLM 的 sourceIds 但管线根本不消费） | 已部署 |
| 09-20 | P0-5 (§23.10) | deep 失控烧钱循环（347 segment→347 节→765 万 prompt tokens/5 分钟, 死于 402） | 已部署 |
| 09-20 | P1-6 (§23.11) | 来源预算 20000 < 入口封顶 32000, 会话涨过 20k 后"保存笔记"永久失败 | 已部署 |
| 09-20 | P0-6 (§23.12) | standard 证据契约二轮修复（normalizeEvidenceItems 等）+ patchIntegralDx 窗口误报 | 已部署 |
| 09-20 | P0-7 (§23.13) | deep 证据装配结构性误报（start:0 写死/ambiguous 猜测/逐字保留）+ deep→standard 预算降级 | 已部署 |
| 09-20 | 根因终局 | 用户复测仍失败; dbpull6 取证定位两道残余 hard 闸门（§4） | **未修复（冻结）** |

## 3. 已完成工作（按补丁索引）

细节全部在计划文档 §23 对应小节, 此处只留识别信息。

- **P1 主体（§23.1-23.5）**: 新建 `GenerationJsonCaller`（统一 `callJson` seam, 守门重试镜像 LlmGuard, 传输/截断/候选未命中不重试, `GenerationJsonError` 六类错误码）; PersistNode insert 失败显式抛 `CaptureGraphError`; StructureNode retriable 映射; TruthCheckNode 输入简化为 `captureText + '\n' + content`; KnowledgeModel 六路线接入 seam。测试 +30（agents 26 + common 4）。
- **P0-1（§23.6）**: `LlmErrorBodyFormatter` 新增 `decodeFull()`; LlmClient 成功分支改用它（错误分支保留 format 截断脱敏）。
- **P0-2（§23.7）**: 非流式 `callJsonInternal` 默认 `enableThinking: false`; `lightBudget.maxTokens` 1200→3000。
- **P0-3（§23.8）**: 管线代算哲学首秀 —— `relocateEvidenceRefs`（excerpt 真实存在时管线重算偏移）、非公式 `EVIDENCE_NOT_PRESERVED` 降 soft、sourceIds 回填、`normalizeDraftCategory` 学科→5 类映射、`normalizeSectionContent` 采用 MM-MD normalizedText、prompt 显式契约行。
- **P0-4（§23.9）**: 同哲学移植 deep 路径 —— `normalizeDeepSectionDraft`（sourceIds/schemaVersion/subject/id/label/category/content 全部管线回填）; callDeepSectionDraft prompt 显式契约。
- **P0-5（§23.10）**: `MAX_DEEP_OUTLINE_SECTIONS=8` + `capDeepOutlineSections`（尾部合并）; `updateDeepLedger` 收紧（仅本节结论/去重/value 截断 160 字符）。调用数上界 = 8 节 × ≤3 守门重试。
- **P1-6（§23.11）**: `deepBudget().maxSourceChars` 20000→36000（> 入口 `NOTE_CONTEXT_LIMIT=32000` + 4k OCR 余量）; 测试同步 `repeat(3000)`→`repeat(5000)`。
- **P0-6（§23.12）**: `normalizeEvidenceItems`（丢空壳/回填 id/去重撞号/非法 sourceId 回退/空 excerpt 锚点）; `validateStandardArtifacts` 空 excerpt 跳过定位检查; `normalizeStandardResult` 重排归一化; `patchIntegralDx` 搜索窗口改为"指数后到最近 `$`/`\]`/`\int`/换行"。
- **P0-7（§23.13）**: `NoteGenerationEvidenceItem.origin?: 'pipeline' | 'model'`; pipeline 证据跳过"草稿逐字保留"检查（DRAFT_SOURCE_MAPPING_MISSING 与定位检查保留）; `buildDeepEvidence` 偏移由 `fragment.indexOf` 重算 + verification 恒 'supported' + origin='pipeline'; Dispatcher `dispatchGeneration` 深源 >36000 自动降级 standard（run 落库前 log 留痕）。

## 4. 最终失败根因（2026-09-20 定位, 未修复）

复测 run `conversation-1789895381981`（17:49, standard 路线, 每轮仅 1017/1046 tokens）:
指纹 `EVIDENCE_REQUIRED:evidence::|TRUTH_CHECK_ERROR:truth_check::` 连续两轮相同 → `repeated_issue_fingerprint` → needs-input → 用户看到「生成笔记失败: standard generation requires additional input」。

**P0-6/P0-7 生效实证**（同 run）: schemaVersion='mindtrace.note-draft.v1' 正确、sourceIds 带 `conversation:` 前缀、SCHEMA_VERSION/SOURCE_REFERENCE_INVALID/空壳类 issue 全部消失、token 消耗 35k→2k。失败原因是**另外两道门**。

### 4.1 根因① EVIDENCE_REQUIRED —— 空证据账本（hard）

- checkpoint `evidence_json = []`: deepseek-v4-flash 在 standard 路线**系统性返回空/全空壳 evidence**; P0-6 的 `normalizeEvidenceItems` 把空壳全部丢弃后账本为空。
- `validateStandardArtifacts`（common/src/main/ets/models/NoteGenerationModels.ets:1316-1318）: `evidence.length === 0 && outline.sections.length > 0` → EVIDENCE_REQUIRED (hard)。
- 修复轮（callEvidenceRepair）再问一次, 模型还是不给 → 指纹重复判死。
- 本质: P0-6 把"给了垃圾"变成"没给", 但"账本非空"门槛还在 —— **契约仍要求模型做它从来做不到的事**（自己编写带引文的证据清单）。

### 4.2 根因② TRUTH_CHECK_ERROR —— 换元积分 `du` 微元误报（hard）

- truth 检查输入 = `captureText + '\n' + 草稿内容`（TruthCheckNode 简化后的契约, §23.2）—— **会话原文也在检查范围内**。
- 会话历史里有一条早前 assistant 回复含换元公式: `\int_{-\infty}^{\infty} f(x)\,dx=\int_{-\infty}^{\infty}\varphi(u)\,du=1`。第二个积分微元是 `du`（换元法, 数学上完全正确）。
- P0-6 修复版 `patchIntegralDx`（agents/src/main/ets/agents/TruthCheckService.ets:244）窗口内只认 `dx` —— 窗口 `\varphi(u)\,du=1` 含 `du` 无 `dx` → 误判"缺 dx" → 注入错误内容 + 记 issue → truthFlag=false → TRUTH_CHECK_ERROR（Dispatcher.ets evaluateStandardCandidate ~L955）。
- Python 完整复现命中（@1433）。**触发点在源文本上, 修复轮改草稿救不了**。
- 这是 P0-6 修的"dx 离指数太远"窗口问题的孪生兄弟: 同类假阳性, 换了个马甲（微元不叫 dx）。

### 4.3 会话污染（放大器, 非直接根因）

该会话被反复重试污染: 同一份正态分布材料贴了 8+ 次, 历次报错（"生成笔记失败"、402 余额不足、SOURCE_BUDGET_EXCEEDED）全部混进"源材料"。即使过了两道闸门, 笔记也是从噪音里生成的。**复测必须换全新会话、只贴一次材料**（根因②的触发文本就在历史里, 旧会话不删必然复现）。

### 4.4 若要修（方向已定, 未实施, 等用户发话）

1. **空账本管线代造**: standard 路线 LLM 证据为空时, 由管线生成 origin='pipeline' 溯源证据（镜像 deep 路线 P0-7 已有机制; standard 已有 relocate/normalize 基建可复用）。
2. **patchIntegralDx 接受任意微元**: 窗口内出现 `\,d[字母]`（dx/du/dt/dy…）即视为已有微元, 不注入不报 issue。
3. 修完后按 §9 复测规范验证: 新会话 standard 应 ≤2 轮成功。

## 5. 修改文件清单（git 全部未提交）

git 状态: 分支 `develop`, 基线 `4b40e9a`（Merge PR #138 multi-device-research）。**本 session 未做任何 commit/push**, 全部改动在工作区。另: `.git` 目录归属另一账户（dubious ownership）, git 命令需 `-c safe.directory=<仓库路径>` 豁免（见 §8）。

### 修改（14 个源码/测试 + 5 个 lock）

| 文件 | 涉及批次 |
|---|---|
| agents/src/main/ets/agents/KnowledgeModel.ets | P1, P0-3, P0-4, P0-5, P0-6, P0-7 |
| agents/src/main/ets/agents/TruthCheckService.ets | P0-6 |
| agents/src/main/ets/core/Dispatcher.ets | P0-7（deep→standard 降级 ~L339）等 |
| agents/src/main/ets/graph/nodes/PersistNode.ets | P1 |
| agents/src/main/ets/graph/nodes/StructureNode.ets | P1 |
| agents/src/main/ets/graph/nodes/TruthCheckNode.ets | P1 |
| agents/src/test/List.test.ets | P1（注册 4 套件） |
| common/src/main/ets/Index.ets | P1（TRUNCATION_MARKER）, P0-6（normalize* 导出） |
| common/src/main/ets/llm/LlmClient.ets | P0-1, P0-2 |
| common/src/main/ets/llm/LlmErrorBodyFormatter.ets | P0-1（decodeFull） |
| common/src/main/ets/models/NoteGenerationModels.ets | P1（tags）, P0-3, P0-4, P0-5, P1-6, P0-6, P0-7 |
| common/src/test/List.test.ets | P1, P0-1（注册套件） |
| common/src/test/LlmErrorBodyFormatter.test.ets | P0-1（重写, 7 用例） |
| entry/src/test/DispatcherNoteGeneration.test.ets | P1-6（budget 用例 repeat(5000)）等 |
| {根, agents, cardservice, entry, skill}/oh-package-lock.json5 | 构建副产物, 提交前 review 是否有意 |

### 新建（未跟踪）

| 文件 | 内容 |
|---|---|
| agents/src/main/ets/agents/GenerationJsonCaller.ets | 统一 callJson seam（P1） |
| agents/src/test/GenerationJsonCaller.test.ets | 13 用例 |
| agents/src/test/PersistNode.test.ets | 5 用例 |
| agents/src/test/StructureNode.test.ets | 5 用例 |
| agents/src/test/TruthCheckNode.test.ets | 3+2 用例（含 P0-6 integral_dx_patch） |
| common/src/test/NoteGenerationModels.test.ets | 16 用例（tags 4 / deep 4 / 封顶 2 / standard 归一化 3 / pipeline origin 3） |
| docs/plans/（整目录未跟踪） | 本计划文档 1733 行 + 上一 session 交接 mindtrace-agent-research-handoff-2026-09-18.md |
| docs/agents/note-generation-fix-handoff-2026-09-20.md | 本文 |

### 验证状态

- 已通过: arkts_check（改动文件逐个）/ `node scripts/arkts-lint/index.mjs --quiet` / BUILD SUCCESSFUL（P0-7 轮 1m22s, 低内存参数）/ 模拟器安装启动成功。
- **未跑**: 全量 Hypium 56 用例只能用户在 DevEco GUI 执行（CLI 不可用）; 冒烟复测因两道闸门未修, 当前必然失败, 不具备复测意义。

## 6. 未完成 / 待办

1. **两道 hard 闸门修复**（§4.4 方向）—— 用户冻结中, 等发话。
2. **Hypium 56 用例** GUI 执行（改动涉及 4 个 module 的测试套件）。
3. **deep 路线复测**: P0-5+P1-6+P0-7 组合从未在干净环境验证 —— 需大会话（>12k 字符）或长内容触发, 预期 round 0 即 clean; >36k 源应自动降级 standard（log 留痕）。
4. **OCR 服务**: torch 损坏（c10.dll WinError 1114）, 修复需用户同意 `pip install --force-reinstall torch --index-url https://download.pytorch.org/whl/cpu`（改全局环境, 不经同意不动）。
5. **git 提交**: 全部工作未提交（§5）; 按团队规范应 commit 到 `feature/*` 分支 PR 合入 `develop`, 不进 main。建议按批次拆 commit（P1 主体 / P0-1~4 / P0-5+P1-6 / P0-6 / P0-7）, 由用户 review。
6. **计划文档 §23.5 后续批次**: TruthCheckInput 结构化、规则分级（hard/warning）、CaptureGraphError 稳定错误码、SSE 流末 envelope 归一化、§20 文件拆分。

## 7. 未处理问题与遗留观察（记录在案, 均未修）

- TRUTH_CHECK_ERROR 不携带 truthCheck.message 细节, 用户只见 'candidate truth check failed' —— 可观测性缺口。
- chat_message 错误文案 `substring(0,120)` 截断 402 等详情。
- note_reply 节点长循环期间 6 分钟无 UI 反馈（UX 债）。
- pending OCR 材料双重计入预算（buildContextText 内嵌段 + ConversationWorkflow 独立片段）—— 需产品裁决。
- SOURCE_BUDGET_EXCEEDED 不置 processBlocked → needs-input 展示为"问用户", UX 反而合理, 暂不动。
- LLM section id 重复 quirk: 复测 run 草稿 5 节全部复用首个 outline id（'section-item-71568ccf' ×5）—— 恰好合法未触发校验, 但草稿↔大纲映射质量隐患, 属模型行为画像。
- 对话流 single fragment >12000 触发 deep 是否合理 —— 产品决策。
- deep token_cost 可超 maxTokens 的统计口径问题。
- 会话历史垃圾收敛依赖摘要机制, 覆盖度待验。
- 预存在不修: arkts-lint 引擎自身测试 109/110、knowledge-graph-rdb.test.mjs ENOENT（均非本 session 引入）。

## 8. 注意事项（坑速查）

**构建**（hvigor CLI 与 DevEco GUI 均合法入口; 低内存参数必需）:

```powershell
$env:DEVECO_SDK_HOME="<DevEco 安装目录>\sdk"
$env:JAVA_HOME="<DevEco 安装目录>\jbr"
$env:PATH="<DevEco 安装目录>\jbr\bin;$env:PATH"
node "<DevEco 安装目录>\tools\hvigor\bin\hvigorw.js" --mode module -p product=default -p buildMode=debug assembleHap --no-daemon --no-parallel --optimization-strategy memory --max-old-space-size 6144
```

产物: `entry/build/default/outputs/default/entry-default-unsigned.hap`。

**部署三连**: `hdc shell aa force-stop com.example.mathmind` → `hdc app install -r <hap>` → `hdc shell aa start -a EntryAbility -b com.example.mathmind`。

**环境坑**:
- 模拟器本机 CLI 启动失败（WHPX/驱动, 进程空转 0.6 CPU 秒）—— 必须从 DevEco Device Manager GUI 启动; 当前实例 PID 10892, hdc target `127.0.0.1:5555`。
- `.git` 归属另一账户: git 命令加 `-c safe.directory=<仓库绝对路径>`, 或 `git config --global --add safe.directory <路径>`（后者改全局配置, 由用户决定）。
- npm `--prefix` 不生效 → 用 workdir 进 `scripts/arkts-lint` 再 `npm test`。
- rg 不可用 → 用 grep 工具; Python stdout 中文乱码 → 输出写临时 UTF-8 文件再读。
- 两个 deveco 常驻进程是 CLI 基础设施, 不可杀。
- 402 Insufficient Balance → LLM_TRANSPORT, retriable=false（历史事故: P0-5 修复前一次失控烧穿余额）。
- LlmClient 非流式截断 gotcha 见 AGENTS.md（`finish_reason==='length'` 分支; 对话回复预算 CHAT_REPLY_MAX_TOKENS=12000）。

**计划文档编码事故（重要教训）**: 该文档实为 UTF-8（无 BOM）。09-20 白天多次追加误用 GBK 编码流程（基于会话早期误判）, 造成头部 UTF-8 + 尾部 GBK 混合编码。已按字节分段识别（utf-8 头 66413 字节 + gbk 尾）无损转码统一回 UTF-8: 1733 行不变、回读一致、替换符 0。转码前原件备份 `%TEMP%\deveco\plan-doc-backup-2026-09-20.md`。**今后该文档直接 UTF-8 追加, 勿再用 GBK 流程**。

**DB 取证流程**（复现问题定位时用）: 设备路径 `/data/app/el2/100/database/com.example.mathmind/entry/rdb/`, **db+wal+shm 三文件必须一起拉**（cp 到 /data/local/tmp → `hdc file recv`）; 关键表 `note_generation_run`（route/status/stop_reason/issue_count/source_summary）、`note_generation_log`、`note_generation_checkpoint`（issue_codes/document_json/outline_json/evidence_json/verification_json/issue_fingerprint/token_cost/iteration）。历史取证副本在 `%TEMP%\deveco\dbpull{3,4,5,6}\`（dbpull5=deep 20-issue run, dbpull6=17:49 复测 run, 含 analysis*.txt 与 Python 复现脚本）。

**速查数字**: 路线判定 `>12000 字符 || fragments≥3 || ocr≥2 || 证明/推导关键词 → deep`; standardBudget maxTokens=6000; deepBudget {maxTokens 14000, nodeRuns 20, repair 4, sourceChars 36000}; `NOTE_CONTEXT_LIMIT=32000`（入口封顶）; `MAX_DEEP_OUTLINE_SECTIONS=8`; `DEEP_LEDGER_VALUE_MAX_CHARS=160`; best-clean 检查在预算检查之前（round 0 干净即成功）。

**关键代码锚点**: EVIDENCE_REQUIRED = NoteGenerationModels.ets:1316-1318; evaluateStandardCandidate = Dispatcher.ets:925（TRUTH_CHECK_ERROR ~955）; deep 降级 = Dispatcher.ets:~339, preflight 防御 ~374-388; truth 启发式 = TruthCheckService.ets:140-234（patchIntegralDx:244）; buildDeepEvidence = KnowledgeModel.ets:643（structureDeepDraft:290 / repairDeepDraft:436 / normalizeStandardResult:930 / relocateEvidenceRefs:1039）; selectGenerationRoute = NoteGenerationModels.ets:835, budgets 875-888, normalizeEvidenceItems:1185; generateNoteFromConversation = ConversationWorkflow.ets:396-468（错误文案:465）。

## 9. 复测规范与对接建议

**复测规范**（修完两道闸门后）:
1. **全新会话**, 材料只贴一次, 再发「保存这条笔记」。旧会话（反复重试过的）必然复现根因②, 不可用于复测。
2. standard 路线（小会话）预期 ≤2 轮成功; deep 路线需 >12k 字符或 ≥3 fragments 触发, 预期 round 0 clean; >36k 源预期自动降级 standard。
3. 失败时先拉 DB 三件套看 checkpoint 的 issue_codes + issue_fingerprint, 再对照本文 §4。

**对接建议**（代码整合顺序）:
1. 先跑静态门禁: `scripts/arkts-lint` 下 `npm test`（70 单元测试）+ `node scripts/arkts-lint/index.mjs --quiet`。
2. 用户 GUI 跑全量 Hypium 56 用例。
3. 按 §5 清单分批 commit（建议批次见 §6 第 5 条）, PR 合入 `develop`; `oh-package-lock.json5` ×5 与 `docs/plans/` 整目录提交前 review。
4. 实施两道闸门修复（§4.4）时, 建议各配 Hypium 用例（空账本代造 / du 微元通过）, 并保持"管线代算 LLM 做不到的事, 不放松真值类校验"的既有哲学。
5. 关联阅读: [AGENTS.md](../../AGENTS.md)（红线与命令）、[CONTEXT.md](../../CONTEXT.md)（词汇消歧）、[docs/specs/018-agent-workflow-architecture.md](../specs/018-agent-workflow-architecture.md)（workflow 架构权威态）、计划文档 §13（truth check 后续设计）、本机 AI 会话计划 `~/.local/share/deveco/plans/1789791628820-hidden-pixel.md`。
