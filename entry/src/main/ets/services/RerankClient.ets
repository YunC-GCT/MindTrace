/**
 * RerankClient.ets — 候选文档的交叉编码器重排
 *
 * 路径: entry/src/main/ets/services/RerankClient.ets
 * 职责: 向量召回后，把候选文档与查询一起送 `/v1/rerank` 重新打分。
 *       向量的余弦分在同领域语料上挤得很窄（实测 25 条笔记只占 0.372–0.515），
 *       单靠余弦无法把第 9 名和第 1 名分开；交叉编码器直接看 query-doc 对，能分开。
 * 依赖: @kit.NetworkKit、common LlmConfig（复用 embedding 的端点与密钥）。
 *
 * 约束:
 *   - 任何失败返回空数组，调用方保持原有余弦顺序（重排是增强，不是依赖）；
 *   - 失败后静默 60 秒，避免本地服务没开时每题都等超时；
 *   - 文档截断到 240 字：reranker 输入上限 512 token，长文对排序没有额外信息。
 */
import { http } from '@kit.NetworkKit';
import { LlmConfig } from 'common';

const CONNECT_TIMEOUT_MS: number = 5000;
const READ_TIMEOUT_MS: number = 20000;
const COOLDOWN_MS: number = 60000;
const MAX_DOC_CHARS: number = 240;

interface RerankBody {
  query: string;
  documents: string[];
}

interface ParsedScore {
  index: number;
  score: number;
}

export class RerankClient {
  private static cooldownUntil: number = 0;

  /** 返回与 documents 同序的相关性分数；不可用时返回空数组。 */
  static async score(query: string, documents: string[]): Promise<number[]> {
    if (documents.length === 0) {
      return [];
    }
    if (Date.now() < RerankClient.cooldownUntil) {
      return [];
    }
    const config: LlmConfig = LlmConfig.getInstance();
    const endpoint: string = config.getEmbeddingEndpoint();
    if (endpoint.length === 0) {
      return [];
    }
    const url: string = RerankClient.buildUrl(endpoint);
    const header: Record<string, string> = { 'Content-Type': 'application/json' };
    const apiKey: string = config.getEmbeddingApiKey();
    if (apiKey.length > 0) {
      header['Authorization'] = 'Bearer ' + apiKey;
    }
    const body: RerankBody = { query: query, documents: documents };
    const request: http.HttpRequest = http.createHttp();
    let response: http.HttpResponse;
    try {
      response = await request.request(url, {
        method: http.RequestMethod.POST,
        header: header,
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: CONNECT_TIMEOUT_MS,
        readTimeout: READ_TIMEOUT_MS,
      });
    } catch (error) {
      request.destroy();
      RerankClient.cooldownUntil = Date.now() + COOLDOWN_MS;
      console.warn('rerank network failed: ' + (error as Error).message);
      return [];
    }
    request.destroy();
    if (response.responseCode !== 200) {
      RerankClient.cooldownUntil = Date.now() + COOLDOWN_MS;
      console.warn('rerank http ' + response.responseCode.toString());
      return [];
    }
    RerankClient.cooldownUntil = 0;
    return RerankClient.parse(String(response.result), documents.length);
  }

  /** endpoint 形如 http://host:8001/v1，服务端路由是 /v1/rerank。 */
  private static buildUrl(endpoint: string): string {
    let base: string = endpoint.trim();
    while (base.length > 0 && base.charAt(base.length - 1) === '/') {
      base = base.substring(0, base.length - 1);
    }
    return base + '/rerank';
  }

  private static parse(text: string, expected: number): number[] {
    const scores: number[] = [];
    for (let i = 0; i < expected; i += 1) {
      scores.push(Number.NEGATIVE_INFINITY);
    }
    try {
      const parsed: Object = JSON.parse(text) as Object;
      const record: Record<string, Object> = parsed as Record<string, Object>;
      const resultsValue: Object | undefined = record['results'];
      if (resultsValue === undefined || !Array.isArray(resultsValue)) {
        return [];
      }
      const items: Object[] = resultsValue as Object[];
      for (let i = 0; i < items.length; i += 1) {
        const item: Record<string, Object> = items[i] as Record<string, Object>;
        const index: number = Number(item['index'] ?? -1);
        const score: number = Number(item['relevance_score'] ?? Number.NEGATIVE_INFINITY);
        if (index >= 0 && index < expected) {
          scores[index] = score;
        }
      }
    } catch (error) {
      return [];
    }
    return scores;
  }

  /** 文档长度收敛到 reranker 的输入上限内。 */
  static trimDocument(text: string): string {
    return text.length > MAX_DOC_CHARS ? text.substring(0, MAX_DOC_CHARS) : text;
  }
}
