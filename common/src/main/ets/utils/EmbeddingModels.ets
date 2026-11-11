/**
 * EmbeddingModels.ets — embedding 模型标识的命名规则（纯函数，无 IO）
 *
 * 路径: common/src/main/ets/utils/EmbeddingModels.ets
 * 职责: 把「用户配置的 embedding 模型名」映射成 rag_embedding.model 里存的标识。
 *       标识带来源前缀，检索侧据此只比较同来源、同模型的向量——
 *       词面向量与云端稠密向量混算会得到没有意义的分。
 * 依赖: 无。
 */

export const CLOUD_EMBEDDING_PROVIDER: string = 'cloud';
export const CLOUD_EMBEDDING_MODEL_PREFIX: string = 'cloud:';

/** 空模型名返回空串（= 未启用）；已带前缀时幂等。 */
export function cloudEmbeddingModelId(model: string): string {
  const trimmed: string = model.trim();
  if (trimmed.length === 0) {
    return '';
  }
  if (trimmed.startsWith(CLOUD_EMBEDDING_MODEL_PREFIX)) {
    return trimmed;
  }
  return CLOUD_EMBEDDING_MODEL_PREFIX + trimmed;
}

export function isCloudEmbeddingModel(id: string): boolean {
  return id.startsWith(CLOUD_EMBEDDING_MODEL_PREFIX);
}

export const BGE_ZH_QUERY_PREFIX: string = '为这个句子生成表示以用于检索相关文章：';

/**
 * BGE 中文检索模型（bge-*-zh-*）做非对称检索时，查询要加指令前缀、文档不加。
 * bge-m3 是例外——它不要求指令，所以不能按 bge 前缀一刀切。
 * 其它模型返回空串。
 */
export function embeddingQueryPrefix(model: string): string {
  const lower: string = model.trim().toLowerCase();
  if (lower.length === 0 || lower.indexOf('bge') < 0) {
    return '';
  }
  if (lower.indexOf('m3') >= 0) {
    return '';
  }
  return lower.indexOf('zh') >= 0 ? BGE_ZH_QUERY_PREFIX : '';
}
