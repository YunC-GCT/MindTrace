// ============================================================================
//  capability/imagesearch/ImageSearchIndex.ets — 文搜图能力端口
//  ----------------------------------------------------------------------------
//  路径: common/src/main/ets/capability/imagesearch/ImageSearchIndex.ets
//  职责: 定义「图片入库 + 自然语言检索」契约 + 进程内注册表, 让 L2/L3 只依赖端口,
//        不直接依赖 Core Vision Kit 的 textSearchImage (spec 033 R2)。
//  依赖: 无 — 本文件零 Kit 依赖; 实现由 entry 组合根注入。
//  数据流: EntryAbility.onCreate → ImageSearchIndexRegistry.install(impl)
//          → AiService.capture 落库后 insert(localPath)
//          → 检索方 ImageSearchIndexRegistry.require().search(query, topK)
//  约束: 本文件不得 import 任何 Kit; 实现文件放在 UI 进程 (entry)。
//
//  与 SDK 的对应关系 (API 26, @hms.ai.vision.textSearchImage):
//    init() → insertImage(imagePath, scope) → search(query, scope, topKey?)
//    → deleteImage(imagePath, scope) → clearData() → release()
//  similarity 取值 [-1, 1], 越大越相似 (SDK d.ts 定义, 不是概率)。
// ============================================================================

// 一条检索命中: 沙箱内图片绝对路径 + 相似度。
export interface ImageSearchHit {
  imagePath: string;
  similarity: number;
}

// 文搜图能力端口: 图片路径进, 命中列表出。实现负责全部 Kit 细节与 scope 管理。
export interface ImageSearchIndex {
  isAvailable(): boolean;
  insert(imagePath: string): Promise<boolean>;
  search(query: string, topK?: number): Promise<ImageSearchHit[]>;
  remove(imagePath: string): Promise<boolean>;
  clear(): Promise<boolean>;
}

// 进程内注册表: 组合根 (EntryAbility.onCreate) 安装唯一实现, 消费方按契约取用。
export class ImageSearchIndexRegistry {
  private static impl: ImageSearchIndex | null = null;

  static install(impl: ImageSearchIndex): void {
    ImageSearchIndexRegistry.impl = impl;
  }

  static isInstalled(): boolean {
    return ImageSearchIndexRegistry.impl !== null;
  }

  static require(): ImageSearchIndex {
    const impl: ImageSearchIndex | null = ImageSearchIndexRegistry.impl;
    if (impl === null) {
      throw new Error('文搜图能力未初始化（ImageSearchIndexRegistry 未安装）');
    }
    return impl;
  }
}
