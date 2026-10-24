// ============================================================================
//  capability/ocr/OcrRecognizer.ets — OCR 能力端口 (issue #227 / spec 033)
//  ----------------------------------------------------------------------------
//  路径: common/src/main/ets/capability/ocr/OcrRecognizer.ets
//  职责: 定义 OCR 识别契约 + 进程内注册表, 让 L2 编排 (agents) 只依赖能力端口,
//        不再直接依赖 OCR 相关 Kit (CoreVisionKit / ImageKit)。
//  依赖: 无 — 本文件零 Kit 依赖; 实现由 entry 组合根注入。
//  数据流: EntryAbility.onCreate → OcrRecognizerRegistry.install(impl)
//          → OcrTool.recognize* → OcrRecognizerRegistry.require().recognize(uri)
//  约束: 本文件不得 import 任何 Kit; 实现文件放在 UI 进程 (entry), 且不进任何 barrel。
// ============================================================================

// 单次 OCR 的文本结果。confidence = 0 表示实现未暴露置信度 (未知)。
export interface OcrTextResult {
  text: string;
  confidence: number;
}

// OCR 能力端口: 一个 URI 进, 一段纯文本出。实现负责全部 Kit 细节。
export interface OcrRecognizer {
  recognize(uri: string): Promise<OcrTextResult>;
  isAvailable(): boolean;
}

// 进程内注册表: 组合根 (EntryAbility.onCreate) 安装唯一实现, 消费方按契约取用。
export class OcrRecognizerRegistry {
  private static impl: OcrRecognizer | null = null;

  static install(impl: OcrRecognizer): void {
    OcrRecognizerRegistry.impl = impl;
  }

  static isInstalled(): boolean {
    return OcrRecognizerRegistry.impl !== null;
  }

  static require(): OcrRecognizer {
    const impl: OcrRecognizer | null = OcrRecognizerRegistry.impl;
    if (impl === null) {
      throw new Error('OCR 能力未初始化（OcrRecognizerRegistry 未安装）');
    }
    return impl;
  }
}
