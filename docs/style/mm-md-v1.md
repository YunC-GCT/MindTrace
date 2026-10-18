# MM-MD-v1 — Note Markdown 协议

> **Status**: active. 本文件是笔记正文的唯一协议定义；实现以 `common/src/main/ets/render/ContentProtocol.ets` 为准。
> **Source**: 2026-07-22 渲染协议设计（原文已随旧计划清理，规范部分保留在本文件）。
> **Related**: [ADR-0016](../adr/0016-reply-contract-by-transport.md)（Reply Body 契约）、[spec 021](../specs/021-chat-streaming-incremental-rendering.md)（流式渲染）、`CONTEXT.md`（Reply Body / StreamEvent）。

## 1. 总原则

### 1.1 单一事实源

整个工程只承认一种可存储的笔记正文协议：**MindTrace Note Markdown v1**（`MM-MD-v1`）。它不是完整 Markdown，而是项目内白名单子集。

AI、数据库、Markdown 解析器、LaTeX 归一化器、ArkUI 渲染器都以这个协议为准。任何输入来源可以不规范，但入库前必须归一成 `MM-MD-v1`。

### 1.2 AI 不能直接控制页面结构

AI 可以生成：标题候选、分类、标签、字段数组 `fields`、字段正文 `field.value`、必要的公式文本。

AI 不应该生成：

- 顶层页面标题结构
- 原始 HTML
- 任意 Markdown 扩展
- 任意 ArkUI 样式含义
- 表格、图片、链接等当前渲染器不稳定支持的格式
- 复杂到本地无法校验的 LaTeX 宏

页面结构由 `KnowledgeModel.contentFromFields()` 或后续统一 `RenderDocumentBuilder` 构造。

### 1.3 兜底分层

| 层级 | 负责对象 | 允许做什么 | 不允许做什么 |
|---|---|---|---|
| AI Prompt | 生成约束 | 说明协议、给正反例 | 假设 AI 一定遵守 |
| `LlmGuard` | JSON 外壳 | 校验字段类型、重试 | 解释数学内容 |
| `ContentProtocol` | 文本协议 | 机械归一、修补边界 | 发明缺失公式 |
| `LatexRiskNormalizer` | 公式风险 | 修补可判定小问题 | 强行渲染高风险公式 |
| `MarkdownParser` | 块解析 | 容错拆块 | 抛异常阻断页面 |
| Renderer | 显示 | WebView 渲染或纯文本回退 | 空白失败 |

## 2. 块级语法

只支持以下块：

| 类型 | 写法 | 说明 |
|---|---|---|
| 标题 | `#` / `##` / `###` | AI 字段值里不推荐写标题，标题由上层拼接 |
| 段落 | 普通文本 | 可包含行内公式 |
| 无序列表 | `- item` | 只支持一层 |
| 有序列表 | `1. item` | 只支持一层 |
| 引用 | `> text` | 可用于注意点 |
| 代码块 | 三个反引号 | 代码块内不解析公式 |
| 分割线 | `---` | 少用 |
| 公式块 | 独立 `$$` fence | 重要公式、长公式、多行推导 |

暂不纳入 AI 生成协议：表格、原始 HTML、图片、链接跳转、任务列表、多级嵌套列表、脚注、Mermaid / 图表。这些能力以后可以加，但必须先扩展协议、解析器和兜底测试。

## 3. 行内语法

| 类型 | 写法 | 说明 |
|---|---|---|
| 加粗 | `**text**` | 只用于短强调 |
| 行内代码 | `` `code` `` | 不解析公式 |
| 行内公式 | `$...$` | 短公式，必须融入句子 |

不支持在同一段里混用复杂嵌套格式，例如：

```markdown
**当 $x \to 0$ 时 `code` 也成立**
```

这种内容应拆成普通文本或更简单的段落。

## 4. 数学公式协议

### 4.1 唯一推荐定界符

| 类型 | 定界符 | 是否推荐 |
|---|---|---|
| 行内公式 | `$...$` | 推荐 |
| 独立公式块 | 独立行 `$$` / `$$` | 推荐 |
| 行内公式 | `\(...\)` | 只兼容输入，不作为 AI 输出 |
| 独立公式 | `\[...\]` | 只兼容输入，不作为 AI 输出 |
| 裸 LaTeX | `\frac{...}{...}` | 禁止直接入库 |

规范公式块必须写成：

```markdown
这里先说明公式用途。

$$
\int x^n\,dx = \frac{x^{n+1}}{n+1} + C \quad (n \neq -1)
$$

这里解释条件和结论。
```

不推荐写成：

```markdown
这里先说明 $$\int x^n dx = ...$$ 然后继续说。
```

### 4.2 什么时候用行内公式

满足以下条件时用 `$...$`：

- 公式是句子的一部分。
- 公式较短，建议不超过 40 个字符。
- 只表达变量、条件、简单关系或短结论。
- 不需要用户横向查看、复制或逐步对齐。
- 不包含多行、不包含 `\\` 换行。

示例：`当 $a > 0$ 时，二次函数开口向上。`

### 4.3 什么时候用独立公式块

满足任一条件时用独立公式块：

- 公式是本段核心结论。
- 公式长度超过 40 个字符。
- 包含 `\frac`、`\sum`、`\int`、`\lim`、`\sqrt`、`\prod` 等复杂结构。
- 包含分段、矩阵、方程组、对齐推导。
- 需要展示多步等式变形。
- 公式包含多个条件或约束。
- 用户需要单独检查公式是否正确。

多步推导用 `aligned`，不要用裸 `align`：

```markdown
$$
\begin{aligned}
ax^2 + bx + c
&= a\left(x^2 + \frac{b}{a}x\right) + c \\
&= a\left(x + \frac{b}{2a}\right)^2 + c - \frac{b^2}{4a}
\end{aligned}
$$
```

### 4.4 块级公式不要融入句子

错误：

```markdown
由 $$a^2+b^2=c^2$$ 可知三角形是直角三角形。
```

正确：

```markdown
由勾股定理可得：

$$
a^2 + b^2 = c^2
$$

因此该三角形是直角三角形。
```

如果必须放在句子中，就改成行内公式：`由 $a^2+b^2=c^2$ 可知三角形是直角三角形。`

### 4.5 公式块内部禁止再写行内公式

规则：

- `$$...$$` 内部不允许出现 `$`。
- `$$...$$` 内的条件也属于同一个数学环境。
- 中文解释不要写进公式块，除非使用 `\text{}` 且内容很短。

### 4.6 标题里禁止公式

标题由 ArkUI 原生 `Text` 渲染，公式会被当普通文本；标题还参与列表、搜索、缓存 key，不适合放复杂符号。

```markdown
## 幂函数积分

要求计算：

$$
\int x^n\,dx
$$
```

## 5. 实现与验证

| 关注点 | 位置 |
|---|---|
| 归一化 / 校验 | `common/src/main/ets/render/ContentProtocol.ets` |
| LaTeX 风险修补 | `common/src/main/ets/render/LatexRiskNormalizer.ets` |
| Markdown 分块 | `entry/src/main/ets/shared/molecules/MarkdownRenderer.ets` |
| 公式渲染 | `entry/src/main/ets/shared/atoms/MathTextRenderer.ets` |
| 流式增量渲染 | [spec 021](../specs/021-chat-streaming-incremental-rendering.md) |
| 截断与流式事件 | `StreamEvent`（`CONTEXT.md`）、`LlmClient` |

Hypium 测试在 `entry/src/ohosTest/ets/generated-knowledge-tests/common/ContentProtocol.test.ets` 与 `LatexRiskNormalizer.test.ets`；协议相关的静态断言在 `scripts/arkts-lint/tests/`。协议变更必须同时更新本文件、`ContentProtocol` 与测试。
