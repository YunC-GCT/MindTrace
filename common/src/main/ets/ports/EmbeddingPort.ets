/**
 * EmbeddingPort.ets — 文本向量化端口
 *
 * 路径: common/src/main/ets/ports/EmbeddingPort.ets
 * 职责: 让检索/判重链路在不知道向量从哪来的前提下使用向量；
 *       实现留在 entry（稀疏词面向量、未来系统/云端稠密模型），由组合根注入。
 * 依赖: 无。
 *
 * 约束: 端口本身不含 Kit、不含 IO，可在任何进程（含 A2A 扩展进程）求值。
 *       不同实现的向量不可混用——调用方必须按 `model` 过滤，只比较同模型向量。
 */
export interface EmbeddingVector {
  provider: string;
  model: string;
  dimension: number;
  values: number[];
}

export interface EmbeddingPort {
  readonly provider: string;
  readonly model: string;
  readonly dimension: number;
  isAvailable(): Promise<boolean>;
  /** 文档向量：写入笔记 chunk 时用。 */
  embed(texts: string[]): Promise<EmbeddingVector[]>;
  /** 查询向量：与文档向量分开，便于注入检索指令（BGE 中文模型需要，文档不加）。 */
  embedQuery(text: string): Promise<EmbeddingVector>;
}
