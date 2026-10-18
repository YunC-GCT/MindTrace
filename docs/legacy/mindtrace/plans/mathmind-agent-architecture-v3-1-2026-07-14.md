# MathMind Agent 架构 v3.1

> 版本 v3.1 · 21 模块 · 7 调度链 · 4 MCP Tool · 3 入口 Agent

---

## 21 模块清单

| # | 模块 | 类别 | 文件 | 优先级 | 说明 |
|---|------|------|------|--------|------|
| A1 | **SkillAgent** | 入口 | `skill/SkillAbility.ets` | P0 | 元服务卡片入口，处理语音/卡片交互 |
| A2 | **FormAgent** | 入口 | `cardservice/FormAbility.ets` | P0 | 表单服务入口，卡片 UI 渲染 |
| A3 | **UIAgent** | 入口 | `entry/EntryAbility.ets` | P0 | 主应用入口，页面路由与生命周期 |
| A4 | **Dispatcher** | 主调度 | `agents/core/Dispatcher.ets` | P0 | 统一调度中心，路由请求到目标 Agent |
| A5 | **TypeClassifier** | 核心 | `agents/agents/TypeClassifier.ets` | P0 | 两轴分类器，输出 (subject, chapter, type) |
| A6 | **KnowledgeModel** | 核心 | `agents/agents/KnowledgeModel.ets` | P0 | 知识单元建模，结构化笔记存储 |
| A7 | **ContextLink** | 核心 | `agents/agents/ContextLink.ets` | P0 | 上下文关联，建立笔记间语义链接 |
| A8 | **ReviewAgent** ⭐ | 核心 | `agents/agents/ReviewAgent.ets` | P0 | 间隔复习调度，艾宾浩斯算法 |
| A9 | **RecallGraphAgent** ⭐ | 核心 | `agents/agents/RecallGraphAgent.ets` | P0 | 知识图谱构建与跨时空检索 |
| A10 | **UserPrefAgent** | 辅助 | `agents/agents/UserPrefAgent.ets` | P0 | 用户偏好管理，考试日期/静默时段 |
| A11 | **SearchAgent** | 辅助 | `agents/agents/SearchAgent.ets` | P0 | 全文/语义搜索，关键词+向量混合 |
| A12 | **VersionAgent** | 辅助 | `agents/agents/VersionAgent.ets` | P0 | 笔记版本控制，diff 与回滚 |
| A14 | **RecycleAgent** ⭐ | 辅助 | `agents/agents/RecycleAgent.ets` | P0 | 回收站管理，软删除/恢复/定时清理 |
| A15 | **FavoriteAgent** ⭐ | 辅助 | `agents/agents/FavoriteAgent.ets` | P0 | 收藏管理，星标/取消/收藏夹查询 |
| A16 | **ExportAgent** | 辅助 | `agents/agents/ExportAgent.ets` | P2 | 数据导出，LaTeX/PDF/Markdown 格式 |
| A17 | **McpServerAgent** | MCP | `agents/mcp/McpServer.ets` | P0 | MCP 服务端，注册工具/处理请求 |
| A18 | **McpClientAgent** | MCP | `agents/mcp/McpClient.ets` | P0 | MCP 客户端，调用 LLM/OCR 等外部能力 |
| T1 | **OcrTool** | MCP Tool | `agents/mcp/tools/OcrTool.ets` | P0 | 图片 OCR → LaTeX，基于 ML Kit |
| T2 | **EmbeddingTool** | MCP Tool | `agents/mcp/tools/EmbeddingTool.ets` | P1(S1) | 文本向量化，初赛用 Jaccard 替代 |
| T3 | **LlmTool** | MCP Tool | `agents/mcp/tools/LlmTool.ets` | P0 | 多 LLM 推理，**默认 DeepSeek(SiliconFlow)**，降级小艺Kit |
| T4 | **SearchTool** | MCP Tool | `agents/mcp/tools/SearchTool.ets` | P0 | 笔记搜索，基于 RDB 全文索引 |

> ⭐ = v3.1 新增模块。编号 A13 保留（预留给未来模块）。

---

## 7 条调度链

| 链 | 触发方式 | 路径 | SLA | 说明 |
|----|----------|------|-----|------|
| **D1 拍照链** | 拍照 / 语音录入 | A1/A3 → A4 → A5 → A6 → A7 → A9 → 写库 | < 3s | 端到端：OCR → 分类 → 建模 → 关联 → 图谱更新 |
| **D2 复习链** | 定时任务 / 新笔记入库 | A4 → A8 → 推送（异步 → A9） | < 1s | 计算复习卡片，推送通知，更新图谱复习状态 |
| **D3 搜索链** | "小艺找..." / 搜索栏 | A1/A3 → A4 → A11 → T4 | < 500ms | 关键词 + 语义混合搜索 |
| **D4 偏好链** | 设置页保存偏好 | A1/A3 → A4 → A10 | < 200ms | 考试日期、静默时段、推送限制 |
| **D5 回收站链** | 软删除 / 恢复 | A1/A3 → A4 → A14 | < 500ms | 笔记移入/移出回收站，30 天自动清理 |
| **D6 收藏链** | 收藏 / 取消收藏 | A1/A3 → A4 → A15 | < 200ms | 星标切换，收藏夹查询 |
| **D7 MCP 协议** | LLM/OCR/搜索调用 | Agent → A18 → A17 → T1–T4 | < 50ms | 内部 MCP 总线，统一工具调用协议 |

### 调度链时序图（D1 拍照链）

```
用户拍照 → SkillAgent ──┐
                        ├─→ Dispatcher ─→ TypeClassifier (分类)
用户输入 → UIAgent ─────┘                    │
                                             ├─→ KnowledgeModel (建模)
                                             │       │
                                             ├─→ ContextLink (关联)
                                             │       │
                                             └─→ RecallGraphAgent (图谱更新)
                                                     │
                                                     └─→ RDB 写库 → 返回结果
```

---

## 4 MCP Tool

| Tool | 用途 | 输入 | 输出 | MVP 初赛方案 |
|------|------|------|------|-------------|
| **T1 OCR** | 图片 → LaTeX | `{ image: base64 }` | `{ latex: string, confidence: float }` | ✅ ML Kit 文字识别 |
| **T2 Embedding** | 文本 → 向量 | `{ texts: string[] }` | `{ vectors: float[][] }` | ⏳ S1 复赛（初赛用 Jaccard 相似度替代） |
| **T3 LLM** | 多 LLM 推理 | `{ prompt, model, maxTokens }` | `{ completion, usage }` | ✅ 小艺 Kit + DeepSeek API |
| **T4 Search** | 笔记搜索 | `{ query, filters, topK }` | `{ results: Note[] }` | ✅ RDB 全文索引 + LIKE 查询 |

### MCP 通信模型

```
┌──────────┐    MCP/JSON-RPC    ┌──────────────┐
│  Agent   │ ◄──────────────► │ McpClient    │
│ (调用方)  │                   │ Agent (A18)  │
└──────────┘                   └──────┬───────┘
                                      │
                              ┌───────▼───────┐
                              │ McpServer     │
                              │ Agent (A17)   │
                              └───────┬───────┘
                                      │
                    ┌─────────────────┼─────────────────┐
                    │                 │                 │
              ┌─────▼─────┐   ┌──────▼──────┐   ┌─────▼─────┐
              │ OcrTool   │   │  LlmTool    │   │SearchTool │
              │   (T1)    │   │   (T3)      │   │  (T4)     │
              └───────────┘   └─────────────┘   └───────────┘
```

---

## Agent 间依赖关系

```
Dispatcher (A4)
├── TypeClassifier (A5) ──── 依赖 → T3 LLM, T2 Embedding
├── KnowledgeModel (A6) ──── 依赖 → A5 (分类结果)
├── ContextLink (A7) ─────── 依赖 → A6 (知识单元), A9 (图谱)
├── ReviewAgent (A8) ─────── 依赖 → A6, A10 (偏好)
├── RecallGraphAgent (A9) ── 依赖 → A6, A7
├── UserPrefAgent (A10) ──── 无依赖
├── SearchAgent (A11) ─────── 依赖 → T4
├── VersionAgent (A12) ───── 依赖 → A6
├── RecycleAgent (A14) ───── 依赖 → A6
├── FavoriteAgent (A15) ──── 依赖 → A6
├── ExportAgent (A16) ────── 依赖 → A6, A9
├── McpClientAgent (A18) ─── 依赖 → A17
└── McpServerAgent (A17) ─── 注册 → T1, T2, T3, T4
```

---

## 设计原则

1. **本地优先 → API 降级兜底**
   - OCR / 分类 / 搜索优先本地执行，网络不可用时降级到本地规则引擎
   - LLM 推理本地用小艺 Kit，云端用 DeepSeek 兜底

2. **Agent 可独立测试**
   - 每个 Agent 暴露 `handle(context: AgentContext): Promise<AgentResult>` 接口
   - 单元测试可 mock Dispatcher 直接调用单个 Agent

3. **MCP 协议统一跨模型通信**
   - 所有外部能力（OCR/LLM/Search/Embedding）通过 MCP JSON-RPC 协议调用
   - 工具注册/发现由 McpServerAgent 统一管理

4. **两轴归类贯穿核心链路**
   - F5 TypeClassifier 提供分类 → F6 KnowledgeModel 结构化存储 → F7 ContextLink 语义关联
   - 所有笔记入库前必须经过两轴分类

---

## 模块目录结构

```
agents/
├── core/
│   └── Dispatcher.ets          # A4  主调度中心
├── agents/
│   ├── TypeClassifier.ets      # A5  两轴分类器
│   ├── KnowledgeModel.ets      # A6  知识单元建模
│   ├── ContextLink.ets         # A7  上下文关联
│   ├── ReviewAgent.ets         # A8  间隔复习 ⭐
│   ├── RecallGraphAgent.ets    # A9  知识图谱 ⭐
│   ├── UserPrefAgent.ets       # A10 用户偏好
│   ├── SearchAgent.ets         # A11 搜索
│   ├── VersionAgent.ets        # A12 版本控制
│   ├── RecycleAgent.ets        # A14 回收站 ⭐
│   ├── FavoriteAgent.ets       # A15 收藏 ⭐
│   └── ExportAgent.ets         # A16 数据导出
├── mcp/
│   ├── McpServer.ets           # A17 MCP 服务端
│   ├── McpClient.ets           # A18 MCP 客户端
│   └── tools/
│       ├── OcrTool.ets         # T1  OCR 工具
│       ├── EmbeddingTool.ets   # T2  向量化工具
│       ├── LlmTool.ets         # T3  LLM 工具
│       └── SearchTool.ets      # T4  搜索工具
skill/
└── SkillAbility.ets            # A1  元服务入口
cardservice/
└── FormAbility.ets             # A2  表单服务入口
entry/
└── EntryAbility.ets            # A3  主应用入口
```

---

*Agent 架构 v3.1 · 21 模块 · 7 调度链 · 4 MCP Tool*
