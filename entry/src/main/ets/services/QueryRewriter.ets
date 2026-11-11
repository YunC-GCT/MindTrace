/**
 * QueryRewriter.ets — 检索查询的 LLM 改写（仅在向量分不开时调用）
 *
 * 路径: entry/src/main/ets/services/QueryRewriter.ets
 * 职责: 把用户的口语化问题改写成一组检索关键词，补上它没说出口的术语。
 *       例如「存在一点其切线平行于两端连线」→「拉格朗日中值定理 罗尔定理 切线 平行」。
 * 依赖: common LlmClient / LlmConfig。
 *
 * 约束:
 *   - 每次调用 2-3 秒 + 计费，只在向量头部确实分不开时才调（见 RagRetrievalService）；
 *   - 超时 1.8s 是为了让 A2A 的 2.5s 证据预算还留得出余量；
 *   - 失败静默返回空数组并在 60 秒内不再重试，改写是增强不是依赖。
 */
import { LlmClient, LlmConfig } from 'common';
import type { ChatMessage, LlmCallResult } from 'common';

const REWRITE_TIMEOUT_MS: number = 1800;
const COOLDOWN_MS: number = 60000;
const MAX_KEYWORDS: number = 8;
const MIN_KEYWORD_LENGTH: number = 2;

const SYSTEM_PROMPT: string = '你是数学检索助手。把用户的问题改写成适合全文检索的中文关键词：'
  + '补上问题里没说出口的术语、定理名和同义说法。'
  + '只输出关键词，用空格分隔，最多 8 个，不要解释，不要标点。';

export class QueryRewriter {
  private static cooldownUntil: number = 0;

  /** 返回改写出的关键词；不可用时返回空数组。 */
  static async rewrite(query: string): Promise<string[]> {
    const trimmed: string = query.trim();
    if (trimmed.length === 0 || Date.now() < QueryRewriter.cooldownUntil) {
      return [];
    }
    const config: LlmConfig = LlmConfig.getInstance();
    const configured: boolean = await config.isConfigured();
    if (!configured) {
      return [];
    }
    const messages: ChatMessage[] = [
      { role: 'system', content: SYSTEM_PROMPT },
      { role: 'user', content: trimmed },
    ];
    try {
      const result: LlmCallResult = await new LlmClient().call({
        messages: messages,
        temperature: 0,
        maxTokens: 64,
        timeoutMs: REWRITE_TIMEOUT_MS,
        enableThinking: false,
      });
      return QueryRewriter.parse(result.text !== undefined ? result.text : '');
    } catch (e) {
      QueryRewriter.cooldownUntil = Date.now() + COOLDOWN_MS;
      console.warn('query rewrite failed: ' + (e as Error).message);
      return [];
    }
  }

  /** 关键词清洗：去掉标点与短词，去重，截断到上限。 */
  private static parse(text: string): string[] {
    const raw: string[] = text.replace(/[，。、；：,.!?！？\n\r\t]/g, ' ').split(' ');
    const keywords: string[] = [];
    for (let i = 0; i < raw.length; i += 1) {
      const word: string = raw[i].trim();
      if (word.length < MIN_KEYWORD_LENGTH || keywords.indexOf(word) >= 0) {
        continue;
      }
      keywords.push(word);
      if (keywords.length >= MAX_KEYWORDS) {
        break;
      }
    }
    return keywords;
  }
}
