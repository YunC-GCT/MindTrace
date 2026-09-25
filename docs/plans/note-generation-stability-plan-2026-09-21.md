# Note Generation Stability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use task-by-task execution with a failing test before each code change. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make AI conversation note generation stable for light, standard, and deep routes by moving unreliable structural fields from model-only output to deterministic pipeline fallbacks.

**Architecture:** Keep the public generation flow unchanged: `ConversationWorkflow -> AiService -> Dispatcher -> KnowledgeModel`. Add small normalization helpers in `common/src/main/ets/models/NoteGenerationModels.ets` so generation routes call one deep module for draft and evidence repair instead of duplicating fallback logic across UI and dispatcher layers.

**Tech Stack:** HarmonyOS ArkTS 1.1, Hypium tests, MindTrace 5-module HAP/HSP structure, existing hvigor/DevEco validation.

**Spec:** Current bug reports from DevEco Studio emulator testing: `SECTION_EMPTY`, `standard generation requires additional input`, `deep generation requires additional input`, and route pollution from conversation history.

## Global Constraints

- Do not commit or push without explicit user permission.
- Keep changes surgical; do not redesign the whole note-generation workflow.
- Follow ArkTS 1.1 strict rules in `docs/style/arkts-1.1.md`.
- Repository documentation links must remain relative paths.
- Each implementation task must have an independently runnable test or a clear manual verification step.

---

## File Structure

- `common/src/main/ets/models/NoteGenerationModels.ets`: owns typed note-generation contracts and deterministic normalization helpers.
- `common/src/main/ets/Index.ets`: exports new helpers for tests and agents module consumers.
- `agents/src/main/ets/agents/KnowledgeModel.ets`: calls normalization helpers after model JSON parsing.
- `agents/src/main/ets/agents/TruthCheckService.ets`: fixes integral differential detection.
- `entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets`: prefers inline material for explicit save requests to reduce context pollution.
- `common/src/test/NoteGenerationModels.test.ets`: regression tests for light fallback and pipeline evidence.
- `agents/src/test/TruthCheckNode.test.ets`: regression test for `du` integral differential.

## Task 1: Light Draft Fallback

**Files:**
- Modify: `common/src/main/ets/models/NoteGenerationModels.ets`
- Modify: `common/src/main/ets/Index.ets`
- Modify: `agents/src/main/ets/agents/KnowledgeModel.ets`
- Test: `common/src/test/NoteGenerationModels.test.ets`

**Interfaces:**
- Produces: `normalizeLightDraft(document: NoteDraftDocument, bundle: SourceBundle): NoteDraftDocument`
- Consumes: `NOTE_DRAFT_SCHEMA_VERSION`, `normalizeDraftCategory`, `SourceBundle`

- [ ] Write a test where a light draft section has empty `id`, `content`, and `sourceIds`.
- [ ] Verify the test fails before implementation.
- [ ] Implement `normalizeLightDraft` so it fills schema, category, section id, label, source ids, and empty content from source text.
- [ ] Call `normalizeLightDraft` inside `KnowledgeModel.structureLightDraft`.
- [ ] Run common note-generation model tests.

## Task 2: Standard Pipeline Evidence Fallback

**Files:**
- Modify: `common/src/main/ets/models/NoteGenerationModels.ets`
- Modify: `common/src/main/ets/Index.ets`
- Modify: `agents/src/main/ets/agents/KnowledgeModel.ets`
- Test: `common/src/test/NoteGenerationModels.test.ets`

**Interfaces:**
- Produces: `buildPipelineEvidence(outline: NoteGenerationOutline, bundle: SourceBundle): NoteGenerationEvidenceItem[]`
- Consumes: normalized outline section source ids.

- [ ] Write a test where an outline has one section and evidence is empty.
- [ ] Verify pipeline evidence contains `origin='pipeline'`, a valid source id, and an excerpt from the source.
- [ ] Implement `buildPipelineEvidence`.
- [ ] In `normalizeStandardResult`, if normalized evidence is empty, replace it with pipeline evidence.
- [ ] Run common note-generation model tests.

## Task 3: Truth Check Differential Detection

**Files:**
- Modify: `agents/src/main/ets/agents/TruthCheckService.ets`
- Test: `agents/src/test/TruthCheckNode.test.ets`

**Interfaces:**
- Keeps existing `TruthCheckService.truthCheck(input: string): MvpTruthCheckResult`.

- [ ] Add a test for `\int ... \varphi(u)\,du=1`.
- [ ] Verify it fails before implementation.
- [ ] Replace `dx`-only detection with a local helper that accepts `dx`, `du`, `dt`, `dy`, and other ASCII-letter differentials.
- [ ] Run truth check tests.

## Task 4: Conversation Inline Material Preference

**Files:**
- Modify: `entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets`
- Test: focused manual emulator verification.

**Interfaces:**
- Private helper: `preferInlineNoteMaterial(userInstruction: string): string`

- [ ] Add a conservative helper in `ConversationWorkflow`: when the current message contains material after `:` / `：` / newline and that material is at least 8 characters, use it before historical memory.
- [ ] Keep existing memory fallback for messages like `保存这条笔记`.
- [ ] Manually verify that a one-message light test does not include AI assistant history.

## Task 5: Verification

- [ ] Run `node scripts/arkts-lint/index.mjs --quiet`.
- [ ] Run available Hypium/unit tests for changed modules when the local environment supports them.
- [ ] If DevEco emulator is available, verify:
  - light: short concept material produces draft preview.
  - standard: one-formula material produces draft preview or a specific non-evidence error.
  - deep: short proof material no longer fails due to standard evidence or `du` truth check regression.

## Self-Review

- Spec coverage: covers all reported symptoms and keeps OCR untouched.
- Placeholder scan: no task depends on unspecified files or unnamed helpers.
- Type consistency: helper names and signatures are repeated exactly where consumed.

---

# 2026-09-23 Progress Addendum: Deep Route Stability

> 本补充记录当前真实开发状态，并对原计划中已经过时的结论进行校正。原计划保留作为历史记录；后续涉及 deep 路线的执行，以本节为准。

## 1. 当前状态（大白话）

当前系统有两条主要生成路线：

- **standard 路线**：一次生成整篇笔记，再统一检查。
- **deep 路线**：先把长材料切成多个小节，每个小节单独生成，再合并、生成证据、做 TruthCheck，发现问题后再局部重写。

截至 2026-09-23：

- standard 路线已经在虚拟机中跑通。
- standard 生成出的笔记编辑页可以打开。
- standard 生成的笔记可以保存。
- 摘要已经限制在 60 字以内。
- 摘要中的短行内公式可以显示。
- 难度值已经归一到 1–4。
- `section-item-*` 这类内部 ID 不再直接作为用户看到的小节标题。
- standard verifier 的返回结果已经增加完整性校验；缺少 evidence decision、字段名错误或没有覆盖全部 evidence 时会重试。
- deep 路线仍未在真实虚拟机链路中确认跑通。
- 当前工作区包含本轮 deep 稳定性修复的未提交代码和测试改动；未进行 commit 或 push。

原计划中“standard 空 evidence、`du` 微元误判、摘要和保存问题未修复”的描述属于 2026-09-20 的历史状态，不能再当作当前状态。相关历史原因保留在 [`docs/agents/note-generation-fix-handoff-2026-09-20.md`](../agents/note-generation-fix-handoff-2026-09-20.md)。

## 2. Deep 路线实际流程

deep 路线的真实调用链如下：

```text
Dispatcher.dispatch
  -> dispatchDeepGeneration
  -> KnowledgeModel.structureDeepDraft
  -> buildDeepOutline
  -> callDeepSectionDraft（每个小节单独调用 LLM）
  -> normalizeDeepSectionDraft
  -> buildDeepEvidence
  -> NoteGenerationEvidenceVerifier.verify
  -> Dispatcher.evaluateDeepCandidate
  -> TruthCheck
  -> repairDeepDraft（失败时局部重写）
  -> 保存 checkpoint / 完成 / 返回失败
```

通俗理解：

1. 先把用户材料切成若干段。
2. 每一段变成一个 outline section。
3. 每个 section 单独让 LLM 生成。
4. 管线把所有 section 合成一份 draft。
5. 管线为每个 section 建 evidence，记录它来自哪个原始材料。
6. verifier 检查结构、来源、公式和覆盖情况。
7. Dispatcher 再做 TruthCheck 和 deep 专属检查。
8. 如果有 hard issue，就调用 `repairDeepDraft` 重写出问题的 section。
9. 如果连续两轮得到完全相同的 issue fingerprint，就停止，避免无限重试。

因此，`repeated_issue_fingerprint` 的含义不是 Git 冲突，而是：

> 系统连续两轮发现的是同一批问题，说明当前修复没有真正改变结果，于是主动停止。

## 3. 已经处理的 deep 问题

以下问题已经有代码修复，不应再次重复设计：

### 3.1 LLM section 输出契约过严

过去 deep section 的校验直接检查 LLM 原始 JSON，导致模型经常因为以下原因连续重试：

- 忘记返回 `sourceIds`；
- 返回学科名称而不是五种允许的类型；
- 使用 `\(...\)` 或 `\[...\]`，而不是项目统一的 MM-MD 公式格式；
- 缺少 schemaVersion 或 section 元数据。

现在由 `normalizeDeepSectionDraft` 在校验前补齐和归一化：

- `schemaVersion`；
- `sourceIds`；
- `subject`；
- section `id` 和 `label`；
- category；
- MM-MD-v1 内容格式。

涉及文件：

- `common/src/main/ets/models/NoteGenerationModels.ets`
- `agents/src/main/ets/agents/KnowledgeModel.ets`

### 3.2 deep section 数量失控

过去一个长会话可能被切成数百个 section，导致串行 LLM 调用次数过多、prompt 不断变长，最终超时或触发费用/余额限制。

当前已经有以下限制：

- deep outline 最多 8 个 section；
- 超出的尾部材料合并到最后一个 section；
- ledger 中的单条内容最多 160 字符；
- ledger 只保留当前 section 相关的结论，并做去重；
- deep source budget 已提高到 36000 字符；
- 超过 deep source budget 时由 Dispatcher 记录降级并转走 standard 路线。

涉及文件：

- `common/src/main/ets/models/NoteGenerationModels.ets`
- `agents/src/main/ets/agents/KnowledgeModel.ets`
- `agents/src/main/ets/core/Dispatcher.ets`

### 3.3 deep evidence 被错误判为不可追溯

过去 `buildDeepEvidence` 把 section 段落的偏移固定写成 0，并根据草稿是否逐字包含原文判断 evidence 是否可信。这对“原文改写成学习笔记”的 deep 路线不成立，容易产生假阳性。

现在：

- evidence 的 start/end 会在真实 source fragment 中重新定位；
- 找不到精确片段时使用空 excerpt 锚点；
- 管线结构生成的 evidence 标记 `origin='pipeline'`；
- pipeline evidence 不再要求草稿逐字复制原文；
- source mapping 仍然保留校验。

涉及文件：

- `agents/src/main/ets/agents/KnowledgeModel.ets`
- `common/src/main/ets/models/NoteGenerationModels.ets`

## 4. 目前仍需处理或确认的问题

下面分成“代码上已经看见的风险”和“必须通过测试/虚拟机日志确认的事实”，不能混为一谈。

### P0：真实 KnowledgeModel deep 回归测试（已补充，待设备执行）

**现状：**

此前已有 deep 测试主要注入一个假的 `KnowledgeModel`，验证 Dispatcher 如何处理 deep 结果。当前已经在 `KnowledgeModelNoteGeneration.test.ets` 中补充直接调用 `KnowledgeModel.structureDeepDraft()` 的脚本化多 section 测试；但本机尚未在 DevEco 设备上执行 Hypium，因此仍需做设备侧确认。

缺少的测试是：

```text
脚本化 LlmCaller
  -> KnowledgeModel.structureDeepDraft
  -> 多个 deep section JSON
  -> normalizeDeepSectionDraft
  -> buildDeepEvidence
  -> verifier
```

**为什么这是问题：**

现在只能证明“Dispatcher 拿到一个已经准备好的 deep 结果后能工作”，不能证明 `KnowledgeModel` 自己从多轮 LLM 返回开始到 deep 结果结束的完整链路没问题。虚拟机中 deep 失败时，无法快速判断是：

- section LLM 返回为空；
- section JSON 校验失败；
- sourceIds 归一化失败；
- evidence 组装失败；
- verifier 产生 hard issue；
- repair 选错 section；
- TruthCheck 或 Dispatcher 的 deep merge 检查失败。

**解决方案：**

已在 `agents/src/test/KnowledgeModelNoteGeneration.test.ets` 增加真实 `structureDeepDraft` 测试，不放宽 verifier，不跳过 TruthCheck。测试断言用户真正关心的结果：

- 生成多个 section；
- section 都有 outline 指定的 `sourceIds`；
- evidence 都带 `origin='pipeline'`；
- summary 不超过 60 字；
- 公式内容保持 MM-MD 格式；
- 首轮生成的 verification 没有 hard issue。

当前测试替身已经覆盖两个可区分的 source/section，并故意省略 LLM 返回的 `sourceIds`、使用可归一化的 `\(...\)` 公式定界符，以验证管线归一化行为。

### P0：repairDeepDraft 没有 sectionId 时默认只修第一个 section（已修复，待设备执行）

当前逻辑是：

```text
有 issue.sectionId -> 修指定 section
没有任何 sectionId -> 修 outline.sections[0]
```

这会造成一个危险情况：

```text
真正出错：第 3 个 section
issue：只有全局 code，没有 sectionId
系统动作：反复重写第 1 个 section
结果：第 3 个 section 不变
最终：重复 issue fingerprint -> 停止
```

**目前结论：**

这是代码中已经存在的风险，但是否就是当前虚拟机 deep 失败的直接原因，需要通过失败 checkpoint 的 `issue_codes`、`sectionId` 和 `sourceId` 确认。

**解决方案：**

修复目标 section 的解析顺序：

1. issue 有 `sectionId`：直接定位该 section。
2. issue 没有 `sectionId` 但有 `sourceId`：找到引用该 source 的 outline section。
3. issue 是 `DEEP_MUST_INCLUDE_MISSING`：找到声明该 mustInclude 的 section。
4. issue 是明确的全局结构问题：按问题类型决定重建所有受影响 section，而不是默认只改第一个。
5. 仍然无法定位时，保留硬失败并输出可读的诊断信息，不要静默伪造“已修复”。

### P1：deep 的总 metadata 只取第一个 section

`structureDeepDraft` 当前只从第一个 section draft 读取：

- title；
- summary；
- subject；
- category；
- chapter；
- difficulty；
- tags。

这不一定导致 deep 失败，但会产生质量问题：第一个 section 可能只是背景材料，整篇笔记的标题、摘要和难度却完全由它决定。

**解决方案：**

先不把它当作 P0 失败根因。deep 主链跑通后，再通过测试确认：

- 第一个 section metadata 完整时，保持当前行为；
- 第一个 section metadata 缺失时，从后续 section 补齐；
- summary 仍统一经过 60 字限制；
- difficulty 最终仍只能是 1–4；
- 不为了聚合 metadata 增加额外 LLM 调用。

最小实现应优先使用已有 section draft 的非空字段，不新增复杂的 metadata 合成器。

### P1：ledger 对公式的识别条件不完整（已修复，待设备执行）

`updateDeepLedger` 当前主要通过内容中是否存在 `=` 或 `\(` 判断是否记录公式。当前项目公式规范已经统一为 `$...$` 和 `$$...$$`，因此以下公式可能被漏掉：

```text
$\pi$
$$\sqrt{x}$$
$$\sum_{i=1}^{n} a_i$$
```

**影响：**

后续 section 可能拿不到前面 section 的公式上下文，导致公式重复、符号漂移或解释不一致。这个问题更像质量风险，暂时不能直接说它就是当前 deep 失败原因。

**解决方案：**

使用已有 `ContentProtocol.hasFormulaSyntax` 或同一套 MM-MD 判断逻辑识别公式，不再只检查 `=`。新增测试覆盖：

- 有等号的公式；
- 没有等号的行内公式；
- display math；
- 普通文本不进入公式 ledger。

## 5. 按 TDD 执行的后续计划

### Task 6: 建立 deep KnowledgeModel 红灯测试

**Files:**

- Modify: `agents/src/test/KnowledgeModelNoteGeneration.test.ets`
- Modify: `agents/src/test/List.test.ets`（只有测试文件尚未注册时才修改）

**测试替身：**

新增一个显式的 `DeepGenerationCaller implements LlmCaller`，按调用次数返回两个 section 的合法 JSON。测试材料至少包含：

- 一个标题；
- 一个证明或推导段；
- 一个公式段；
- 两个可区分的 source/segment。

LLM 返回内容故意省略 `sourceIds`，并使用可归一化的公式定界符，验证管线归一化而不是要求模型完美配合。

- [ ] 添加 `runs_real_deep_structure_with_multiple_sections` 测试。
- [ ] 断言测试直接调用 `new KnowledgeModel(caller).structureDeepDraft(request)`。
- [ ] 断言 section 数量、section id、sourceIds、pipeline evidence、summary 长度和公式格式。
- [ ] 运行该测试，记录失败位置和实际 issue；如果测试在当前代码下直接通过，说明它建立的是基线测试，而不是失败复现测试，必须继续覆盖 repair 场景。

验证命令：

```powershell
devecocli build --modules agents@ohosTest
```

预期：新增测试能够编译；若 Hypium CLI 无法直接运行，则在 DevEco Studio 的 `agents@ohosTest` 中执行，并记录测试名称和结果。

### Task 7: 建立 deep repair 定位红灯测试

**Files:**

- Modify: `agents/src/test/KnowledgeModelNoteGeneration.test.ets`

**测试内容：**

构造两个 section 的 `NoteGenerationDeepResult`：

- section A 对应 source A；
- section B 对应 source B；
- 传入一个没有 `sectionId`、但带 `sourceId=source B` 的 repairable issue。

测试必须证明修复调用针对 section B，而不是 section A。`DeepGenerationCaller` 应记录每次请求中出现的 section id，断言最后一次 repair 请求目标是 section B。

- [ ] 先写 `repairs_the_section_selected_by_issue_source_id`。
- [ ] 运行测试，确认当前实现会默认修第一个 section，或至少确认该场景没有被当前代码覆盖。
- [ ] 将测试结果写入本计划的执行记录。

### Task 8: 最小修改 repairDeepDraft

**Files:**

- Modify: `agents/src/main/ets/agents/KnowledgeModel.ets`
- Test: `agents/src/test/KnowledgeModelNoteGeneration.test.ets`

**实现边界：**

只增加一个局部的目标解析逻辑，优先复用当前已有的 `outline.sections`、`sourceIds` 和 issue 字段。不要修改 verifier 的 hard gate，不要删除 TruthCheck，不要把所有 section 无条件重写。

- [ ] 实现 `sectionId -> sourceId -> mustInclude -> 明确全局问题` 的目标解析顺序。
- [ ] 对无法定位的 issue 保留失败，不默认把第一个 section 当作万能修复目标。
- [ ] 运行 Task 7 的回归测试。
- [ ] 运行现有 Dispatcher deep 测试，确认 deep mock 路线仍然通过。

### Task 9: 补充公式 ledger 测试并做最小归一化

**Files:**

- Modify: `agents/src/test/KnowledgeModelNoteGeneration.test.ets`
- Modify: `agents/src/main/ets/agents/KnowledgeModel.ets`（仅在测试确认问题存在时）

- [ ] 添加无等号公式进入 ledger 的测试。
- [ ] 先确认当前测试在旧逻辑下能暴露缺失。
- [ ] 复用 `ContentProtocol` 的公式识别能力，不新增第二套公式解析规则。
- [ ] 运行 deep 相关测试和 common note-generation 测试。

### Task 10: metadata 质量修复（P1，只有测试证明需要时才做）

**Files:**

- Modify: `agents/src/test/KnowledgeModelNoteGeneration.test.ets`
- Modify: `agents/src/main/ets/agents/KnowledgeModel.ets`

- [ ] 添加第一个 section metadata 不完整、第二个 section metadata 完整的测试。
- [ ] 先确认当前结果确实丢失后续 metadata。
- [ ] 只补齐非空字段，不新增额外 LLM 调用。
- [ ] 重新验证 summary 60 字限制、difficulty 1–4 和既有 standard 行为。

## 6. 真实虚拟机验证计划

代码测试通过后，必须使用全新会话验证，不能继续使用反复重试过的旧会话。

### 6.1 准备

1. 启动 DevEco Studio 虚拟机。
2. 确认屏幕已解锁。
3. 确认应用使用当前构建产物。
4. 新建一个空白会话。
5. 只输入一次长数学材料，不重复粘贴失败内容。

### 6.2 deep 触发条件

使用满足以下至少一项的材料：

- 文本长度超过 12000 字符；
- 至少 3 个 source fragments；
- 至少 2 页 OCR 材料；
- 明确包含“证明”或“推导”要求。

### 6.3 观察内容

需要记录：

- 是否进入 deep 路线；
- outline section 数量；
- 初始 LLM 调用次数；
- 是否出现 `SECTION_EMPTY`；
- 是否出现 `VERIFIER_DECISION_MISSING`；
- 是否出现 `DEEP_*` issue；
- 是否出现 `TRUTH_CHECK_ERROR`；
- `stopReason`；
- 是否进入 `repeated_issue_fingerprint`；
- 是否打开笔记编辑页；
- 是否成功保存。

### 6.4 失败时的取证

如果仍然失败，不要只复制最后一行错误。应保存：

- 用户界面显示的完整错误；
- `stop=` 后面的值；
- 所有 issue code；
- 是否带 `sectionId`；
- 是否带 `sourceId`；
- 至少两轮 checkpoint 的 issue fingerprint。

重点查看的表：

- `note_generation_run`；
- `note_generation_log`；
- `note_generation_checkpoint`。

如果错误仍是 `repeated_issue_fingerprint`，先比较两轮 issue fingerprint 是否完全一致，再判断 repair 是否命中了同一个 section。不要先放宽 verifier。

## 7. 验收标准

deep 路线只有满足以下条件才算完成：

- [ ] `KnowledgeModel.structureDeepDraft` 有真实多 section 回归测试。
- [ ] deep repair 对带 `sectionId` 的 issue 修正确 section。
- [ ] deep repair 对无 `sectionId` 但有 `sourceId` 的 issue 能定位到正确 section。
- [ ] 无法定位的全局 hard issue 不会静默只重写第一个 section。
- [ ] deep evidence 保留有效 source mapping 和 `origin='pipeline'`。
- [ ] verifier 和 TruthCheck 仍然是硬门禁，没有为了通过测试而绕过。
- [ ] deep 不因 section 数量失控而产生超预算调用。
- [ ] 虚拟机能进入 deep 生成的笔记编辑页。
- [ ] 虚拟机中 deep 笔记能成功保存。
- [ ] standard 路线已有的生成、摘要、公式、难度、标题和保存行为不回归。

## 8. 暂不处理的事项

以下事项不是本轮 deep 稳定性修复的目标：

- 不重新拆分或删除 `KnowledgeModel`。
- 不重写 Dispatcher 总体架构。
- 不删除 verifier 或 TruthCheck。
- 不把所有 deep issue 降级成 warning。
- 不新增第三方依赖。
- 不在没有真实测试证明前重做 metadata 聚合。
- 不在没有用户明确要求前 commit 或 push。

## 9. 本补充的执行顺序

```text
先更新文档
  -> 建立真实 deep KnowledgeModel 测试
  -> 运行测试并定位具体失败阶段
  -> 建立 repair 目标选择测试
  -> 只修被测试证明的问题
  -> 运行 ArkTS lint / Hypium / DevEco build
  -> 全新会话进行虚拟机 deep 验收
  -> 记录结果后再决定是否处理 P1 质量问题
```

**本轮文档更新完成后的下一步：**Task 6–9 的测试和最小代码修复已经完成；下一步是设备侧执行 Hypium 和全新会话的 deep 虚拟机验收。只有设备测试或真实 checkpoint 取证继续指出具体问题，才进入后续 P1 修复。

---

# 2026-09-23 Execution Record

## 已完成

- [x] 在 `KnowledgeModelNoteGeneration.test.ets` 中加入真实 `KnowledgeModel.structureDeepDraft()` 多 section 回归测试。
- [x] 加入 repair 目标选择测试：issue 没有 `sectionId`、但带有第二个 source 的 `sourceId` 时，最后一次 repair 请求第二个 section。
- [x] `KnowledgeModel.repairDeepDraft()` 按 `sectionId -> sourceId -> mustInclude -> 全局问题` 解析 repair 目标；无法定位时抛出明确错误，不再默认修第一个 section。
- [x] deep/standard prompt 复用公共 `LATEX_GENERATION_RULES`。
- [x] deep ledger 复用 `ContentProtocol.hasFormulaSyntax()` 识别公式。
- [x] `git diff --check` 通过。
- [x] `npm --prefix scripts/arkts-lint test` 通过：122 tests passed。
- [x] `devecocli build --modules common agents` 通过：`BUILD SUCCESSFUL`。

## 当前验证限制

- [ ] `agents` 和 `common` 当前没有 `ohosTest` target，无法使用 `devecocli build --modules agents@ohosTest common@ohosTest` 编译测试目标。
- [ ] 当前没有在线设备：`devecocli device list` 返回 `No active devices`，因此尚未执行 DevEco/Hypium 设备测试。
- [ ] 尚未用长材料、多 section、多公式样例完成 deep 虚拟机验收。
- [ ] 尚未修改前端公式渲染器；要先通过设备日志确认是输入格式、ContentProtocol、KaTeX 兼容性，还是整段 fallback 粒度问题。

## Lint 结果

`node scripts/arkts-lint/index.mjs` 当前报告 20 errors、441 warnings。明确命中的 `agents/src/main/ets/agents/KnowledgeModel.ets:1636` 的 `throw llmErr` 属于已有代码，未由本轮改动引入；本轮生产代码已经通过 DevEco ArkTS 编译。其余 lint 输出主要是仓库既有 warning，暂不在 deep 稳定性任务中顺带重构。

## 下一步

1. 启动 DevEco Studio 虚拟机并确认设备在线。
2. 用全新会话运行标准 deep 长样例，记录 section 数量、调用次数、issue code、`sectionId`、`sourceId`、`stopReason` 和最终保存结果。
3. 在设备上执行新增 `KnowledgeModel`、`ContentProtocol` 测试；若失败，再根据具体失败阶段做最小修改。
4. 只有确认是前端整段 fallback 后，才处理单公式级渲染降级。
