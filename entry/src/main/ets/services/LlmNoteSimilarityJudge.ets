/**
 * LlmNoteSimilarityJudge.ets — 灰区查重的模型仲裁实现
 *
 * 路径: entry/src/main/ets/services/LlmNoteSimilarityJudge.ets
 * 职责: 两条笔记的确定性相似度落在灰区时，让聊天模型判断是否同一道题。
 *       超时/未配置/解析失败一律返回 false（宁可不判重，也不误删/误跳）。
 * 依赖: common LlmClient/LlmConfig/markdownToPlainText。
 */
import { ChatMessage, LlmClient, LlmConfig, markdownToPlainText } from 'common';
import type { NoteSimilarityJudgePort } from 'common';

const EXCERPT_LIMIT: number = 320;
const JUDGE_TIMEOUT_MS: number = 8000;

export class LlmNoteSimilarityJudge implements NoteSimilarityJudgePort {
  async isSameNote(leftTitle: string, leftContent: string,
    rightTitle: string, rightContent: string): Promise<boolean> {
    try {
      if (!(await LlmConfig.getInstance().isConfigured())) {
        return false;
      }
      const messages: ChatMessage[] = [
        {
          role: 'system',
          content: '你是数学笔记查重助手。判断两条笔记是否在讲同一道题或同一个知识点，'
            + '换一种说法、变量名不同也算同一题。只输出 YES 或 NO。',
        },
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
      return text.indexOf('YES') === 0;
    } catch (e) {
      return false;
    }
  }

  private static clip(content: string): string {
    const plain: string = markdownToPlainText(content).replace(/\s+/g, ' ');
    return plain.length > EXCERPT_LIMIT ? plain.substring(0, EXCERPT_LIMIT) : plain;
  }
}
