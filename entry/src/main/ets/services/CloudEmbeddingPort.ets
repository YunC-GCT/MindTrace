/**
 * CloudEmbeddingPort.ets — OpenAI 兼容 /embeddings 的向量端口
 *
 * 路径: entry/src/main/ets/services/CloudEmbeddingPort.ets
 * 职责: 用当前服务厂商的 baseUrl 与 API Key 调 `/embeddings`，把文本批量转成稠密向量。
 *       协议按 OpenAI 兼容格式：请求 {model, input[]}，响应 {data:[{index, embedding[]}]}。
 * 依赖: @kit.NetworkKit（LlmClient 已在 common 使用，进程边界允许）、common LlmConfig。
 *
 * 约束:
 *   - 失败必须抛出：写入侧据此保留原有向量、不落半截数据；
 *   - 分批请求，单批 16 条，避免长笔记一次超时；
 *   - 维度由首次响应确定，写库时按实际长度记录。
 */
import { http } from '@kit.NetworkKit';
import { CLOUD_EMBEDDING_PROVIDER, cloudEmbeddingModelId, embeddingQueryPrefix, LlmConfig } from 'common';
import type { EmbeddingPort, EmbeddingVector } from 'common';

const BATCH_SIZE: number = 16;
const CONNECT_TIMEOUT_MS: number = 5000;
const READ_TIMEOUT_MS: number = 30000;
// 本地服务没启动时不要每次都等连接超时：失败后静默 60 秒，检索直接走 FTS。
const COOLDOWN_MS: number = 60000;

interface EmbeddingRequestBody {
  model: string;
  input: string[];
}

interface ParsedItem {
  index: number;
  values: number[];
}

export class CloudEmbeddingPort implements EmbeddingPort {
  provider: string = CLOUD_EMBEDDING_PROVIDER;
  model: string = '';
  dimension: number = 0;
  private readonly modelName: string;
  private static cooldownUntil: number = 0;

  constructor(modelName: string) {
    this.modelName = modelName.trim();
    this.model = cloudEmbeddingModelId(this.modelName);
  }

  async isAvailable(): Promise<boolean> {
    const config: LlmConfig = LlmConfig.getInstance();
    // 密钥可选：本地自建服务通常不带鉴权。
    return this.modelName.length > 0 && config.getEmbeddingEndpoint().length > 0;
  }

  async embed(texts: string[]): Promise<EmbeddingVector[]> {
    const vectors: EmbeddingVector[] = [];
    for (let offset = 0; offset < texts.length; offset += BATCH_SIZE) {
      const end: number = offset + BATCH_SIZE < texts.length ? offset + BATCH_SIZE : texts.length;
      const batch: string[] = texts.slice(offset, end);
      const batchVectors: EmbeddingVector[] = await this.requestBatch(batch);
      for (let i = 0; i < batchVectors.length; i += 1) {
        vectors.push(batchVectors[i]);
      }
    }
    return vectors;
  }

  /** 查询向量：BGE 中文检索模型要求查询加指令前缀，文档不加。 */
  async embedQuery(text: string): Promise<EmbeddingVector> {
    const prefix: string = embeddingQueryPrefix(this.modelName);
    const vectors: EmbeddingVector[] = await this.embed([prefix + text]);
    if (vectors.length === 0) {
      throw new Error('embedding: empty query vector');
    }
    return vectors[0];
  }

  private async requestBatch(texts: string[]): Promise<EmbeddingVector[]> {
    if (texts.length === 0) {
      const empty: EmbeddingVector[] = [];
      return empty;
    }
    if (Date.now() < CloudEmbeddingPort.cooldownUntil) {
      throw new Error('embedding: service unavailable (cooling down)');
    }
    const config: LlmConfig = LlmConfig.getInstance();
    const apiKey: string = config.getEmbeddingApiKey();
    const endpoint: string = config.getEmbeddingEndpoint();
    if (endpoint.length === 0) {
      throw new Error('embedding: endpoint missing');
    }
    const url: string = CloudEmbeddingPort.buildUrl(endpoint);
    const header: Record<string, string> = { 'Content-Type': 'application/json' };
    if (apiKey.length > 0) {
      header['Authorization'] = 'Bearer ' + apiKey;
    }
    const body: EmbeddingRequestBody = { model: this.modelName, input: texts };
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
      CloudEmbeddingPort.cooldownUntil = Date.now() + COOLDOWN_MS;
      throw new Error('embedding network: ' + (error as Error).message);
    }
    request.destroy();
    CloudEmbeddingPort.cooldownUntil = 0;
    if (response.responseCode !== 200) {
      throw new Error('embedding http ' + response.responseCode.toString()
        + ': ' + String(response.result).substring(0, 200));
    }
    return this.parseResponse(String(response.result), texts.length);
  }

  /** baseUrl 可能带尾斜杠（智谱 v4/），拼完保证只有一个分隔符。 */
  private static buildUrl(endpoint: string): string {
    let base: string = endpoint.trim();
    while (base.length > 0 && base.charAt(base.length - 1) === '/') {
      base = base.substring(0, base.length - 1);
    }
    return base + '/embeddings';
  }

  private parseResponse(text: string, expected: number): EmbeddingVector[] {
    const items: ParsedItem[] = [];
    try {
      const parsed: Object = JSON.parse(text) as Object;
      const record: Record<string, Object> = parsed as Record<string, Object>;
      const dataValue: Object | undefined = record['data'];
      if (dataValue === undefined || !Array.isArray(dataValue)) {
        throw new Error('embedding: response has no data array');
      }
      const rows: Object[] = dataValue as Object[];
      for (let i = 0; i < rows.length; i += 1) {
        const row: Record<string, Object> = rows[i] as Record<string, Object>;
        const values: number[] = CloudEmbeddingPort.readVector(row['embedding']);
        if (values.length === 0) {
          continue;
        }
        const indexValue: Object | undefined = row['index'];
        const index: number = indexValue === undefined ? i : Number(indexValue);
        items.push({ index: index, values: values });
      }
    } catch (error) {
      throw new Error(error instanceof Error ? error.message : 'embedding: invalid response');
    }
    if (items.length !== expected) {
      throw new Error('embedding: expected ' + expected.toString()
        + ' vectors, got ' + items.length.toString());
    }
    items.sort((left: ParsedItem, right: ParsedItem): number => left.index - right.index);
    const vectors: EmbeddingVector[] = [];
    for (let i = 0; i < items.length; i += 1) {
      const values: number[] = items[i].values;
      if (this.dimension === 0) {
        this.dimension = values.length;
      }
      vectors.push({
        provider: this.provider,
        model: this.model,
        dimension: values.length,
        values: values,
      });
    }
    return vectors;
  }

  private static readVector(value: Object | undefined): number[] {
    const values: number[] = [];
    if (value === undefined || value === null || !Array.isArray(value)) {
      return values;
    }
    const items: Object[] = value as Object[];
    for (let i = 0; i < items.length; i += 1) {
      const n: number = Number(items[i]);
      if (Number.isFinite(n)) {
        values.push(n);
      }
    }
    return values;
  }
}
