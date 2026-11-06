/**
 * EmbeddingRuntime.ets — 当前生效的向量端口选择
 *
 * 路径: entry/src/main/ets/services/EmbeddingRuntime.ets
 * 职责: 配置了 embedding 模型就走云端稠密向量，否则回落到确定性词面向量。
 *       写库与检索都从这里取端口，保证两边用的是同一个模型标识。
 * 依赖: common LlmConfig、./LexicalEmbeddingPort、./CloudEmbeddingPort。
 *
 * 约束: 端口选择只看 LlmConfig 的内存缓存（启动时已加载），因此可在检索路径同步调用；
 *       配置变更后由设置页调用 refresh() 丢弃缓存的云端端口。
 */
import { LlmConfig } from 'common';
import type { EmbeddingPort } from 'common';
import { CloudEmbeddingPort } from './CloudEmbeddingPort';
import { LexicalEmbeddingPort } from './LexicalEmbeddingPort';

export class EmbeddingRuntime {
  private static readonly lexical: LexicalEmbeddingPort = new LexicalEmbeddingPort();
  private static cloud: CloudEmbeddingPort | null = null;
  private static cloudModelName: string = '';

  /** 当前端口：三项配置齐全走云端，否则词面。 */
  static active(): EmbeddingPort {
    if (!EmbeddingRuntime.isDense()) {
      return EmbeddingRuntime.lexical;
    }
    const modelName: string = LlmConfig.getInstance().getEmbeddingModel();
    if (EmbeddingRuntime.cloud === null || EmbeddingRuntime.cloudModelName !== modelName) {
      EmbeddingRuntime.cloud = new CloudEmbeddingPort(modelName);
      EmbeddingRuntime.cloudModelName = modelName;
    }
    return EmbeddingRuntime.cloud;
  }

  /** 写库与检索用的模型标识；只有同标识的向量才可互相比较。 */
  static activeModel(): string {
    return EmbeddingRuntime.active().model;
  }

  /** 稠密向量才参与检索融合。模型与端点必须齐全；密钥可选（本地服务通常不带鉴权）。 */
  static isDense(): boolean {
    const config: LlmConfig = LlmConfig.getInstance();
    return config.getEmbeddingModel().length > 0
      && config.getEmbeddingEndpoint().length > 0;
  }

  /** 设置页改完 embedding 配置后调用。 */
  static refresh(): void {
    EmbeddingRuntime.cloud = null;
    EmbeddingRuntime.cloudModelName = '';
  }
}
