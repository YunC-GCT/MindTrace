# OCR 后的 LLM 预处理链路核查

> 核查当前图片输入从相机/相册、OCR、分类、展示、笔记生成到最终持久化的真实源码链路，回答 OCR 正文是否先经过 LLM 预处理。

## 结论

当前默认图片识别链路中，**OCR 正文没有经过 LLM 纠错、改写、公式修复或语义预处理**。更准确地说，图片文本并非 OCR 后逐字原样返回，而是依次经过：

1. `OcrTool` 识别普通文字与公式；
2. `TypeClassifier.preprocessText` 做确定性的本地规则清洗；
3. LLM 读取清洗后的文本，只输出 `category`、`subject`、`chapter`、`confidence` 四项分类元数据；
4. UI 展示的“识别内容”仍是清洗后的 OCR 文本，不是 LLM 改写文本。

因此，对“图像识别之后直接返回识别内容，没有让 LLM 进行一轮预处理”的判断应表述为：**基本正确；中间有本地规则清洗和一次 LLM 分类，但没有针对 OCR 正文的 LLM 预处理。**

只有用户明确要求“生成笔记”或“整理成笔记”时，系统才在 OCR 与分类之后调用 LLM 生成 `KnowledgeUnit` 草稿。这是独立的笔记生成阶段，不会把 LLM 生成结果回写成 OCR 正文。

## 默认图片识别链路

### 1. 选图只产生图片 URI

浮窗中的相机与相册动作只取得 URI，并把它写入输入 ViewModel 的图片预览状态，尚未执行 OCR 或 LLM：

- `entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets:760-798`
- `entry/src/main/ets/viewmodels/AgentInputViewModel.ets:238-260`

用户发送后，有图片 URI 就调用 `captureReply(sessionId, uri, msg)`；`ConversationRuntime` 将其转换为 `kind: 'image'` 的 conversation request：

- `entry/src/main/ets/services/ConversationRuntime.ets:70-77`

### 2. Conversation workflow 先判断用户要“识别”还是“生成笔记”

图片请求先进入 `classify_image_intent`。没有附带文字或文字为 `[图片]` 时，意图默认为 `chat`；只有意图为 `note_generation` 时才进入 `image_note_reply`，其余进入 `image_reply`：

- `entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets:259-269`
- `entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets:394-407`

默认的 `image_reply` 路径调用 `analyzeImage`，保存 OCR 素材，再直接调用 `formatAnalyzeReply` 形成一条 AI 消息：

- `entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets:479-497`

### 3. `analyzeImage` 只运行 Capture 与 Classify

`AiService.analyzeImage` 自身的契约是“只 OCR + 分类，返回识别内容，不生成笔记、不入库”。它调用 `Dispatcher.dispatch` 时传入：

- `persist: false`
- `includeRawText: true`
- `analysisOnly: true`

证据：`entry/src/main/ets/services/AiService.ets:85-113`。

`Dispatcher` 构造的 Capture workflow 顺序是 `START -> capture -> classify`。在 `classify` 后，`analysisOnly` 为真就直接到 `END`，不会进入 `structure`、`truth_check` 或 `persist`：

- `agents/src/main/ets/core/Dispatcher.ets:1627-1659`

这也符合架构约束：`Dispatcher.dispatch` 是 Capture workflow 的唯一公开业务入口，见 `docs/specs/018-agent-workflow-architecture.md:45-56`。

### 4. OCR 与本地规则清洗

`OcrNode` 调用 `TypeClassifier.recognizeText`，随后把 `recognized.text` 写入 `captureText`：

- `agents/src/main/ets/graph/nodes/OcrNode.ets:22-27`

对于图片，`TypeClassifier` 调用 `OcrTool.recognize(imageUri)` 获取文字，并合并可选的用户补充文本：

- `agents/src/main/ets/agents/TypeClassifier.ets:92-100`
- `agents/src/main/ets/agents/TypeClassifier.ets:147-160`
- `agents/src/main/ets/agents/TypeClassifier.ets:165-172`

随后执行的 `preprocessText` 是纯确定性字符串规则：统一换行、删除 NUL 与替换字符、折叠空白、删除固定噪声行、移除空行并按字符上限截断：

- `agents/src/main/ets/agents/TypeClassifier.ets:174-199`
- `agents/src/main/ets/agents/TypeClassifier.ets:201-213`

这里没有 `LlmClient` 或 `LlmGuard` 调用，因此它不是 LLM 预处理。

`OcrTool` 本身使用 CoreVisionKit 与本地 HTTP OCR 服务识别普通文字和公式，并将两者拼为 prompt text；该类也没有调用 LLM：

- `agents/src/main/ets/mcp/tools/OcrTool.ets:98-108`
- `agents/src/main/ets/mcp/tools/OcrTool.ets:111-173`
- `agents/src/main/ets/mcp/tools/OcrTool.ets:376-385`

### 5. LLM 只做分类，不改 OCR 正文

`ClassifyNode` 把 `captureText` 传给 `TypeClassifier.classifyText`：

- `agents/src/main/ets/graph/nodes/ClassifyNode.ets:9-15`

分类 prompt 明确要求模型只返回 JSON，并仅识别 `category`、`subject`、`chapter`、`confidence`：

- `agents/src/main/ets/agents/TypeClassifier.ets:223-242`

分类成功或规则兜底时，结果对象的 `ocrText` 都直接赋值为传入的 `text`。模型输出只用于分类字段，不会覆盖 OCR 正文：

- `agents/src/main/ets/agents/TypeClassifier.ets:113-143`

这意味着默认链路中确实发生了一次 LLM 调用，但它是**分类调用**，不是 OCR 正文预处理调用。若分类 LLM 失败，代码会退回本地规则分类；识别正文仍保留。

### 6. UI 直接展示清洗后的 OCR 文本

`formatAnalyzeReply` 从 `result.ocrText` 取正文，最多裁到 1600 个字符，然后拼接类型、学科、章节、置信度与“识别内容”。它没有再发起 LLM 调用：

- `entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets:950-960`

所以用户看到的“识别内容”是经过本地规则清洗后的 Capture 文本，而不是经过 LLM 修订的内容。

## 用户确认与持久化边界

默认图片识别路径没有 OCR 正文确认步骤。识别成功后，workflow 会先通过 `safeSaveOcrResult` 保存为会话的待处理素材，再显示识别结果：

- `entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets:479-497`
- `entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets:1129-1136`
- `entry/src/main/ets/services/AgentMemoryService.ets:83-107`

这里保存的是会话记忆中的 OCR 素材，不是最终 `KnowledgeUnit`。

用户明确要求生成笔记时，`image_note_reply` 会：

1. 再取得 OCR 与分类结果；
2. 将当前图片的 `ocrText`、分类元数据和用户指令拼成来源材料；
3. 调用 `generateNoteDraft` 让 LLM 生成笔记草稿；
4. 把草稿交给 UI 预览，而不是立即写成最终笔记。

证据：

- `entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets:505-547`
- `entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets:549-597`
- `entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets:598-612`

用户确认草稿后，`ConversationDraftWorkflow` 才调用确认 gateway；`AiService.confirmDraft` 再通过 `Dispatcher.dispatch(..., { persist: true })` 写入最终 `KnowledgeUnit`：

- `entry/src/main/ets/workflows/conversation/ConversationDraftWorkflow.ets:106-122`
- `entry/src/main/ets/services/AiService.ets:404-428`

## 术语与设计依据

仓库领域词汇将 `Capture` 定义为“通过 OCR 或手动输入产生原始文本”，将 `Structure` 定义为“由 LLM 把 Capture 结果转成 KnowledgeUnit”：

- `CONTEXT.md:56-62`

这一边界与当前实现一致：默认识别到展示只完成 Capture 与 Classify；只有笔记生成路径才进入 LLM Structure。不要把分类 LLM 调用称作“OCR 预处理”，也不要把待处理 OCR 素材的会话持久化等同于最终笔记持久化。

## 风险与改进含义

当前缺口不是“完全没有 LLM”，而是**没有面向 OCR 正文质量的模型层**。因此 OCR 中的断行、错字、公式串扰和上下标误识别，除现有固定规则能处理的部分外，会原样进入展示与后续笔记生成素材。

若要补充 LLM 预处理，建议将其定义为独立且可审计的 Capture 后处理能力，至少明确：

- 原始 OCR 与修订文本是否同时保留；
- 模型是否允许改写数学表达，如何避免“纠错”引入事实错误；
- 用户在生成笔记前是否可以对比与确认修订；
- 分类应读取原始文本还是修订文本；
- 失败时是否回退到当前确定性规则清洗结果。

这些属于后续设计问题，本次只读核查未修改运行时行为。
