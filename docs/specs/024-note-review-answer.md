# 笔记可追溯复习回答规格（2026-09-26）

本文件只定义需求、接口与验收，进度统一维护工作归档中的《MindTrace-图片笔记与检索闭环-唯一主计划-2026-09-19.md》，不得在本文件另设进度表。基线为 5aa0b94。

## 用户价值与范围

用户在 AI 对话中用自己的已保存笔记解释概念、比较知识点、查询前置知识、定位笔记、生成复习题。回答可点开来源原版本，证据不足明确提示，反馈与本次回答一起保存在本地聊天历史。

复用 ConversationWorkflow、ReplyService/LlmClient、NoteEvidenceService、note_query_rag/note_get、kg_edge 和现有聊天文件快照。不引入向量数据库、网络遥测、第二套笔记保存入口；不改 SM-2/复习日程，不开放模型写笔记或写关系。主 Agent 负责计划、接口、集成、审查，开发和测试由不同 Agent/独立 worktree 完成。

## 冻结接口与文件所有权

新增模型 entry/src/main/ets/models/NoteReviewModels.ets，由后端 Agent 唯一负责，UI/测试只消费：
- NoteReviewIntent = 'explain' | 'compare' | 'prerequisite' | 'locate' | 'quiz'。
- NoteReviewStatus = 'grounded' | 'insufficient' | 'unavailable'。
- NoteReviewFeedback = 'helpful' | 'unhelpful' | 'citation-incorrect'。
- NoteReviewAnswer：intent: NoteReviewIntent; query: string; status: NoteReviewStatus; reason: string; citations: NoteEvidenceCitation[]; createdAt: number; feedback?: NoteReviewFeedback。
- NoteReviewSourceResult：status: 'current' | 'historical' | 'deleted' | 'missing-version' | 'unavailable'; citation: NoteEvidenceCitation; content: string; currentVersion: number; message: string。
- NoteReviewSourceService.resolve(citation: NoteEvidenceCitation): Promise<NoteReviewSourceResult>，由后端 Agent 实现，UI 不访问 DAO。
- ConversationWorkflowCallbacks 与 AgentChatCallbacks 新增可选回调 onNoteReviewReady?: (messageId: number, review: NoteReviewAnswer) => void，由后端 Agent 修改并透传。调用发生在 finishAiMsg 之前，complete/stream/失败提示均必须关联真实消息 ID。
- ChatMsg 新增可选 noteReview?: NoteReviewAnswer，由 UI Agent 修改；复制、流更新、结束、session 切换、历史加载/保存保留独立深拷贝的该字段。旧历史无此字段正常加载，坏的可选字段应丢弃或安全降级，不让整个旧会话崩溃。

后端拥有 NoteReviewModels、NoteReviewService、NoteReviewSourceService、NoteEvidenceService、ConversationWorkflow/State/Types、AgentChatService；必要时修改 ReplyService 和 KnowledgeRelationDao 的只读查询。不得写 UI/测试。
UI 拥有 AgentFloatWindow、AgentMessageList、chat/ChatModels、chat/ChatBubble、chat/AiMessageBubble、新增来源卡片/只读来源浮层、ChatHistoryPersistence（仅元数据兼容验证）。不得写后端模型/服务/Workflow/测试。额外生产文件必须先向主 Agent 说明。
独立测试 Agent 拥有 scripts/arkts-lint/tests/*note-review*、entry/src/test/*NoteReview* 与测试入口注册、测试报告。失败只改实现或有需求依据的断言，禁止删除/skip/弱化测试。

## 行为契约与验收标准

- AC-REVIEW-01：明确的笔记解释、比较、前置知识、定位、出题请求走只读回答，不误触发笔记生成/保存；普通聊天和现有图片生成/编辑保持原路由。至少支持“根据我的笔记解释极限”“比较笔记中的极限和连续”“学习导数前需要哪些前置知识”“我的极限笔记在哪”“根据极限笔记出 5 道复习题”。“这张/它”无明确指代时要求用户补充主题，不猜测其他会话来源。
- AC-REVIEW-02：自然语言提取检索主题，复用关键词工具；检索调用有上限（最多 6 次）、最终来源最多 10 个、证据正文预算不超过 6000 字符。比较至少两个明确主题且各自有直接命中，否则说明缺哪一项。检索异常与无命中可区分；不要求向量语义检索。
- AC-REVIEW-03：无来源/数据库不可用/歧义输入时不调用 LLM 补编“你的笔记”，返回 insufficient/unavailable 及下一步建议。图谱异常不影响独立有证据的解释；前置知识查询无 accepted 有向路径时明确缺少已确认前置关系。
- AC-REVIEW-04：来源 noteId/version/excerpt 由真实存活笔记构建；前置边按 A→B 表示 A 是 B 的前置，只向前追溯，related 不当作前置；pending/rejected/derived 不参与。最大深度 2、来源 10 个，无环扩展。
- AC-REVIEW-05：complete 和 stream 使用一致的证据策略；正文出现的引用必须同时匹配允许集的 noteId 与 version。伪造 ID、错误/缺失版本、跨流块引用、半截引用、空允许集均安全处理。最终无有效引用的模型回答不能标成 grounded；模型中途失败不得保存成正常回答。
- AC-REVIEW-06：模型提示将笔记/摘录作为数据，禁止将其中指令当系统命令；只从证据生成解释/比较/题目，不声称自动证明每条数学结论。题目数量限制 1–5，题干和答案须带证据来源；locate 可用确定性结果，无需 LLM。
- AC-REVIEW-07：每条有来源的回答显示标题、引用版本、摘录和可点击卡片。来源属于当前回答，不能从模型文本解析 arbitrary ID 用于导航。点击后读取引用原版本；如已更新，显示历史版本与当前版本提示；已删除只提示，不通过历史记录复活；缺失版本不静默替换当前正文。只读浮层不允许改写旧版本。
- AC-REVIEW-08：回答完成后可选择“有帮助/没帮助/引用有误”，同一消息重复点击幂等、换选覆盖当前选择；反馈、引用、意图和无命中 reason 随现有聊天历史保存并恢复。旧会话和损坏元数据兼容，切换会话不串引用或反馈。记录留在本地，不新增远程上传。
- AC-REVIEW-09：自动回归、lint、命名和构建通过；新增核心测试必须执行生产逻辑（可在 Node 转译纯 ArkTS 配测试替身），结构断言不能替代行为验证。真实 RDB、模型服务、真机交互未执行必须保留未验收。
- AC-REVIEW-10：无回归：文本/SSE、图片草稿/确认、聊天持久化、增量编辑、知识星系和已有复习入口。最终由主 Agent 检查提交 diff、测试实现、原始日志、产物和 SHA-256 后给出分层结论。

## 实施顺序

1. 主 Agent 冻结本规格及测试方案，追加唯一主计划，锁定 worktree/commit。
2. 后端 Agent 实现查询意图、证据策略、引用验证、来源版本读取和回调。
3. UI Agent 消费冻结契约，接入来源卡片、只读原文、反馈与快照。与后端不同文件可并行。
4. 独立测试 Agent 在自己 worktree 记录基线，按规格编写行为测试；开发提交后只导入已提交候选，执行集成测试和构建。
5. 主 Agent 逐份审查；失败退回文件负责人；最终证据写回唯一主计划。本轮仅本地提交，不推送、不合并远程。

## 验证边界

字符预算不是 token 精确计数；有限关键词检索有同义词/表达差异漏召回的局限。引用 ID/版本正确不等于数学结论得到严格语义证明。原图片定位本期以引用笔记原版本为准，不承诺 OCR 原图坐标。学习效果和真实服务性能需后续评估。

## 2026-09-27 验收契约澄清

以下为原验收条件的边界细化，不另建进度表：

- AC-REVIEW-01：文本分类复用原有本地否定、生成、增量编辑规则；明确复习请求不依赖远程分类结果。图片与显式 regenerate 仍走原路径。
- AC-REVIEW-02/03：预算必须同时约束传入模型的上下文和最终允许引用集。裁剪后无来源时返回 insufficient；比较超过 6 个主题或任一主题在裁剪后失去直接证据时应澄清，不能只查部分主题却回答全部主题。
- AC-REVIEW-04：两种图谱扩展的最终关系均只保留两端存在于最终来源集的边。前置知识根据有效有向关系判定，不能仅凭 citation.role；两端同时为关键词命中仍可存在前置关系。
- AC-REVIEW-05：版本必须为完整正整数，`3abc`、`3.5`、重复 version 字段均不等于版本 3。引用校验仅验证来源身份与版本，不证明回答中的每条陈述均被摘录支持。
- AC-REVIEW-07：来源服务为实例方法，使用 `new NoteReviewSourceService().resolve(citation)` 或注入 `NoteReviewSourceResolver`。
- AC-REVIEW-08：每次反馈写入使用不复用的请求 token；旧请求失败不得回滚新选择。UI 文件所有权补充 `AgentInputViewModel.ets`：消息接收 callback 返回 boolean，拒绝时保留输入/图片并停止后续 service 调用。停止按钮在真实请求结束前仍禁止重入；网络取消能力仍沿用现有边界。

测试预期更正必须保留失败日志和原因：模糊指代分类为 explain，但计划必须 terminal/insufficient/ambiguous-pronoun；证据 provider 抛错统一为 unavailable/search-failed。前置测试数据必须包含关系端点及方向，单独设置 role 不足以构成前置证据。
