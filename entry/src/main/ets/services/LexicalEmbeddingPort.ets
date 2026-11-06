/**
 * LexicalEmbeddingPort.ets — 确定性词面向量的端口实现
 *
 * 路径: entry/src/main/ets/services/LexicalEmbeddingPort.ets
 * 职责: 用 common 的纯函数实现 EmbeddingPort；不依赖任何 Kit，
 *       因此主进程与 A2A 扩展进程都能求值。
 * 依赖: common（LexicalEmbedding）。
 *
 * 约束: 生成的向量带 model 标记；检索侧只比较同 model 的向量，
 *       未来接入系统/云端稠密模型时按 model 区分、旧向量自动视为待重建。
 */
import {
  buildLexicalVector,
  EmbeddingPort,
  EmbeddingVector,
  LEXICAL_DIMENSION,
  LEXICAL_EMBEDDING_MODEL,
  LEXICAL_EMBEDDING_PROVIDER,
} from 'common';

export class LexicalEmbeddingPort implements EmbeddingPort {
  readonly provider: string = LEXICAL_EMBEDDING_PROVIDER;
  readonly model: string = LEXICAL_EMBEDDING_MODEL;
  readonly dimension: number = LEXICAL_DIMENSION;

  async isAvailable(): Promise<boolean> {
    return true;
  }

  async embed(texts: string[]): Promise<EmbeddingVector[]> {
    const vectors: EmbeddingVector[] = [];
    for (let i = 0; i < texts.length; i += 1) {
      vectors.push({
        provider: this.provider,
        model: this.model,
        dimension: this.dimension,
        values: buildLexicalVector(texts[i]),
      });
    }
    return vectors;
  }

  async embedQuery(text: string): Promise<EmbeddingVector> {
    return {
      provider: this.provider,
      model: this.model,
      dimension: this.dimension,
      values: buildLexicalVector(text),
    };
  }
}
