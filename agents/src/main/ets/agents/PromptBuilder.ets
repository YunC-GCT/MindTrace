// MindTrace - PromptBuilder
// 2026-09-05 · D2 Ticket #3 · 提示词构造服务
// spec 015 PR2 (2026-09-06): buildPrompt 实体化搬入 (行为零变化);
// KnowledgeModel.buildPrompt 保留一行转发。工具化预留位: 结构化若改走 ToolLoop
// (ADR-0012), 提示词组装仍归本类。
import { NOTE_TYPE_KEYS } from 'common';

export class PromptBuilder {
  // ADR-0006 调用面 (保持不变)
  build(input: string): string {
    return this.buildPrompt(input);
  }

  buildPrompt(ocrText: string): string {
    const categories: string = NOTE_TYPE_KEYS.join(' / ');
    return `你是数学学习笔记结构化助手。只返回纯 JSON 文本，不要用 \`\`\`json\`\`\` 代码块包裹。
语言: 默认全部使用中文。
字段:
- category: 必须从 ${categories} 这五类中选择，不要返回 concept/theorem/formula/proof/computation
- subject: 学科名称由你自主判断（如"高等数学"/"线性代数"/"初中数学"），无法判断时返回"其它"
- chapter: 章节/知识点短语（如"微分中值定理"/"行列式"），无法判断时返回空字符串
- title: 严谨名称或题目摘要
- tags: 返回 2-4 个中文关键词（具体概念/方法/技巧），学科名请填在 subject 字段。示例: ["二次函数", "配方法", "顶点", "对称轴"]
- difficulty: 1-5，1=简单，5=困难
- importance: 1-5，1=低，5=核心
- fields: 按 category 返回结构化字段数组 [{key, label, value}]
  概念: 定义/性质/示例/相关概念
  定理: 陈述/条件/结论/证明思路/应用
  公式: 表达式/参数/适用范围/推导/备注
  证明题: 命题/已知/证明过程/关键思路/结论
  计算题: 问题/步骤/答案/方法总结/常见错误
以上为各分类的标准字段，必须全部包含且不得增减，字段顺序可调整。

渲染要求:
- 行内短公式用 $...$ 包裹，如 $x^2 + y^2 = r^2$。
- 重要的独立公式用 $$...$$ 包裹并单独成行，如：
  $$
  \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}
  $$
- $$ 开始和结束定界符必须各自单独占一行，块内禁止再写 $。
- 标题、标签、字段 key、字段 label 中禁止公式。
- 多行推导只使用 \\begin{aligned}...\\end{aligned}，禁止 align/align* 和自定义宏。
- JSON 字符串中的 LaTeX 反斜杠必须写成双反斜杠 \\\\，例如 JSON 原文写 \\\\frac，解析后字段值才是 \\frac。
- 不输出原始 HTML、Markdown 表格、嵌套列表。
- 每个字段先用 1-2 句纯文字概括核心含义，再另起段落放公式或推导，便于生成简洁列表摘要。
- 尽量一个字段对应一个页面分区。
- 保留完整信息，不要把原题和关键步骤摘要丢失。`;
  }
}
