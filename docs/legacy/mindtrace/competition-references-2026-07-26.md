# MindTrace 参考资料清单

> 用于参赛材料附件 · 生成日期: 2026-07-26

---

## 一、GitHub 开源仓库

### 直接依赖（嵌入源码）

| 项目 | 许可证 | 版本 | 用途 |
|------|--------|------|------|
| [KaTeX/KaTeX](https://github.com/KaTeX/KaTeX) | MIT | v0.16.9 | 数学公式渲染引擎，支持 LaTeX 语法编译为 HTML+CSS，项目中用于 chat 气泡 Markdown 公式渲染、笔记详情页公式展示、公式预览卡片 |
| [markedjs/marked](https://github.com/markedjs/marked) | MIT | — | Markdown 解析器，将 AI 生成的 Markdown 文本转换为 HTML，配合 KaTeX 实现公式+富文本混合渲染 |

### 设计与架构参考

| 项目 | 用途 | 引用位置 |
|------|------|---------|
| swiftui-to-arkui (TodoItem 模式) | `StudyPlanItem` 数据模型设计参考，从 SwiftUI `@Observable` 到 ArkTS `@Observed` 的状态管理迁移 | `common/src/main/ets/models/StudyPlan.ets:5` |
| [react-native-webview/react-native-webview](https://github.com/react-native-webview/react-native-webview) | WebView 组件生命周期与内存管理调研参考（仅文档内引用，未集成代码） | `docs/2026-07-24/research-multi-webview-performance-20260724.md` |

### 项目自身

| 项目 | 说明 |
|------|------|
| [YunC-GCT/Math-Mind](https://github.com/YunC-GCT/Math-Mind) | MindTrace 主仓库，HarmonyOS 数学学习助手 |

---

## 二、API 与协议

| 来源 | 文档链接 | 用途 |
|------|---------|------|
| DeepSeek API (Chat Completions) | https://api-docs.deepseek.com/zh-cn/ | 核心 LLM 后端，对话生成、题型分类、知识结构化均通过 OpenAI 兼容接口调 `deepseek-v4-pro` 模型；支持 SSE 流式输出与思考模式 (Thinking Mode) |
| DeepSeek 思考模式指南 | https://api-docs.deepseek.com/zh-cn/guides/thinking_mode | 流式输出中 `reasoning_content` 与 `content` 的处理策略、多轮上下文拼接规则 |
| OpenAI API (Structured Outputs) | https://platform.openai.com/docs/api-reference/chat/object | `response_format: { type: "json_object" }` 协议参考，用于 `LlmGuard` 结构化输出校验 |
| Qwen Cloud API | https://docs.qwencloud.com/api-reference/chat/dashscope | 备选 API 的 `response_format` 参数对比参考 |

---

## 三、平台与框架

| 来源 | 文档链接 | 用途 |
|------|---------|------|
| HarmonyOS `@kit.NetworkKit` (http 模块) | [OpenHarmony 官方文档](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-network-kit/js-apis-http.md) | HTTP 请求与 SSE 流式数据接收 (`requestInStream` + `on('dataReceive')`) |
| HarmonyOS `@kit.ArkData` (preferences) | HarmonyOS SDK 文档 | LLM 配置、OCR 配置、聊天历史、用户设置的本地持久化存储 |
| HarmonyOS `@kit.ArkTS` (util.TextDecoder) | HarmonyOS SDK 文档 | SSE 流式响应 ArrayBuffer → UTF-8 字符串解码 |
| HarmonyOS ArkUI 声明式框架 | HarmonyOS SDK 文档 | 全部 UI 组件 (`@Component` / `@State` / `@Prop` / `LazyForEach`) |

---

## 四、学术与标准

| 来源 | 链接 | 引用位置 |
|------|------|---------|
| GitHub Docs — Writing mathematical expressions | https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/writing-mathematical-expressions | `docs/2026-07-22/render-protocol-optimization-route-20260722.md` |
| LaTeX 数学公式语法规范 | — | KaTeX 支持的 LaTeX 子集，项目中所有数学渲染的基础语法标准 |
| SSE (Server-Sent Events) 协议规范 | W3C / WHATWG | DeepSeek 流式 API 的数据传输格式 (`text/event-stream`, `data:` 行, `\n\n` 事件分隔) |
| OpenAI Chat Completions API 协议 | https://api-docs.deepseek.com/zh-cn/api/create-chat-completion | `LlmClient` 请求/响应格式的协议基准 |

---

## 五、文献与调研

| 文档 | 路径 | 内容 |
|------|------|------|
| 公式渲染策略调研 | `docs/2026-07-24/research-formula-render-strategies-20260724.md` | ChatGPT/Claude/DeepSeek 等产品的数学公式渲染方案对比，KaTeX vs MathJax 选型分析 |
| 多 WebView 分块渲染性能调研 | `docs/2026-07-24/research-multi-webview-performance-20260724.md` | ArkUI WebView 1800vp 高度上限的解决方案调研，React Native WebView 参考 |
| HarmonyOS HTTP 流式输出调研 | `docs/research-harmonyos-http-streaming-20260724.md` | `@kit.NetworkKit` http 模块 SSE 支持能力调研 |
| 渲染协议优化路线 | `docs/2026-07-22/render-protocol-optimization-route-20260722.md` | LLM 输出 Guard、LaTeX 风险归一化、公式安全截断方案 |

---

## 六、总结

| 类别 | 数量 |
|------|------|
| GitHub 开源仓库（直接依赖） | 2 |
| GitHub 开源仓库（设计参考） | 2 |
| API 与协议 | 4 |
| 平台框架 | 4 |
| 学术标准 | 4 |
| 内部调研文档 | 4 |
| **合计** | **20** |
