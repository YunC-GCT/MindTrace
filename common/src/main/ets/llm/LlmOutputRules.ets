import type { ChatMessage } from './LlmTypes';

export const JSON_ONLY_RULES: string =
  'Return one strict JSON object only. Do not wrap it in markdown fences. Do not add explanations.';

export const LATEX_GENERATION_RULES: string =
  'MM-MD-v1 公式输出规则: ' +
    '1. 句子中的短公式只能使用 $...$, 例如 $x$ 或 $n \\neq -1$. ' +
    '2. 核心公式、长公式和多步推导必须使用独立 $$ 块, 开始和结束的 $$ 必须各自单独占一行且前后留空行. ' +
    '3. 禁止输出没有定界符的裸 LaTeX 命令行, 例如 \\int ... 或 \\frac .... ' +
    '4. $$ 块内部禁止再出现 $, 条件应写在同一数学环境中, 例如 \\quad (n \\neq -1). ' +
    '5. 标题、标签、字段 key 和字段 label 中禁止公式. ' +
    '6. 列表项只允许短行内公式, 长公式必须移到列表外的独立 $$ 块. ' +
    '7. 多行推导使用 \\begin{aligned}...\\end{aligned}, 禁止 align/align* 和自定义宏. ' +
    '8. 禁止原始 HTML、Markdown 表格和嵌套列表. ' +
    '9. 公式不完整或 OCR 字符不确定时保留原文并标注待确认, 不得补造数学内容. ' +
    '10. JSON 字符串中的每个 LaTeX 反斜杠必须写成双反斜杠 \\\\, 解析后的字段值才能保留单反斜杠. ' +
    '11. 禁止输出 \\begin{enumerate}、\\end{enumerate}、\\begin{itemize}、\\end{itemize} 或 \\item; 列表必须使用 Markdown 的 - item 或 1. item.';

export function buildGuardRetryMessage(label: string, issues: string[]): ChatMessage {
  return {
    role: 'user',
    content: 'The previous ' + label + ' output failed local validation. ' +
      'Continue answering the original user request. Regenerate the answer as a single strict JSON object only. ' +
      'Fix these issues, output only the corrected final answer, and do not output a format diagnosis, ' +
      'validation report, or other meta-commentary:\n- ' +
      issues.join('\n- '),
  };
}
