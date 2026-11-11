/**
 * LlmNoteSimilarityJudge.ets — 灰区查重的模型仲裁实现
 *
 * 路径: entry/src/main/ets/services/LlmNoteSimilarityJudge.ets
 * 职责: 两条笔记的确定性相似度落在灰区时，让聊天模型判断二者关系：
 *       同一道题且无新内容（same）、同一主题但有补充（supplement）、不同主题（different）。
 *       是拦截还是放行由模型给出的结论决定，写服务只执行。
 * 依赖: common LlmClient/LlmConfig/markdownToPlainText。
 *
 * 约束: 超时/未配置/解析失败一律返回 different（放行）——
 *       宁可多存一条，也不要误删/误跳用户的新内容。
 */
import { ChatMessage, LlmClient, LlmConfig, markdownToPlainText } from 'common';
import type { NoteSimilarityJudgePort, NoteSimilarityVerdict } from 'common';

const EXCERPT_LIMIT: number = 320;
const JUDGE_TIMEOUT_MS: number = 8000;

const SYSTEM_PROMPT: string = '你是数学笔记查重助手。比较两条笔记，判断它们的关系，只输出一个词：'
  + 'SAME（讲同一道题或同一知识点，且新笔记没有实质新内容）、'
  + 'SUPPLEMENT（同一主题，但新笔记包含已有笔记没有的内容）、'
  + 'DIFFERENT（不同主题）。换一种说法、变量名不同，仍算同一题。';

export class LlmNoteSimilarityJudge implements NoteSimilarityJudgePort {
  async judge(leftTitle: string, leftContent: string,
    rightTitle: string, rightContent: string): Promise<NoteSimilarityVerdict> {
    try {
      if (!(await LlmConfig.getInstance().isConfigured())) {
        return LlmNoteSimilarityJudge.different('judge-unavailable');
      }
      const messages: ChatMessage[] = [
        { role: 'system', content: SYSTEM_PROMPT },
        {
          role: 'user',
          content: '笔记A标题：' + leftTitle + '\n笔记A摘录：' + LlmNoteSimilarityJudge.clip(leftContent)
            + '\n\n笔记B标题：' + rightTitle + '\n笔记B摘录：' + LlmNoteSimilarityJudge.clip(rightContent),
        },
      ];
      const result = await new LlmClient().call({
        messages: messages,
        maxTokens: 8,
        temperature: 0,
        timeoutMs: JUDGE_TIMEOUT_MS,
        enableThinking: false,
      });
      const text: string = (result.text !== undefined ? result.text : '').trim().toUpperCase();
      // 先判 SUPPLEMENT：它的文本里不含 SAME，但顺序写错容易误判，保持显式。
      if (text.indexOf('SUPPLEMENT') >= 0) {
        return { kind: 'supplement', reason: 'model-supplement' };
      }
      if (text.indexOf('SAME') >= 0) {
        return { kind: 'same', reason: 'model-same' };
      }
      return LlmNoteSimilarityJudge.different('model-different');
    } catch (e) {
      return LlmNoteSimilarityJudge.different('judge-failed');
    }
  }

  private static different(reason: string): NoteSimilarityVerdict {
    return { kind: 'different', reason: reason };
  }

  private static clip(content: string): string {
    const plain: string = markdownToPlainText(content).replace(/\s+/g, ' ');
    return plain.length > EXCERPT_LIMIT ? plain.substring(0, EXCERPT_LIMIT) : plain;
  }
}
