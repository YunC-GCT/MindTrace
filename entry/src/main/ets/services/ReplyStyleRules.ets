/**
 * ReplyStyleRules.ets — 回复通道的数学排版规则（UI 默认 markdown / A2A 纯文本）
 *
 * 路径: entry/src/main/ets/services/ReplyStyleRules.ets
 * 职责: 为回复链路提供显式 style：markdown 返回现有 IntentClassifier 第 12–16 条公式规则原文；
 *       plain_text_math 返回禁用 $/LaTeX 的纯文本数学规则。
 * 依赖: 无（纯函数，不 import 任何 Kit）
 *
 * 数据流:
 *   IntentClassifier.buildReplyMessages(context, style) → buildMathStyleRules(style) → system prompt
 *
 * 为什么需要两个 style（#234 真机实证）:
 *   App 内聊天能完整渲染公式，但小艺 A2A 气泡会把 $...$ / LaTeX 整段吞掉（只留时间戳）；
 *   同一份快照原文在 App 内可显示，说明损失在小艺渲染层。A2A 通道改用纯文本数学，
 *   App 内聊天继续用 markdown，逐字节不变。
 */
export type ReplyStyle = 'markdown' | 'plain_text_math';

/**
 * 现有 IntentClassifier 第 12–16 条公式规则原文（原样搬出，内容不许改）。
 * 末尾保留 \n，供后面直接拼接 LATEX_GENERATION_RULES，保持 UI 提示词逐字节不变。
 */
const MARKDOWN_MATH_RULES: string =
  '12. 短公式必须融入文字并用单个美元符定界，例如 $a>0$；不要输出裸 \\mu、\\sigma、\\Phi、\\operatorname，也不要使用单独的 [ ] 充当公式边界。\n'
  + '13. 重要公式、长公式和多行推导使用展示公式，起止 $$ 必须各占独立一行；不要写成 $$公式$$，不要在 $$ 内嵌套单个美元符，也不要用 Markdown 代码块包公式。\n'
  + '14. 多行公式只能在独立的 $$ 块内使用 \\begin{aligned}...\\end{aligned}；不要使用 align 或 align* 环境。\n'
  + '15. 列表项内只允许短行内公式；长公式和 $$ 定界符必须移到列表外，绝不能写成“1. $$”“2. 公式”“3. $$”。如需分步推导，用“第 1 步：”文字段落，再另起独立 $$ 块。\n\n'
  + '16. 如果发现格式问题，请在内部修正后继续回答原问题；禁止输出“格式问题”“校验失败”“上一条回答存在问题”等格式诊断或元评论，只输出最终答案。\n';

/**
 * A2A 纯文本数学规则：小艺渲染层不认 $...$ / LaTeX，只有普通文本与 Unicode 能完整显示。
 * 明确禁止包裹符与占位符，同时要求数学含义完整（不能以“无法显示”为由省略）。
 */
const PLAIN_TEXT_MATH_RULES: string =
  '12. 数学表达一律使用纯文本：禁止使用美元符号 $ 或 $$ 定界，禁止输出 \\命令（如 \\frac、\\sqrt、\\mu）和 \\begin{}...\\end{} 环境，也不要用 Markdown 代码块包数学。\n'
  + '13. 数学用 Unicode 与普通文本表达：根号写成 √a，条件写成 a ≥ 0，平方写成 x²，分式写成 a/b，乘除写成 × 和 ÷，圆周率写成 π；不得改写或省略数学含义。\n'
  + '14. 不得因为排版受限而省略公式、替换成占位符或写成“无法显示”；必须用纯文本把同样的数学内容完整表达出来。\n'
  + '15. 不要使用 Mermaid、原始 HTML 或 Markdown 表格；分步推导用“第 1 步：”“第 2 步：”这样的文字段落，每步单独成段。\n'
  + '16. 如果发现格式问题，请在内部修正后继续回答原问题；禁止输出“格式问题”“校验失败”“上一条回答存在问题”等格式诊断或元评论，只输出最终答案。';

/** 按通道返回数学规则：UI（markdown）保持原公式规则，A2A（plain_text_math）只给纯文本数学。 */
export function buildMathStyleRules(style: ReplyStyle): string {
  if (style === 'plain_text_math') {
    return PLAIN_TEXT_MATH_RULES;
  }
  return MARKDOWN_MATH_RULES;
}
